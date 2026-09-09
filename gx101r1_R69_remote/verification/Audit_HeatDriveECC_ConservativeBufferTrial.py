"""Independent endpoint inventory audit of the isolated buffer candidate."""
import argparse
from collections import Counter
import csv
import json
from pathlib import Path

import h5py
import numpy as np
from scipy.optimize import brentq

from Audit_HeatDriveECC_ColdChamberCycle import EXPERIMENT
from Audit_HeatDriveECC_ColdChamberRejection import read
from Audit_HeatDriveECC_ColdCoordinateSmoke import compare_initial, ledger
from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_NativeWindowLedger import validate_grid
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field


PRODUCER = 'bdc451f3751d0da639d258c8bce4f2cf0f8b5597'
MOMENTUM_PRODUCER = '999d0308c267a1bd55343e173099deea819e791d'
ENERGY_LIMIT_J = 1e-8
MASS_LIMIT_KG = 1e-15
NAMES = {'stored_mass', 'stored_energy', 'T_I', 'p_I', 'p_A', 'rho_I', 'u_I', 'u_port',
         'volume', 'level', 'fluid_internal_energy', 'environment_pv_energy', 'gravitational_energy',
         'auxiliary_energy', 'auxiliary_capacity', 'mdot_A', 'Phi_A', 'Q_H'}
MOMENTUM_NAMES = {'rho_port', 'T_port', 'T_node', 'dynamic_pressure'}


def dynamic_pressure(mdot, rho_port, area):
    mdot, rho_port = np.asarray(mdot, dtype=float), np.asarray(rho_port, dtype=float)
    if (mdot.shape != rho_port.shape or mdot.ndim != 1 or not np.isfinite([mdot, rho_port]).all()
            or np.any(rho_port <= 0) or not np.isfinite(area) or area <= 0):
        raise ValueError('Invalid momentum boundary inputs')
    return np.where(mdot < 0, mdot**2/(2*rho_port*area**2), 0.)


def momentum_boundary(table, get, reconstructed, area):
    pressure = get('p_A', 'Pa')
    rho = table['rho'](np.column_stack((get('T_port', 'K'), pressure)))
    pdyn = dynamic_pressure(get('mdot_A', 'kg/s'), rho, area)
    errors = dict(port_density_kg_m3=float(abs(rho-get('rho_port', 'kg/m^3')).max()),
                  dynamic_pressure_Pa=float(abs(pdyn-get('dynamic_pressure', 'Pa')).max()),
                  momentum_balance_Pa=float(abs(pressure+pdyn-reconstructed['port_pressure']).max()))
    passed = errors['port_density_kg_m3'] <= 1e-7 and max(errors[k] for k in errors if k.endswith('_Pa')) <= 1e-6
    reconstructed['port_pressure'] -= pdyn
    reconstructed['u_port'] = table['u'](np.column_stack((get('T_I', 'K'), reconstructed['port_pressure'])))
    return dict(momentum_boundary_pass=passed, errors=errors,
                dynamic_pressure_range_Pa=[float(pdyn.min()), float(pdyn.max())],
                port_vs_internal_density_max_difference_kg_m3=float(abs(rho-get('rho_I', 'kg/m^3')).max()),
                native_tank_energy_equivalence=False)


def inventory(table, temp, mass, pressure, area, gravity, reference_temp, auxiliary_depth):
    temp, mass = np.asarray(temp, dtype=float), np.asarray(mass, dtype=float)
    if (temp.shape != mass.shape or temp.ndim != 1 or not np.isfinite([temp, mass]).all() or
            not np.isfinite([pressure, area, gravity, reference_temp, auxiliary_depth]).all() or
            area <= 0 or gravity < 0 or auxiliary_depth < 0 or np.any(mass <= 0)):
        raise ValueError('Invalid physical buffer inventory')
    coords = np.column_stack((temp, np.full_like(temp, pressure)))
    rho, u = table['rho'](coords), table['u'](coords)
    if np.any(rho <= 0):
        raise ValueError('Nonpositive fluid density')
    reference = [[reference_temp, pressure]]
    capacity = area*auxiliary_depth*float(table['rho'](reference)[0])*float(table['cp'](reference)[0])
    volume = mass/rho; height = volume/area; port_pressure = pressure+rho*gravity*height
    parts = dict(fluid_internal_energy=mass*u, environment_pv_energy=pressure*volume,
                 gravitational_energy=mass*gravity*height/2, auxiliary_energy=capacity*(temp-reference_temp))
    return dict(parts=parts, total=sum(parts.values()), rho=rho, u=u, volume=volume, level=height,
                port_pressure=port_pressure, capacity=capacity,
                u_port=table['u'](np.column_stack((temp, port_pressure))))


