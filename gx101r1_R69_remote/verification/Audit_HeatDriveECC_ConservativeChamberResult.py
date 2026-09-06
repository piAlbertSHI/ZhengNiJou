"""Audit paired native/conservative physical trials without authorizing recovery."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np
from scipy.optimize import root

from Audit_HeatDriveECC_ChamberStepConvergence import PHYSICAL_SHA, TOPOLOGY_SHA
from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_NativeWindowLedger import validate_grid
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field


TRIAL_COMMIT = '3484fa1dcc78753b6ad63d7ccad557203d286dfa'
MASS_ATOL_KG = 1e-15
ENERGY_ATOL_J = 1e-8


def closed_balance(time, density, specific_energy, volume, heat):
    time, density, specific_energy = [np.asarray(a, dtype=float) for a in (time, density, specific_energy)]
    if (time.ndim != 1 or len(time) < 2 or density.shape != time.shape or specific_energy.shape != time.shape
            or not np.isfinite([time, density, specific_energy]).all() or np.any(np.diff(time) <= 0)
            or np.any(density <= 0) or not np.isfinite([volume, heat]).all() or volume <= 0):
        raise ValueError('Invalid closed inventory input')
    mass = density * volume
    energy = mass * specific_energy
    dm = mass - mass[0]
    de = energy - energy[0] - heat * (time-time[0])
    return dict(mass_max_abs_residual_kg=float(abs(dm).max()), energy_max_abs_residual_J=float(abs(de).max()),
                mass_endpoint_change_kg=float(dm[-1]), energy_endpoint_excess_J=float(de[-1]),
                mass_closure_pass=bool(np.all(abs(dm) <= MASS_ATOL_KG)),
                energy_closure_pass=bool(np.all(abs(de) <= ENERGY_ATOL_J)))


def independent_endpoint(table, initial_temperature, initial_pressure, volume, heat, seconds=1):
    start = np.array([[initial_temperature, initial_pressure]])
    rho0, u0, cp0, beta0, alpha0 = [float(table[k](start)[0]) for k in ('rho', 'u', 'cp', 'beta', 'alpha')]
    target_u = u0 + heat*seconds/(rho0*volume)
    dt = heat*seconds/(rho0*volume*cp0)
    # Solve the two inventory algebraic constraints directly. No Simscape
    # trajectory or fitted reference endpoint enters this calculation.
    def residual(coordinates):
        point = np.array([[coordinates[0], coordinates[1]*1e6]])
        return [(float(table['rho'](point)[0])-rho0)/rho0,
                (float(table['u'](point)[0])-target_u)/max(abs(target_u), 1)]
    result = root(residual, [initial_temperature+dt, (initial_pressure+beta0*alpha0*dt)/1e6], tol=1e-10)
    if not result.success or not np.isfinite(result.x).all() or max(abs(np.asarray(residual(result.x)))) > 1e-11:
        raise ValueError('Independent mass-energy endpoint inversion failed')
    return np.array([result.x[0], result.x[1]*1e6])


def read_case(path):
    with h5py.File(path, 'r') as f:
        meta = json.loads(text_field(f['record_json']))
        raw = []
        for ref in f['traces'][:].flat:
            row = f[ref]
            raw.append((text_field(row['name']), text_field(row['unit']), row['time_s'][:].reshape(-1), row['values'][:].reshape(-1)))
    units = dict(T_I='K', p_I='Pa', rho_I='kg/m^3', u_I='J/kg', mdot_A='kg/s', mdot_B='kg/s', Phi_A='W', Phi_B='W', Q_H='W')
    if meta['formulation'] == 'conservative':
        units.update(stored_mass='kg', stored_energy='J')
    elif meta['formulation'] != 'native':
        raise ValueError('Unknown component formulation')
    if len(raw) != len(units) or {v[0] for v in raw} != set(units):
        raise ValueError('Wrong native trace coverage')
    values = {}
    for name, unit, time, value in raw:
        validate_grid(time, 0, 1, meta['local_step_s'])
        if value.shape != time.shape or not np.isfinite(value).all() or not np.array_equal(time, raw[0][2]):
            raise ValueError('Invalid native trace or time alignment')
        values[name] = convert(value, unit, units[name])
    return meta, raw[0][2], values


def audit_case(meta, time, values, table):
    if (meta['local_solver_enabled'] != 'on' or meta['local_solver'] != 'NE_BACKWARD_EULER_ADVANCER'
            or meta['local_step_s'] not in (.001, .0005, .00025) or meta['global_step_s'] != meta['local_step_s']
            or meta['global_solver'] != 'ode3' or meta['stop_s'] != 1
            or meta['initial_pressure_Pa'] != 2.5e6 or meta['expected_Q_H_W'] not in (-5, 5)
            or meta['heat_source_command_W'] != -meta['expected_Q_H_W']):
        raise ValueError('Unexpected paired trial contract')
    if (max(np.max(abs(values[k])) for k in ('mdot_A', 'mdot_B')) > 1e-15
            or max(np.max(abs(values[k])) for k in ('Phi_A', 'Phi_B')) > 1e-9
            or np.max(abs(values['Q_H']-meta['expected_Q_H_W'])) > 1e-9):
        raise ValueError('Closed-port constant-heat assumptions failed')
    temp, pressure, rho, u = [values[k] for k in ('T_I', 'p_I', 'rho_I', 'u_I')]
    if abs(temp[0]-meta['initial_temperature_K']) > 1e-9 or abs(pressure[0]-meta['initial_pressure_Pa']) > 1e-4:
        raise ValueError('Initial state not paired')
    points = np.column_stack((temp, pressure))
    if np.max(abs(table['rho'](points)-rho)) > 1e-8 or np.max(abs(table['u'](points)-u)) > 1e-6:
        raise ValueError('Native table values changed')
    volume = meta['volume_m3']
    balance = closed_balance(time, rho, u, volume, meta['expected_Q_H_W'])
    ref = independent_endpoint(table, meta['initial_temperature_K'], meta['initial_pressure_Pa'], volume, meta['expected_Q_H_W'])
    row = dict(meta, sample_count=len(time), **balance, final_temperature_K=float(temp[-1]), final_pressure_Pa=float(pressure[-1]),
               pressure_min_Pa=float(pressure.min()), pressure_max_Pa=float(pressure.max()),
               independent_endpoint_temperature_K=float(ref[0]), independent_endpoint_pressure_Pa=float(ref[1]),
               independent_endpoint_temperature_error_K=float(temp[-1]-ref[0]),
               independent_endpoint_pressure_error_Pa=float(pressure[-1]-ref[1]))
    if meta['formulation'] == 'conservative':
        row['stored_mass_alias_max_error_kg'] = float(np.max(abs(values['stored_mass']-rho*volume)))
        row['stored_energy_alias_max_error_J'] = float(np.max(abs(values['stored_energy']-rho*volume*u)))
        row['inventory_aliases_match'] = (row['stored_mass_alias_max_error_kg'] <= MASS_ATOL_KG
                                          and row['stored_energy_alias_max_error_J'] <= ENERGY_ATOL_J)
        row['independent_endpoint_match'] = (abs(row['independent_endpoint_temperature_error_K']) <= 1e-8
                                              and abs(row['independent_endpoint_pressure_error_Pa']) <= .01)
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite result evidence')
    root_dir = args.repo/'outputs_storage_audit'
    trial_dir = root_dir/'conservative_chamber_20260907_v4/trial'
    trial_path = trial_dir/'conservative_chamber_result.json'
    trial = json.loads(trial_path.read_text(encoding='utf-8-sig'))
    table_path = root_dir/'tl_domain_energy_tables_20260906/tl_domain_metadata.json'
    component = args.repo/'verification/simscape_inventory/+ecc_inventory/conservative_chamber.ssc'
    compiled_source = trial_dir/'build/+ecc_inventory/conservative_chamber.ssc'
    if (sha256(table_path).upper() != TOPOLOGY_SHA or sha256(Path(trial['source_options_path'])).upper() != PHYSICAL_SHA
            or sha256(component) != sha256(compiled_source) or not trial['collection_pass'] or len(trial['cases']) != 24
            or trial['schema'] != 'heatdrive_ecc_conservative_chamber_trial_v1' or trial['execution_commit'] != TRIAL_COMMIT
            or trial['production_model_changed'] or trial['production_checkpoint_loaded'] or trial['production_recovery_allowed']):
        raise ValueError('Frozen provenance or model boundary changed')
    tables = json.loads(table_path.read_text(encoding='utf-8-sig'))
    water = next(r for r in tables['settings_tables'] if r['block_path'].endswith('/SMA_ThermalLiquidSettings'))
    table = energy_tables(water['parameters'])
    keys = [(form, temp, heat, step) for form in ('native', 'conservative')
            for temp in (300, 380) for heat in (5, -5) for step in (.001, .0005, .00025)]
    rows, hashes = [], dict(trial=sha256(trial_path), topology=sha256(table_path), compiled_source=sha256(compiled_source))
    for index, key in enumerate(keys, 1):
        path = trial_dir/f'case_{index}.mat'
        meta, time, values = read_case(path)
        if (meta != trial['cases'][index-1] or tuple(meta[n] for n in ('formulation', 'initial_temperature_K', 'expected_Q_H_W', 'local_step_s')) != key
                or meta['source_settings'] != water['block_path'] or meta['volume_m3'] != 1.6084954386379741e-6):
            raise ValueError('Missing or nonpaired case')
        rows.append(audit_case(meta, time, values, table))
        hashes[f'case_{index}'] = sha256(path)
    corrected = rows[12:]
    result = dict(schema='heatdrive_ecc_conservative_chamber_audit_v1', computation_complete=True, cases=rows,
                  actual_simscape_cases=24, trial_execution_commit=TRIAL_COMMIT, input_sha256=hashes,
                  mass_absolute_gate_kg=MASS_ATOL_KG, energy_absolute_gate_J=ENERGY_ATOL_J,
                  corrected_mass_max_abs_residual_kg=max(r['mass_max_abs_residual_kg'] for r in corrected),
                  corrected_energy_max_abs_residual_J=max(r['energy_max_abs_residual_J'] for r in corrected),
                  sealed_component_inventory_closure_verified=all(r['mass_closure_pass'] and r['energy_closure_pass']
                      and r['inventory_aliases_match'] and r['independent_endpoint_match'] for r in corrected),
                  native_endpoint_mass_closure_pass_count=sum(r['mass_closure_pass'] for r in rows[:12]),
                  native_endpoint_energy_closure_pass_count=sum(r['energy_closure_pass'] for r in rows[:12]),
                  open_port_transport_verified=False, switched_network_verified=False,
                  whole_model_first_law_verified=False, production_recovery_allowed=False, table4_reproduction_claim=False)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('cases', 'input_sha256')}, indent=2))


if __name__ == '__main__':
    main()
