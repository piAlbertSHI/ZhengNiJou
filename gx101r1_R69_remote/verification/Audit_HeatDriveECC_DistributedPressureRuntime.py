"""Verify actual distributed commands in completed arms, never grant a seed."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Cycle import metrics
from Audit_HeatDriveECC_ColdPumpPressureProbes import audit_arm as pressure_arm
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def check_equations(live, delayed, viscosity, resistance, target, command, contract):
    T = np.asarray(contract['property_temperature_K'])
    nu = np.asarray(contract['kinematic_viscosity_m2_s'])
    coefficients = np.asarray(contract['segment_coefficients_MPa_per_kgps_per_m2ps'])
    if (live.shape != delayed.shape or live.shape != viscosity.shape or live.shape[0] != 21
            or coefficients.shape != (21,) or T.shape != nu.shape or np.any(np.diff(T) <= 0)
            or np.any(nu <= 0) or not all(np.isfinite(v).all() for v in
                                        (live, delayed, viscosity, resistance, target, command))):
        raise ValueError('Invalid finite distributed coordinates')
    predicted_nu = np.interp(delayed, T, nu)
    predicted_r = coefficients @ predicted_nu
    predicted_command = -target * predicted_r
    errors = {
        'one_step_delay_max_K': float(np.max(abs(delayed[:, 1:]-live[:, :-1]))),
        'native_nu_interpolation_max_m2_s': float(np.max(abs(viscosity-predicted_nu))),
        'distributed_resistance_max_MPa_per_kgps': float(np.max(abs(resistance-predicted_r))),
        'pressure_command_formula_max_MPa': float(np.max(abs(command-predicted_command))),
    }
    gates = dict(delay=errors['one_step_delay_max_K'] <= 1e-9,
                 viscosity=errors['native_nu_interpolation_max_m2_s'] <= 1e-14,
                 resistance=errors['distributed_resistance_max_MPa_per_kgps'] <= 1e-9,
                 command=errors['pressure_command_formula_max_MPa'] <= 1e-10,
                 property_domain=bool(np.all((delayed >= T[0]) & (delayed <= T[-1]))))
    return errors, gates


def audit_arm(folder):
    completion = read_json(folder/'arm_completion.json')
    contract = read_json(folder/'distributed_pressure_ff_contract.json')
    path = folder/'observations.mat'
    if (completion['observation_sha256'] != sha256(path) or not contract['simulation_run']
            or len(contract['sources']) != 21 or contract['legacy_reference_multiplier_used']
            or completion.get('production_recovery_allowed') is not False):
        raise ValueError('Completed arm integrity/controller contract is invalid')
    with h5py.File(path) as f, h5py.File(folder/'configuration.mat') as cfg:
        signals = {}
        time = f['signals/distributed_target_flow_kg_s/time_s'][:].reshape(-1)
        if (not np.allclose(time, np.arange(10001)*.001, rtol=0, atol=1e-9)
                or abs(contract['causal_delay_s']-.001) > 1e-12):
            raise ValueError('Require the complete unchanged 10 s solver clock')
        for name, row in f['signals'].items():
            if not np.array_equal(row['time_s'][:].reshape(-1), time):
                raise ValueError('Signal clock mismatch: '+name)
            signals[name] = row['values'][:]
        get = lambda n: signals['distributed_'+n]
        live = get('fluid_temperature21_K')
        errors, gates = check_equations(live, get('delayed_temperature21_K'),
            get('kinematic_viscosity21_m2_s'), get('bed_resistance_MPa_per_kgps')[0],
            get('target_flow_kg_s')[0], get('pressure_feedforward_MPa')[0], contract)
        lookup = {r['block']: i for i, r in enumerate(contract['sources'])}
        if len(lookup) != 21:
            raise ValueError('Duplicate native source paths')
        native_errors = []
        for ref in f['native'][:].reshape(-1):
            row = f[ref]
            decode = lambda d: ''.join(chr(int(v)) for v in d[:].reshape(-1))
            block, variable = decode(row['block_path']), decode(row['state_name'])
            if block in lookup and variable == 'T_I':
                if decode(row['unit']) != 'K' or not np.array_equal(row['time_s'][:].reshape(-1), time):
                    raise ValueError('Native source coordinate mismatch')
                native_errors.append(float(np.max(abs(row['values'][:].reshape(-1)-live[lookup[block]]))))
        if len(native_errors) != 21:
            raise ValueError('Missing native source authority')
        errors['probe_vs_native_T_I_max_K'] = max(native_errors)
        gates['native_source_match'] = max(native_errors) <= 1e-9
        actual_ff = signals['stage4_dynamic_feedforward'][0]
        errors['command_authority_max_MPa'] = float(np.max(abs(actual_ff-get('pressure_feedforward_MPa')[0])))
        gates['command_authority'] = errors['command_authority_max_MPa'] <= 1e-10
        performance, solids, flows = metrics(signals, cfg['options'], time, origin=0)
        # SMA's mature sensor orientation is negative. A universal q>0 test
        # would falsely reject it; retain the original magnitude gates and
        # do not claim this subset establishes every route's direction.
        phase_pass = all(0 <= s['all_node_phase_min'] <= s['all_node_phase_max'] <= 1 for s in solids.values())
    return dict(arm=completion['arm'], execution_commit=completion['execution_commit'],
        observation_sha256=sha256(path), controller_contract_sha256=sha256(folder/'distributed_pressure_ff_contract.json'),
        samples=len(time), equation_errors=errors, equation_gates=gates,
        distributed_controller_runtime_pass=all(gates.values()), settled_flows=flows,
        selected_flow_gates_pass=all(r['selected_flow_gate'] for r in flows),
        complete_route_direction_audit=False,
        pressure_boundary=pressure_arm(folder.parent,completion['arm'],0,10),
        solid_balances=solids, phase_bounds_pass=phase_pass,
        solid_energy_pass=all(s['selected_solid_energy_gate'] for s in solids.values()),
        performance=performance, full_package_collection_verified=False,
        all_mechanism_gates_evaluated=False, production_recovery_allowed=False, seed_authority_granted=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--arm-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--baseline-arm-root', type=Path)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Never overwrite evidence')
    result = audit_arm(args.arm_root)
    if args.baseline_arm_root:
        folder=args.baseline_arm_root
        completion=read_json(folder/'arm_completion.json')
        if completion['observation_sha256'] != sha256(folder/'observations.mat'):
            raise ValueError('Baseline arm hash mismatch')
        with h5py.File(folder/'observations.mat') as f, h5py.File(folder/'configuration.mat') as cfg, \
                h5py.File(args.arm_root/'configuration.mat') as current:
            keys=('se_stage2_pressure_pi_kp_MPa_per_kgps','se_stage4_pressure_pi_kp_MPa_per_kgps',
                  'se_stage4_pressure_pi_ki_MPa_per_kgps_s','pressure_pi_error_filter_tau_s')
            for key in keys:
                if not np.array_equal(cfg['options/branch/'+key][:],current['options/branch/'+key][:]):
                    raise ValueError('Baseline controller parameter differs: '+key)
            signals={name:row['values'][:] for name,row in f['signals'].items()}
            t=f['signals/mass_flow_v4_hot_inlet_kgps/time_s'][:].reshape(-1)
            _,_,flows=metrics(signals,cfg['options'],t,origin=0)
        result['legacy_same_cold_window_comparison']=dict(
            baseline_observation_sha256=completion['observation_sha256'],
            baseline_settled_flows=flows,PI_parameters_identical=True,
            not_a_periodic_or_Table4_comparison=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
    return 0 if result['distributed_controller_runtime_pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
