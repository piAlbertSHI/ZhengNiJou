"""Retain every interval while auditing open-flow inventory and external ports."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_ChamberStepConvergence import PHYSICAL_SHA, TOPOLOGY_SHA
from Audit_HeatDriveECC_ConservativeChamberResult import MASS_ATOL_KG, ENERGY_ATOL_J
from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_NativeWindowLedger import validate_grid
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field


TRIAL_COMMIT = 'a85c89b700a296d19ac4a6c0b9043c4432faf416'


def balance(time, mass, energy, mass_flow, power):
    arrays = [np.asarray(a, dtype=float) for a in (time, mass, energy, mass_flow, power)]
    t, m, u, mdot, q = arrays
    if (t.ndim != 1 or len(t) < 2 or any(a.shape != t.shape for a in arrays)
            or not np.isfinite(arrays).all() or np.any(np.diff(t) <= 0) or np.any(m <= 0)):
        raise ValueError('Invalid open-flow ledger inputs')
    dt = np.diff(t)
    dm, de = mdot[1:]*dt, q[1:]*dt
    mass_error, energy_error = m-m[0]-np.r_[0, np.cumsum(dm)], u-u[0]-np.r_[0, np.cumsum(de)]
    return dict(mass_max_abs_residual_kg=float(abs(mass_error).max()), energy_max_abs_residual_J=float(abs(energy_error).max()),
                mass_final_residual_kg=float(mass_error[-1]), energy_final_residual_J=float(energy_error[-1]),
                mass_interval_max_abs_residual_kg=float(abs(np.diff(m)-dm).max()),
                energy_interval_max_abs_residual_J=float(abs(np.diff(u)-de).max()),
                integrated_mass_kg=float(dm.sum()), integrated_energy_J=float(de.sum()),
                endpoint_mass_change_kg=float(m[-1]-m[0]), endpoint_energy_change_J=float(u[-1]-u[0]),
                mass_closure_pass=bool(np.all(abs(mass_error) <= MASS_ATOL_KG)),
                energy_closure_pass=bool(np.all(abs(energy_error) <= ENERGY_ATOL_J)))


def command(time, mode, step):
    if mode not in ('forward', 'reverse', 'reversal') or step not in (.001, .0005, .00025):
        raise ValueError('Unsupported flow command contract')
    index = np.rint(np.asarray(time)/step).astype(int)
    if mode == 'forward':
        return np.full(index.shape, .0002)
    if mode == 'reverse':
        return np.full(index.shape, -.0002)
    return np.where(index < round(.5/step), .0002, -.0002)


def temperature_coordinate_balance(time, temperature, pressure, volume, mass_flow, power, table):
    arrays = [np.asarray(a, dtype=float) for a in (time, temperature, pressure, mass_flow, power)]
    t, temp, p, mdot, q = arrays
    if (t.ndim != 1 or len(t) < 2 or any(a.shape != t.shape for a in arrays)
            or not np.isfinite(arrays).all() or np.any(np.diff(t) <= 0)
            or np.ptp(p) > 1e-4 or not np.isfinite(volume) or volume <= 0):
        raise ValueError('Temperature-coordinate diagnosis requires a finite constant-pressure path')
    grid = table['rho'].grid[0]
    index = np.clip(np.searchsorted(grid, temp, side='right')-1, 0, len(grid)-2)
    low, high = np.column_stack((grid[index], p)), np.column_stack((grid[index+1], p))
    width = grid[index+1]-grid[index]
    rho_t = (table['rho'](high)-table['rho'](low))/width
    u_t = (table['u'](high)-table['u'](low))/width
    point = np.column_stack((temp, p))
    rho, u = table['rho'](point), table['u'](point)
    dt, dtemp = np.diff(t), np.diff(temp)
    derivative_mass = volume*rho_t[1:]*dtemp
    derivative_energy = volume*(rho_t*u+rho*u_t)[1:]*dtemp
    mass_bridge = np.diff(volume*rho)-derivative_mass
    energy_bridge = np.diff(volume*rho*u)-derivative_energy
    knot_intervals = np.flatnonzero(np.diff(index))
    return dict(temperature_cell_change_count=len(knot_intervals),
                temperature_cell_change_right_times_s=t[knot_intervals+1].tolist(),
                coefficient_mass_interval_max_residual_kg=float(np.max(abs(derivative_mass-mdot[1:]*dt))),
                coefficient_energy_interval_max_residual_J=float(np.max(abs(derivative_energy-q[1:]*dt))),
                endpoint_minus_temperature_coordinate_mass_kg=float(mass_bridge.sum()),
                endpoint_minus_temperature_coordinate_energy_J=float(energy_bridge.sum()),
                compiler_state_selection_directly_observed=False,
                scope='Observed trajectory matches temperature-coordinate BE chain rule; not a replacement physical gate')


def read_case(path):
    units = dict(T_I='K', p_I='Pa', rho_I='kg/m^3', u_I='J/kg', mdot_A='kg/s', mdot_B='kg/s',
                 Phi_A='W', Phi_B='W', Q_H='W', stored_mass='kg', stored_energy='J', power='W')
    with h5py.File(path, 'r') as f:
        meta = json.loads(text_field(f['record_json']))
        packets, common_time = {}, None
        for ref in f['packets'][:].flat:
            block = f[ref]
            role = text_field(block['role'])
            if role in packets:
                raise ValueError('Duplicate port ledger role')
            traces = {}
            for trace_ref in block['traces'][:].flat:
                trace = f[trace_ref]
                name, unit = text_field(trace['name']), text_field(trace['unit'])
                time, value = trace['time_s'][:].reshape(-1), trace['values'][:].reshape(-1)
                validate_grid(time, 0, 1, meta['local_step_s'])
                if common_time is None:
                    common_time = time
                if name in traces or name not in units or value.shape != time.shape or not np.array_equal(time, common_time):
                    raise ValueError('Duplicate variable, shape error or nonidentical native grid')
                traces[name] = convert(value, unit, units[name])
            packets[role] = traces
    expected = dict(chamber={'T_I', 'p_I', 'rho_I', 'u_I', 'mdot_A', 'mdot_B', 'Phi_A', 'Phi_B', 'Q_H'},
                    flow_source={'mdot_A', 'mdot_B', 'Phi_A', 'Phi_B', 'power'},
                    hot_reservoir={'mdot_A', 'Phi_A', 'p_I', 'T_I'}, cold_reservoir={'mdot_A', 'Phi_A', 'p_I', 'T_I'})
    if meta['formulation'] == 'conservative':
        expected['chamber'].update(('stored_mass', 'stored_energy'))
    if set(packets) != set(expected) or any(set(packets[k]) != v for k,v in expected.items()):
        raise ValueError('Incomplete native component/port coverage')
    return meta, common_time, packets


def audit_case(meta, time, packets, table):
    if (meta['formulation'] not in ('native', 'conservative') or meta['local_solver_enabled'] != 'on'
            or meta['local_solver'] != 'NE_BACKWARD_EULER_ADVANCER' or meta['global_solver'] != 'ode3'
            or meta['local_step_s'] != meta['global_step_s'] or meta['initial_temperature_K'] != 340
            or meta['pressure_Pa'] != 2.5e6 or meta['hot_reservoir_K'] != 380 or meta['cold_reservoir_K'] != 300
            or meta['flow_magnitude_kg_s'] != .0002 or meta['stop_s'] != 1 or meta['reversal_time_s'] != .5):
        raise ValueError('Trial configuration changed')
    c, source, hot, cold = [packets[k] for k in ('chamber', 'flow_source', 'hot_reservoir', 'cold_reservoir')]
    expected = command(time, meta['mode'], meta['local_step_s'])
    if (max(np.max(abs(c['mdot_A']-expected)), np.max(abs(source['mdot_A']-expected))) > 1e-15
            or np.max(abs(c['Q_H'])) > 1e-9 or np.max(abs(source['power'])) > 1e-9):
        raise ValueError('Flow direction, switch timing or zero-head adiabatic contract failed')
    if (abs(c['T_I'][0]-340) > 1e-9 or max(np.max(abs(v['p_I']-2.5e6)) for v in (c, hot, cold)) > 1e-4
            or np.max(abs(hot['T_I']-380)) > 1e-9 or np.max(abs(cold['T_I']-300)) > 1e-9):
        raise ValueError('Initial or reservoir boundary conditions changed')
    point = np.column_stack((c['T_I'], c['p_I']))
    if np.max(abs(table['rho'](point)-c['rho_I'])) > 1e-8 or np.max(abs(table['u'](point)-c['u_I'])) > 1e-6:
        raise ValueError('Native table lookup differs from frozen water domain')
    m, u = c['rho_I']*meta['volume_m3'], c['rho_I']*meta['volume_m3']*c['u_I']
    local_mass, local_power = c['mdot_A']+c['mdot_B'], c['Phi_A']+c['Phi_B']+c['Q_H']
    external_mass = -hot['mdot_A']-cold['mdot_A']
    external_power = -hot['Phi_A']-cold['Phi_A']+source['power']
    spatial_mass = [hot['mdot_A']+source['mdot_A'], source['mdot_B']+c['mdot_A'], c['mdot_B']+cold['mdot_A'],
                    source['mdot_A']+source['mdot_B']]
    spatial_energy = [hot['Phi_A']+source['Phi_A'], source['Phi_B']+c['Phi_A'], c['Phi_B']+cold['Phi_A'],
                      source['Phi_A']+source['Phi_B']+source['power']]
    row = dict(meta, sample_count=len(time), local_ledger=balance(time, m, u, local_mass, local_power),
               external_ledger=balance(time, m, u, external_mass, external_power),
               spatial_mass_max_abs_kg_s=float(np.max(abs(np.array(spatial_mass)))),
               spatial_energy_max_abs_W=float(np.max(abs(np.array(spatial_energy)))),
               final_temperature_K=float(c['T_I'][-1]), min_temperature_K=float(c['T_I'].min()), max_temperature_K=float(c['T_I'].max()),
               max_measured_flow_source_power_W=float(np.max(abs(source['power']))),
               forward_sample_count=int(np.count_nonzero(c['mdot_A'] > 0)), reverse_sample_count=int(np.count_nonzero(c['mdot_A'] < 0)),
               positive_flow_cold_port_is_outlet=bool(np.all(c['mdot_B'][expected > 0] < 0)),
               negative_flow_cold_port_is_inlet=bool(np.all(c['mdot_B'][expected < 0] > 0)))
    row['spatial_port_identities_pass'] = row['spatial_mass_max_abs_kg_s'] <= 1e-15 and row['spatial_energy_max_abs_W'] <= 1e-9
    if meta['formulation'] == 'conservative':
        row['temperature_coordinate_diagnostic'] = temperature_coordinate_balance(
            time, c['T_I'], c['p_I'], meta['volume_m3'], local_mass, local_power, table)
        row['inventory_aliases_match'] = bool(np.max(abs(c['stored_mass']-m)) <= MASS_ATOL_KG
                                               and np.max(abs(c['stored_energy']-u)) <= ENERGY_ATOL_J)
        row['open_flow_inventory_closure_pass'] = (row['spatial_port_identities_pass'] and row['inventory_aliases_match']
            and row['positive_flow_cold_port_is_outlet'] and row['negative_flow_cold_port_is_inlet']
            and all(row[k]['mass_closure_pass'] and row[k]['energy_closure_pass'] for k in ('local_ledger', 'external_ledger')))
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite audit evidence')
    base = args.repo/'outputs_storage_audit'
    trial_dir = base/'chamber_open_flow_20260907_v2/trial'
    trial_path = trial_dir/'open_flow_result.json'
    trial = json.loads(trial_path.read_text(encoding='utf-8-sig'))
    topology_path = base/'tl_domain_energy_tables_20260906/tl_domain_metadata.json'
    sealed_path = base/'conservative_chamber_20260907_v4/conservative_audit_v1.json'
    sealed = json.loads(sealed_path.read_text())
    compiled = trial_dir/'build/+ecc_inventory/conservative_chamber.ssc'
    if (sha256(topology_path).upper() != TOPOLOGY_SHA or sha256(Path(trial['source_options_path'])).upper() != PHYSICAL_SHA
            or sha256(compiled) != sealed['input_sha256']['compiled_source']
            or not sealed['sealed_component_inventory_closure_verified'] or trial['schema'] != 'heatdrive_ecc_chamber_open_flow_trial_v1'
            or not trial['collection_pass'] or len(trial['cases']) != 18 or trial['execution_commit'] != TRIAL_COMMIT
            or trial['production_model_changed'] or trial['production_checkpoint_loaded'] or trial['production_recovery_allowed']):
        raise ValueError('Frozen source, model identity or scope changed')
    topology = json.loads(topology_path.read_text(encoding='utf-8-sig'))
    water = next(r for r in topology['settings_tables'] if r['block_path'].endswith('/SMA_ThermalLiquidSettings'))
    table = energy_tables(water['parameters'])
    keys = [(f,m,s) for f in ('native', 'conservative') for m in ('forward', 'reverse', 'reversal') for s in (.001,.0005,.00025)]
    rows, hashes = [], dict(contract=sha256(trial_path), topology=sha256(topology_path), sealed_audit=sha256(sealed_path), component=sha256(compiled))
    for index, key in enumerate(keys, 1):
        path = trial_dir/f'case_{index}.mat'
        meta, time, packets = read_case(path)
        if (meta != trial['cases'][index-1] or tuple(meta[k] for k in ('formulation', 'mode', 'local_step_s')) != key
                or meta['source_settings'] != water['block_path'] or meta['volume_m3'] != 1.6084954386379741e-6):
            raise ValueError('Missing or unpaired flow case')
        rows.append(audit_case(meta, time, packets, table))
        hashes[f'case_{index}'] = sha256(path)
    result = dict(schema='heatdrive_ecc_chamber_open_flow_audit_v1', computation_complete=True, cases=rows,
                  input_sha256=hashes, trial_execution_commit=TRIAL_COMMIT, actual_simscape_cases=18,
                  actual_native_scalar_trace_count=414, mass_absolute_gate_kg=MASS_ATOL_KG, energy_absolute_gate_J=ENERGY_ATOL_J,
                  tested_open_flow_inventory_closure_verified=all(r['open_flow_inventory_closure_pass'] for r in rows[9:]),
                  corrected_external_mass_max_residual_kg=max(r['external_ledger']['mass_max_abs_residual_kg'] for r in rows[9:]),
                  corrected_external_energy_max_residual_J=max(r['external_ledger']['energy_max_abs_residual_J'] for r in rows[9:]),
                  all_spatial_port_identities_pass=all(r['spatial_port_identities_pass'] for r in rows),
                  omitted_event_intervals=0, nonzero_pump_head_verified=False, full_sma_se_switching_verified=False,
                  whole_model_first_law_verified=False, production_recovery_allowed=False, table4_reproduction_claim=False)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('cases', 'input_sha256')}, indent=2))


if __name__ == '__main__':
    main()
