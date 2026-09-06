"""Audit genuine local BE step interventions against the same-equation ODE.

The DOP853 reference is an independent integrator, not independent experimental
validation. A sealed, heated component cannot qualify a switched whole system.
"""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np
from scipy.integrate import solve_ivp

from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_NativeWindowLedger import validate_grid
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field


TRIAL_COMMIT = 'b4e6438d0917420802036a39f14d0f4cd9897eb4'
TOPOLOGY_SHA = 'C5E2170D57E6010C7012575610F68C1AFD9E214D50B9CCB4901FCA7607367D46'
PHYSICAL_SHA = '6E5D15B2C2F67799748187F1BD15E0CBA1B08C7BCF1A5C1D1639B35AFE6CCC13'


def sealed_rhs(table, volume, heat):
    if not np.isfinite([volume, heat]).all() or volume <= 0:
        raise ValueError('Invalid chamber volume or input heat')

    def rhs(_time, state):
        temp, pressure = state
        point = np.array([[temp, pressure]])
        rho, cp, alpha, beta = [float(table[k](point)[0]) for k in ('rho', 'cp', 'alpha', 'beta')]
        # mdot=0 gives dp=beta*alpha*dT. Substitute into the installed
        # dUdp/dUdT energy equation; the h*alpha terms cancel exactly.
        capacity = volume * (rho * cp - temp * beta * alpha**2)
        if not np.isfinite(capacity) or capacity <= 0:
            raise ValueError('Nonpositive sealed-chamber effective heat capacity')
        dtemp = heat / capacity
        return [dtemp, beta * alpha * dtemp]

    return rhs


def reference_solution(table, volume, heat, temp, pressure, fine=False):
    result = solve_ivp(sealed_rhs(table, volume, heat), (0, 1), [temp, pressure],
                       method='DOP853', rtol=2e-13 if fine else 2e-11,
                       atol=[2e-12, 1e-7] if fine else [2e-10, 1e-5],
                       max_step=.001 if fine else .01, dense_output=True)
    if not result.success or result.t[-1] != 1 or not np.isfinite(result.y).all():
        raise ValueError('Independent reference integration failed')
    return result


def convergence_order(errors):
    e = np.asarray(errors, dtype=float)
    if e.shape != (3,) or not np.isfinite(e).all() or np.any(e <= 0):
        raise ValueError('Three positive finite refinement errors required')
    orders = np.log2(e[:-1] / e[1:])
    return orders.tolist(), bool(np.all((orders >= .8) & (orders <= 1.2)))


def read_case(path):
    with h5py.File(path, 'r') as f:
        meta = json.loads(text_field(f['record_json']))
        rows = []
        for ref in f['traces'][:].flat:
            row = f[ref]
            rows.append((text_field(row['name']), text_field(row['unit']),
                         row['time_s'][:].reshape(-1), row['values'][:].reshape(-1)))
    units = dict(T_I='K', p_I='Pa', rho_I='kg/m^3', u_I='J/kg', h_I='J/kg',
                 mdot_A='kg/s', Phi_A='W', Q_H='W')
    if len(rows) != len(units) or {r[0] for r in rows} != set(units):
        raise ValueError('Missing or duplicated native chamber coordinates')
    values = {}
    for name, unit, time, data in rows:
        validate_grid(time, 0, 1, meta['local_step_s'])
        if data.shape != time.shape or not np.isfinite(data).all():
            raise ValueError('Invalid native values')
        if not np.array_equal(time, rows[0][2]):
            raise ValueError('Native coordinates do not share a grid')
        values[name] = convert(data, unit, units[name])
    return meta, rows[0][2], values