def read_traces(path, momentum=False):
    with h5py.File(path) as f:
        meta = json.loads(text_field(f['record_json'])); rows = {}
        for ref in f['traces'][:].flat:
            r = f[ref]; name = text_field(r['name']); time = r['time_s'][:].reshape(-1)
            validate_grid(time, 0, .1, .001)
            if name in rows or r['values'].shape != (1, 101) or not np.isfinite(r['values'][:]).all():
                raise ValueError('Invalid candidate native traces')
            rows[name] = dict(unit=text_field(r['unit']), values=r['values'][:].reshape(-1))
    if set(rows) != (NAMES | MOMENTUM_NAMES if momentum else NAMES):
        raise ValueError('Incomplete candidate variables')
    return meta, time, rows


def audit(repo, momentum=False):
    root = repo/'outputs_storage_audit'/('conservative_buffer_momentum_trial_20260909' if momentum else 'conservative_buffer_trial_20260909')
    producer = MOMENTUM_PRODUCER if momentum else PRODUCER
    execution_path = root/'buffer_trial_execution.json'; execution = read(execution_path)
    if (not execution['collection_pass'] or execution['execution_commit'] != producer or len(execution['cases']) != 16 or
            any(execution[k] for k in ('checkpoint_loaded', 'checkpoint_saved', 'mainline_model_modified', 'production_recovery_allowed'))):
        raise ValueError('Wrong isolated buffer scope')
    if momentum and (not execution['momentum_trial'] or execution['package'] != 'ecc_buffer_momentum'):
        raise ValueError('Wrong momentum candidate identity')
    native = repo/'outputs_storage_audit'/EXPERIMENT/'native'
    configuration = native/'configuration.mat'; metadata_path = native/'inventory_metadata.json'
    if sha256(configuration) != execution['configuration_sha256']:
        raise ValueError('Changed configuration')
    with h5py.File(configuration) as f:
        canonical = Path(text_field(f['options/model_path']))
    if sha256(canonical) != execution['canonical_model_sha256']:
        raise ValueError('Canonical model changed')
    tables = {b['block_path']: energy_tables(b['parameters']) for b in read(metadata_path)['settings_tables']}
    files = [execution_path, root/'matlab_diary.log', configuration, metadata_path, canonical]
    names = ['ColdFluidBuffer', 'HotFluidBuffer', 'SHEXFluidBuffer', 'SMAHotFluidBuffer']
    flow = .1 if momentum else .001
    modes = {'heating': (10, 0), 'cooling': (-10, 0), 'inflow': (0, flow), 'outflow': (0, -flow)}
    results = []; initial_comparisons = []; seen = set()
    for c in execution['cases']:
        key = c['source_tank'], c['mode']
        if (key in seen or key[0] not in names or key[1] not in modes or c['fixed_step_s'] != .001 or c['stop_s'] != .1 or
                c['initial_source_time_s'] != 0 or c['area_m2'] != .001 or c['gravity_m_s2'] != 9.81 or
                c['p_environment_Pa'] != 1e6 or c['auxiliary_depth_m'] != .001 or c['port_area_m2'] != (.01 if momentum else .0001) or
                (c['heat_into_buffer_W'], c['mass_into_buffer_kg_s']) != modes[key[1]]):
            raise ValueError('Unexpected trial matrix')
        seen.add(key); path = root/c['file']; files.append(path)
        if sha256(path) != c['sha256']:
            raise ValueError('Candidate trace hash changed')
        meta, time, rows = read_traces(path, momentum)
        if meta != {k: v for k, v in c.items() if k not in ('file', 'sha256')}:
            raise ValueError('Raw case identity mismatch')
        initial = Path(c['initial_source_file'])
        if sha256(initial) != c['initial_source_sha256']:
            raise ValueError('Initial source changed')
        files.append(initial)
        with h5py.File(initial) as f:
            initial_rows = {text_field(f[r]['name']): f[r] for r in f['traces'][:].flat}
            for name, unit, declared in [('mass', 'kg', c['initial_mass_kg']), ('T_I', 'K', c['initial_temperature_K'])]:
                r = initial_rows[name]
                if r['time_s'][0, 0] != 0:
                    raise ValueError('Nonzero-time source is not a cold target')
                value = float(convert(r['values'][0, 0], text_field(r['unit']), unit))
                if not compare_initial(declared, value)['within_strict_comparison']:
                    raise ValueError('Declared initial target changed')
        def get(name, unit):
            row = rows[name]
            if row['unit'] == unit:
                return row['values']
            if unit == 'J/K' and row['unit'] == 'kJ/K':
                return row['values']*1000
            return convert(row['values'], row['unit'], unit)
        mass, temp = get('stored_mass', 'kg'), get('T_I', 'K')
        actual_energy = get('stored_energy', 'J'); table = tables[c['source_settings']]
        reconstructed = inventory(table, temp, mass, c['p_environment_Pa'], c['area_m2'], c['gravity_m_s2'],
                                  c['initial_temperature_K'], c['auxiliary_depth_m'])
        momentum_result = momentum_boundary(table, get, reconstructed, c['port_area_m2']) if momentum else None
        aliases = {k: float(abs(v-get(k, 'J')).max()) for k, v in reconstructed['parts'].items()}
        aliases['stored_energy'] = float(abs(reconstructed['total']-actual_energy).max())
        extra_checks = dict(volume=float(abs(reconstructed['volume']-get('volume', 'm^3')).max()),
            level=float(abs(reconstructed['level']-get('level', 'm')).max()),
            rho=float(abs(reconstructed['rho']-get('rho_I', 'kg/m^3')).max()),
            u=float(abs(reconstructed['u']-get('u_I', 'J/kg')).max()),
            u_port=float(abs(reconstructed['u_port']-get('u_port', 'J/kg')).max()),
            pressure=float(abs(reconstructed['port_pressure']-get('p_A', 'Pa')).max()),
            capacity=float(abs(reconstructed['capacity']-get('auxiliary_capacity', 'J/K')).max()))
        limits = dict(volume=1e-12, level=1e-10, rho=1e-7, u=1e-6, u_port=1e-6, pressure=1e-6, capacity=1e-8)
        alias_pass = max(aliases.values()) <= ENERGY_LIMIT_J and all(extra_checks[k] <= limits[k] for k in limits)
        mdot, phi, q = get('mdot_A', 'kg/s'), get('Phi_A', 'W'), get('Q_H', 'W')
        if np.any(get('p_I', 'Pa') != c['p_environment_Pa']) or abs(q-c['heat_into_buffer_W']).max() > 1e-10 or abs(mdot-c['mass_into_buffer_kg_s']).max() > 1e-12:
            raise ValueError('Boundary pressure, mass flow or heat contract failed')
        local = ledger(time, mass, reconstructed['total'], mdot, phi+q)
        if c['mode'] in ('heating', 'cooling') and (np.any(mdot != 0) or np.any(phi != 0)):
            raise ValueError('Closed heat trial has fluid exchange')
        expected_init = [('mass', mass[0], c['initial_mass_kg']), ('energy', actual_energy[0], c['initial_energy_J']),
                         ('temperature', temp[0], c['initial_temperature_K'])]
        initial_checks = [dict(source_tank=c['source_tank'], mode=c['mode'], coordinate=k, **compare_initial(a, b))
                          for k, a, b in expected_init]
        initial_comparisons.extend(initial_checks)
        initial_pass = all(r['within_strict_comparison'] for r in initial_checks)
        row = dict(source_tank=c['source_tank'], mode=c['mode'], independent_ledger=local,
            actual_initial_coordinates_pass=initial_pass, inventory_alias_pass=alias_pass, energy_alias_errors_J=aliases,
            auxiliary_alias_errors=extra_checks, mass_change_kg=float(mass[-1]-mass[0]),
            temperature_change_K=float(temp[-1]-temp[0]), temperature_start_K=float(temp[0]),
            energy_parts_change_J={k: float(v[-1]-v[0]) for k, v in reconstructed['parts'].items()},
            heat_input_J=float(np.sum(q[1:]*np.diff(time))), fluid_port_input_J=float(np.sum(phi[1:]*np.diff(time))),
            auxiliary_capacity_J_K=reconstructed['capacity'],
            candidate_component_pass=initial_pass and alias_pass and local['mass_closure_pass'] and local['energy_closure_pass'])
        if momentum:
            row['momentum'] = momentum_result
            row['candidate_component_pass'] &= momentum_result['momentum_boundary_pass']
            lo, hi = momentum_result['dynamic_pressure_range_Pa']
            if c['mode'] == 'outflow' and lo <= .01:
                raise ValueError('Finite outflow must measurably exercise the momentum term')
            if c['mode'] != 'outflow' and (lo != 0 or hi != 0):
                raise ValueError('Unexpected inflow or closed-case pressure loss')
        if c['mode'] in ('heating', 'cooling'):
            def total_at(t):
                return inventory(table, np.array([t]), np.array([mass[0]]), c['p_environment_Pa'], c['area_m2'],
                    c['gravity_m_s2'], c['initial_temperature_K'], c['auxiliary_depth_m'])['total'][0]
            reference = brentq(lambda t: total_at(t)-reconstructed['total'][0]-row['heat_input_J'], temp[0]-1, temp[0]+1,
                               xtol=1e-12, rtol=1e-14)
            row['closed_heat_endpoint_temperature_error_K'] = float(temp[-1]-reference)
            row['closed_heat_independent_reference_pass'] = bool(abs(temp[-1]-reference) <= 1e-7)
            row['candidate_component_pass'] &= row['closed_heat_independent_reference_pass']
        results.append(row)
    if seen != {(n, m) for n in names for m in modes}:
        raise ValueError('Incomplete heating/cooling/inflow/outflow matrix')
    contract_path = repo/'verification/c200_mainline_freeze_contract.json'; contract = read(contract_path); files.append(contract_path)
    for key in ('result', 'checkpoint'):
        path = repo/contract[key+'_relative_path']; files.append(path)
        if sha256(path) != contract[key+'_sha256']:
            raise ValueError('C200 authority changed')
    package = 'ecc_buffer_momentum' if momentum else 'ecc_buffer'
    source_folder = 'simscape_buffer_momentum' if momentum else 'simscape_buffer'
    component = repo/'verification'/source_folder/('+'+package)/'conservative_buffer.ssc'; files.append(component)
    built = root/'component_build'/('+'+package)/'conservative_buffer.ssc'; files.append(built)
    if sha256(component) != sha256(built):
        raise ValueError('Executed component differs from candidate source')
    if momentum and sha256(component) != execution['component_sha256']:
        raise ValueError('Executed component hash differs from recorded source')
    result = dict(schema='heatdrive_ecc_conservative_buffer_audit_v1', execution_commit=producer,
        momentum_boundary_trial=momentum,
        evidence_computation_pass=True, isolated_component_conservation_pass=all(r['candidate_component_pass'] for r in results),
        cases=results, modes=dict(Counter(r['mode'] for r in results)),
        mass_limit_kg=MASS_LIMIT_KG, energy_limit_J=ENERGY_LIMIT_J,
        equivalent_to_native_tank=False, constant_reference_auxiliary_capacity=True,
        homogeneous_free_surface_density_approximation=True, experimental_validation_complete=False,
        mainline_model_modified=False, coupled_model_run=False, production_recovery_allowed=False,
        full_device_first_law_verified=False, table4_reproduction_claim=False,
        input_sha256={str(p.relative_to(repo)): sha256(p) for p in sorted(set(files), key=str)})
    return result, initial_comparisons


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-root', type=Path, required=True)
    parser.add_argument('--momentum', action='store_true')
    args = parser.parse_args()
    if args.output_root.exists():
        raise FileExistsError('Do not overwrite evidence')
    result, rows = audit(Path(__file__).resolve().parents[1], args.momentum)
    args.output_root.mkdir(parents=True)
    (args.output_root/'conservative_buffer_audit.json').write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    with (args.output_root/'initial_coordinates.csv').open('w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)
    print(json.dumps(dict(isolated_component_conservation_pass=result['isolated_component_conservation_pass'],
        cases=len(result['cases']), maximum_mass_residual_kg=max(r['independent_ledger']['mass_max_abs_residual_kg'] for r in result['cases']),
        maximum_energy_residual_J=max(r['independent_ledger']['energy_max_abs_residual_J'] for r in result['cases']),
        failed=[(r['source_tank'], r['mode']) for r in result['cases'] if not r['candidate_component_pass']],
        production_recovery_allowed=False, output=str(args.output_root)), indent=2))
    raise SystemExit(0 if result['isolated_component_conservation_pass'] else 1)
