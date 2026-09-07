"""Recompute each finite-wall interval without subtracting numerical defects."""
import argparse
import json
import math
from pathlib import Path

from Audit_HeatDriveECC_ChamberStepConvergence import PHYSICAL_SHA, TOPOLOGY_SHA
from Audit_HeatDriveECC_DualChamberSwitchResult import read_case, audit_case
from Audit_HeatDriveECC_DualPipeResult import verify_parameters, momentum_audit
from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def verify_wall(meta):
    verify_parameters(meta, wall_model=True)
    contract = meta['wall_contract']
    expected = dict(capacity_each_J_K=math.pi/4*((.0032+.001)**2-.0032**2)*.2*1.8e6,
                    conductance_each_W_K=3.66*math.pi*.2*.60, initial_temperature_K=340,
                    external_heat_flow_W=0, wall_cp_reference_J_kgK=500)
    if any(not math.isclose(contract[k], v, rel_tol=1e-14, abs_tol=1e-14) for k, v in expected.items()):
        raise ValueError('Wall constitutive contract changed')
    for field in ('actual_wall_parameters', 'actual_wall_link_parameters'):
        if len(meta[field]) != 2:
            raise ValueError('Missing paired wall components')
        for record in meta[field]:
            values = record['values']
            if field == 'actual_wall_parameters':
                numbers = dict(mass=expected['capacity_each_J_K']/500, sp_heat=500, T=340)
                strings = dict(mass_unit='kg', sp_heat_unit='J/(K*kg)', T_unit='K',
                               T_specify='on', T_priority='High',
                               mass_type='foundation.enum.constant_variable.constant', num_ports='foundation.enum.numPorts2.one')
            else:
                numbers = dict(area=1, thickness=1, th_cond=expected['conductance_each_W_K'])
                strings = dict(area_unit='m^2', thickness_unit='m', th_cond_unit='W/(K*m)',
                               thermal_type='foundation.enum.ConstantVariableTabulated.Constant',
                               wall_geometry='foundation.enum.ConductionWallGeometry.Planar')
            if (any(not math.isclose(float(values[k]), v, rel_tol=1e-14, abs_tol=1e-14) for k,v in numbers.items())
                    or any(values[k] != v for k,v in strings.items())):
                raise ValueError('Actual wall parameters changed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite wall evidence')
    base = args.repo/'outputs_storage_audit'
    root = base/'dual_pipe_wall_20260907_v2'
    trial_path = root/'dual_switch_result.json'
    trial = json.loads(trial_path.read_text(encoding='utf-8-sig'))
    topology = base/'tl_domain_energy_tables_20260906/tl_domain_metadata.json'
    component = root/'build/+ecc_inventory/conservative_chamber.ssc'
    if (trial['schema'] != 'heatdrive_ecc_dual_chamber_switch_trial_v9' or not trial['collection_pass']
            or len(trial['cases']) != 6 or trial['failed_cases'] or not trial['wall_model']
            or trial['execution_commit'] != '3a8f5f22070ba917eb994cd0982e0c48bd220973'
            or trial['production_checkpoint_loaded'] or trial['production_model_changed'] or trial['production_recovery_allowed']
            or sha256(topology) != TOPOLOGY_SHA or sha256(Path(trial['source_options_path'])) != PHYSICAL_SHA
            or sha256(component) != sha256(args.repo/'verification/simscape_inventory_pipe/+ecc_inventory/conservative_chamber.ssc')):
        raise ValueError('Wall trial source or scope changed')
    data = json.loads(topology.read_text(encoding='utf-8-sig'))
    water = next(r for r in data['settings_tables'] if r['block_path'].endswith('/SMA_ThermalLiquidSettings'))
    table = energy_tables(water['parameters'])
    rows, trace_count = [], 0
    hashes = dict(trial=sha256(trial_path), topology=sha256(topology), component=sha256(component))
    keys = [(mode, step) for mode in ('none', 'isentropic') for step in (.001, .0005, .00025)]
    for i, key in enumerate(keys, 1):
        path = root/f'case_{i}.mat'
        meta, t, p = read_case(path, finite_transition=True, pipe_model=True, wall_model=True)
        if (meta != trial['cases'][i-1] or (meta['power_mode'],meta['local_step_s']) != key
                or meta['formulation'] != 'conservative' or meta['valve_transition_s'] != 0):
            raise ValueError('Incomplete or unpaired wall trial')
        verify_wall(meta)
        row = audit_case(meta, t, p, table, finite_transition=True, pipe_model=True, wall_model=True)
        row.update(momentum_audit(p))
        row['dual_inventory_closure_pass'] &= row['momentum_pressure_pass'] and row['finite_pipe_loss_observed']
        rows.append(row)
        trace_count += sum(len(v) for v in p.values())
        hashes[f'case_{i}'] = sha256(path)
    result = dict(schema='heatdrive_ecc_dual_pipe_wall_audit_v1', computation_complete=True,
                  actual_simscape_cases=6, actual_scalar_trace_count=trace_count,
                  trial_execution_commit=trial['execution_commit'], wall_contract=trial['wall_contract'],
                  cases=rows, input_sha256=hashes, mass_absolute_gate_kg=1e-15, energy_absolute_gate_J=1e-8,
                  all_inventory_pass=all(r['dual_inventory_closure_pass'] for r in rows),
                  all_wall_heat_transfer_pass=all(r['wall_heat_transfer_pass'] for r in rows),
                  all_spatial_port_identities_pass=all(r['spatial_port_identities_pass'] for r in rows),
                  mass_max_abs_residual_kg=max(v['mass_max_abs_residual_kg'] for r in rows for v in r['ledgers'].values()),
                  energy_max_abs_residual_J=max(v['energy_max_abs_residual_J'] for r in rows for v in r['ledgers'].values()),
                  production_model_changed=False, production_recovery_allowed=False,
                  whole_model_first_law_verified=False, table4_reproduction_claim=False, omitted_event_intervals=0)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('cases','input_sha256')}, indent=2))


if __name__ == '__main__':
    main()