def audit_case(meta, time, values, table, reference):
    if (meta['local_solver_enabled'] != 'on' or meta['local_solver'] != 'NE_BACKWARD_EULER_ADVANCER'
            or meta['local_step_s'] not in (.001, .0005, .00025)
            or meta['global_solver'] != 'ode3' or meta['global_step_s'] != meta['local_step_s']
            or meta['stop_s'] != 1 or meta['initial_pressure_Pa'] != 1e6
            or meta['heat_source_command_W'] != -10 or meta['expected_Q_H_W'] != 10):
        raise ValueError('Unexpected experiment or physical solver contract')
    if (np.max(abs(values['mdot_A'])) > 1e-15 or np.max(abs(values['Phi_A'])) > 1e-9
            or np.max(abs(values['Q_H'] - 10)) > 1e-9):
        raise ValueError('Trial is not sealed with +10 W measured input')
    temp, pressure, rho, u, h = [values[k] for k in ('T_I', 'p_I', 'rho_I', 'u_I', 'h_I')]
    if abs(temp[0] - meta['initial_temperature_K']) > 1e-9 or abs(pressure[0] - 1e6) > 1e-4:
        raise ValueError('Initial conditions changed across step interventions')
    point = np.column_stack((temp, pressure))
    if (np.max(abs(table['rho'](point) - rho)) > 1e-8 or np.max(abs(table['u'](point) - u)) > 1e-6):
        raise ValueError('Independent tables do not match the actual native properties')
    cp, alpha, beta = [table[k](point) for k in ('cp', 'alpha', 'beta')]
    volume = meta['volume_m3']
    be_mass = volume * rho[1:] * (np.diff(pressure)/beta[1:] - alpha[1:] * np.diff(temp))
    be_energy = volume * ((rho*h/beta-temp*alpha)[1:] * np.diff(pressure)
                          + ((cp-h*alpha)*rho)[1:] * np.diff(temp))
    input_energy = values['Q_H'][1:] * np.diff(time)
    ref = reference.sol(time)
    error = abs(np.column_stack((temp, pressure)).T - ref)
    ref_points = reference.y[:, [0, -1]].T
    ref_rho, ref_u = table['rho'](ref_points), table['u'](ref_points)
    return dict(local_step_s=meta['local_step_s'], sample_count=len(time),
                initial_temperature_K=meta['initial_temperature_K'], final_temperature_K=float(temp[-1]),
                final_pressure_Pa=float(pressure[-1]), measured_heat_J=float(input_energy.sum()),
                BE_energy_max_interval_residual_J=float(np.max(abs(input_energy-be_energy))),
                BE_mass_max_interval_residual_kg=float(np.max(abs(be_mass))),
                native_endpoint_energy_residual_J=float(input_energy.sum()-volume*(rho[-1]*u[-1]-rho[0]*u[0])),
                native_endpoint_mass_change_kg=float(volume*(rho[-1]-rho[0])),
                reference_endpoint_energy_residual_J=float(10-volume*np.diff(ref_rho*ref_u)[0]),
                reference_endpoint_mass_change_kg=float(volume*np.diff(ref_rho)[0]),
                max_temperature_error_K=float(error[0].max()), max_pressure_error_Pa=float(error[1].max()),
                final_temperature_error_K=float(error[0, -1]), final_pressure_error_Pa=float(error[1, -1]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Never overwrite audit evidence')
    root = args.repo/'outputs_storage_audit'
    trial_root = root/'isolated_chamber_steps_20260907/trial'
    contract_path = trial_root/'isolated_chamber_result.json'
    trial = json.loads(contract_path.read_text(encoding='utf-8-sig'))
    topology_path = root/'tl_domain_energy_tables_20260906/tl_domain_metadata.json'
    if (sha256(topology_path).upper() != TOPOLOGY_SHA
            or sha256(Path(trial['source_options_path'])).upper() != PHYSICAL_SHA
            or trial['schema'] != 'heatdrive_ecc_isolated_chamber_steps_v1'
            or not trial['collection_pass'] or len(trial['cases']) != 6
            or trial['execution_commit'] != TRIAL_COMMIT or trial['production_checkpoint_loaded']
            or trial['production_recovery_allowed'] or trial['whole_model_convergence_verified']):
        raise ValueError('Frozen input identity or diagnostic scope changed')
    topology = json.loads(topology_path.read_text(encoding='utf-8-sig'))
    water = next(r for r in topology['settings_tables'] if r['block_path'].endswith('/SMA_ThermalLiquidSettings'))
    table = energy_tables(water['parameters'])
    rows, groups, hashes = [], [], {'contract': sha256(contract_path), 'topology': sha256(topology_path)}
    for index, expected in enumerate(trial['cases'], 1):
        path = trial_root/f'case_{index}.mat'
        meta, time, values = read_case(path)
        if (meta != expected or meta['source_settings'] != water['block_path']
                or meta['volume_m3'] != 1.6084954386379741e-6
                or meta['initial_temperature_K'] != (300 if index <= 3 else 380)
                or meta['local_step_s'] != (.001, .0005, .00025)[(index-1) % 3]):
            raise ValueError('Paired case metadata changed')
        if index in (1, 4):
            common = (table, meta['volume_m3'], 10, meta['initial_temperature_K'], 1e6)
            coarse_ref, fine_ref = reference_solution(*common), reference_solution(*common, fine=True)
            query = np.linspace(0, 1, 4001)
            gap = abs(coarse_ref.sol(query)-fine_ref.sol(query)).max(axis=1)
            groups.append(dict(initial_temperature_K=meta['initial_temperature_K'],
                               reference_tolerance_gap_K=float(gap[0]), reference_tolerance_gap_Pa=float(gap[1])))
        rows.append(audit_case(meta, time, values, table, fine_ref))
        hashes[f'case_{index}'] = sha256(path)
    for group, subset in zip(groups, (rows[:3], rows[3:])):
        group['temperature_orders'], tpass = convergence_order([r['max_temperature_error_K'] for r in subset])
        group['pressure_orders'], ppass = convergence_order([r['max_pressure_error_Pa'] for r in subset])
        separated = (group['reference_tolerance_gap_K'] < subset[-1]['max_temperature_error_K']*.01
                     and group['reference_tolerance_gap_Pa'] < subset[-1]['max_pressure_error_Pa']*.01)
        group.update(reference_error_separated=bool(separated), observed_first_order=tpass and ppass and bool(separated))
    result = dict(schema='heatdrive_ecc_chamber_step_convergence_v1', computation_complete=True,
                  actual_simscape_case_count=6, trial_execution_commit=TRIAL_COMMIT, input_sha256=hashes,
                  physical_sha256=PHYSICAL_SHA, cases=rows, groups=groups,
                  isolated_step_convergence_verified=all(g['observed_first_order'] for g in groups),
                  reference_scope='Independent DOP853 integration of the same installed chamber equations',
                  step_intervention='Local BE and global ode3 steps changed together; constant input and no global dynamics',
                  full_device_first_law_verified=False, physical_mass_closure_verified=False,
                  whole_model_convergence_verified=False, production_recovery_allowed=False,
                  table4_reproduction_claim=False)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    print(json.dumps({k: result[k] for k in ('computation_complete', 'actual_simscape_case_count',
                                          'isolated_step_convergence_verified', 'groups')}, indent=2))


if __name__ == '__main__':
    main()
