"""Test the extra tank thermal volume with independent trials and retained C181.

The 1 mm hypothesis was fixed in the MATLAB trial before simulation. No fitted
coefficient is substituted into a ledger. Historical v1 ledgers remain unchanged.
"""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_NativeResidualLocalization import component_terms
from Audit_HeatDriveECC_NativeWindowLedger import NativeWindowLedger, validate_grid
from Audit_HeatDriveECC_NativeWindowPackets import load_packet
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field


DEAD_HEIGHT_M = .001
TRIAL_COMMIT = '322a6b7affa7bee46c91d046f2bf5b1ebefcca0a'


def extra_thermal_accumulation(time, temperature, density, cp, area):
    arrays = [np.asarray(v, dtype=float) for v in (time, temperature, density, cp)]
    t, temp, rho, heat_capacity = arrays
    if (t.ndim != 1 or t.size < 2 or any(v.shape != t.shape for v in arrays)
            or not np.isfinite(arrays).all() or np.any(np.diff(t) <= 0)
            or np.any(temp <= 0) or np.any(rho <= 0) or np.any(heat_capacity <= 0)
            or not np.isfinite(area) or area <= 0):
        raise ValueError("Invalid extra-volume accumulation inputs")
    coefficient = rho * heat_capacity * area * DEAD_HEIGHT_M
    return coefficient[1:] * np.diff(temp), .5 * (coefficient[:-1] + coefficient[1:]) * np.diff(temp)


def hydrostatic_transport(time, mass_flow, level, gravity, inlet_height):
    t, mdot, y = (np.asarray(v, dtype=float) for v in (time, mass_flow, level))
    if (t.ndim != 1 or t.size < 2 or mdot.shape != t.shape or y.shape != t.shape
            or not np.isfinite([t, mdot, y]).all() or not np.isfinite([gravity, inlet_height]).all()
            or np.any(np.diff(t) <= 0) or gravity < 0 or inlet_height < 0 or np.any(y < inlet_height)):
        raise ValueError('Require a finite, submerged, single tank inlet')
    # Positive incoming fluid must rise from the port to the free-surface
    # pressure reference. Keep this term separate from the measured port Phi.
    power = -mdot * gravity * (y - inlet_height)
    return power[1:] * np.diff(t), .5 * (power[:-1] + power[1:]) * np.diff(t)


def analyze(block, table, area, gravity=9.81, inlet_height=0):
    if block['mask_type'] != 'Tank (TL)':
        raise ValueError('Extra tank volume does not apply to other components')
    time, terms, _ = component_terms(block, table)
    leaves = {v['name']: v for v in block['leaf_variables']}

    def series(name, unit):
        v = leaves[name]
        return convert(v['values'], v['unit'], unit)

    temp, pressure = series('T_I', 'K'), series('p_I', 'Pa')
    rho = series('rho_I', 'kg/m^3')
    cp = table['cp'](np.column_stack((temp, pressure)))
    be, tr = extra_thermal_accumulation(time, temp, rho, cp, area)
    corrected = terms['BE_energy_residual_J'] - be
    volume = series('volume', 'm^3')
    if set(n for n in leaves if n.startswith('mdot_')) != {'mdot_A'}:
        raise ValueError('This diagnostic supports the actual single-inlet tanks only')
    hydro_be, hydro_tr = hydrostatic_transport(time, series('mdot_A', 'kg/s'), volume / area, gravity, inlet_height)
    final = corrected + hydro_be
    mass = series('mass', 'kg')
    # A roundoff allowance for subtracting absolute temperatures, not a
    # physical closure gate or a tolerance fitted to measured residuals.
    roundoff_limit = 16 * np.finfo(float).eps * max(abs(temp)) * max((mass + rho * area * DEAD_HEIGHT_M) * cp)
    return dict(block_path=block['block_path'], area_m2=area, hypothesized_dead_volume_m3=area * DEAD_HEIGHT_M,
                sample_count=len(time), start_s=float(time[0]), stop_s=float(time[-1]),
                original_BE_energy_residual_J=float(terms['BE_energy_residual_J'].sum()),
                extra_BE_accumulation_J=float(be.sum()), corrected_BE_energy_residual_J=float(corrected.sum()),
                corrected_BE_absolute_residual_sum_J=float(abs(corrected).sum()),
                corrected_BE_max_interval_residual_J=float(abs(corrected).max()),
                floating_point_interval_allowance_J=float(roundoff_limit),
                all_intervals_within_roundoff_allowance=bool(np.all(abs(corrected) <= roundoff_limit)),
                hydrostatic_internal_transport_BE_J=float(hydro_be.sum()),
                extra_volume_and_head_BE_residual_J=float(final.sum()),
                extra_volume_and_head_BE_absolute_residual_sum_J=float(abs(final).sum()),
                extra_volume_and_head_BE_max_interval_residual_J=float(abs(final).max()),
                extra_volume_and_head_BE_roundoff_match=bool(np.all(abs(final) <= roundoff_limit)),
                original_trapezoid_energy_residual_J=float(terms['energy_residual_J'].sum()),
                extra_trapezoid_accumulation_J=float(tr.sum()),
                corrected_trapezoid_energy_residual_J=float((terms['energy_residual_J'] - tr).sum()),
                extra_volume_and_head_trapezoid_residual_J=float((terms['energy_residual_J'] - tr + hydro_tr).sum()),
                mass_endpoint_change_kg=float(mass[-1] - mass[0]),
                BE_mass_residual_kg=float(terms['BE_mass_residual_kg'].sum()),
                temperature_change_K=float(temp[-1] - temp[0]),
                heat_port_mean_W=float(np.mean(series('Q_H', 'W'))))


def read_trial(path, template):
    with h5py.File(path, 'r') as f:
        meta = json.loads(text_field(f['record_json']))
        leaves = []
        for ref in f['traces'][:].flat:
            row = f[ref]
            leaves.append(dict(name=text_field(row['name']), unit=text_field(row['unit']),
                               values=row['values'][:].reshape(-1), time_s=row['time_s'][:].reshape(-1)))
    if len({v['name'] for v in leaves}) != len(leaves):
        raise ValueError('Duplicate trial leaf')
    for leaf in leaves:
        validate_grid(leaf['time_s'], 0, .1, .001)
    return dict(template, leaf_variables=leaves), meta


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite tank evidence')
    root = args.repo / 'outputs_storage_audit'
    experiment = root / 'tank_energy_basis_20260907/isolated_trial'
    inputs = dict(topology=root / 'tl_domain_energy_tables_20260906/tl_domain_metadata.json',
                  probe=root / 'native_inventory_port_comparison_20260906/native_inventory_probe.json',
                  metadata=root / 'native_inventory_model_metadata_20260906/storage_model_metadata.json',
                  geometry=root / 'tank_energy_basis_20260907/geometry_v2/tank_geometry.json',
                  trial=experiment / 'isolated_tank_result.json')
    cycle = args.repo / 'outputs/qian_native_inventory_pilot_from_c180_20260906/cycle_181'
    inputs.update(packet=cycle / 'native_window.mat', physical=cycle / 'segment_physical.mat',
                  ledger=cycle / 'native_ledger.json', mechanism=cycle / 'cycle_audit.json')
    data = {n: json.loads(p.read_text(encoding='utf-8-sig')) for n, p in inputs.items() if n not in ('packet', 'physical')}
    hashes = {n: sha256(p) for n, p in inputs.items()}
    old = data['ledger']
    if (hashes['packet'] != old['packet_sha256'] or not old['ledger_computation_pass']
            or old['production_recovery_allowed'] or not data['mechanism']['mechanism_pass']
            or not data['mechanism']['strict_restore_pass']
            or any(hashes[n] != old['input_sha256'][n] for n in ('topology', 'probe', 'metadata'))):
        raise ValueError('Frozen C181 identity or scope changed')
    trial = data['trial']
    if (not trial['collection_pass'] or len(trial['cases']) != 6 or trial['production_checkpoint_loaded']
            or trial['output_operating_point_saved'] or trial['production_recovery_allowed']
            or trial['execution_commit'] != TRIAL_COMMIT):
        raise ValueError('Unexpected independent experiment provenance')
    if (Path(trial['source_options_path']).resolve() != inputs['physical'].resolve()
            or Path(data['geometry']['physical_path']).resolve() != inputs['physical'].resolve()):
        raise ValueError('Geometry or trial options came from a different result')
    with h5py.File(inputs['physical'], 'r') as physical:
        solver = physical['options/simscape']
        if (not bool(solver['local_solver_enabled'][0, 0])
                or text_field(solver['local_solver_choice']) != 'NE_BACKWARD_EULER_ADVANCER'
                or float(solver['local_solver_sample_time_s'][0, 0]) != .001):
            raise ValueError('C181 did not use the recorded local BE discretization')
    ledger = NativeWindowLedger(*(data[n] for n in ('topology', 'probe', 'metadata')))
    header, streams = load_packet(inputs['packet'])
    if any(header[k] != v for k, v in ledger.source.items()) or set(streams['native']) != ledger.keys:
        raise ValueError('Native source or inventory differs')
    geometry = {r['block_path']: r for r in data['geometry']['tanks']}
    if len(geometry) != 4 or data['geometry']['checkpoint_loaded'] or data['geometry']['simulation_run']:
        raise ValueError('Invalid geometry evidence')
    cases = []
    for i in range(1, 7):
        meta = trial['cases'][i - 1]
        path = 'heatdrive_ecc_coupled_se21/' + meta['source_tank']
        block, saved_meta = read_trial(experiment / f'case_{i}.mat', ledger.templates[path])
        if (meta != saved_meta or meta['hypothesized_dead_height_m'] != DEAD_HEIGHT_M or meta['hypothesis_fitted_from_trial']
                or meta['fixed_step_s'] != .001 or meta['stop_s'] != .1
                or meta['local_solver'] != 'NE_BACKWARD_EULER_ADVANCER'):
            raise ValueError('Trial metadata or fixed hypothesis changed')
        table = ledger.tables[ledger.basis[path]['settings_path']]
        row = analyze(block, table, meta['area_m2'])
        row.update(case_index=i, trial_sha256=sha256(experiment / f'case_{i}.mat'), fluid_index=meta['fluid_index'])
        if (abs(row['mass_endpoint_change_kg']) > 1e-12 or abs(row['heat_port_mean_W']) != 10
                or abs(row['temperature_change_K']) < .001):
            raise ValueError('Trial lacks a closed, thermally excited tank')
        cases.append(row)
    if sorted((r['fluid_index'], r['area_m2']) for r in cases) != [(f, a) for f in (1, 2) for a in (.0005, .001, .002)]:
        raise ValueError('Trial geometry interventions incomplete')
    coupled = []
    for path, geometry_row in geometry.items():
        template = ledger.templates[path]
        if not geometry_row['parameters']['volume_spec'].endswith('.Constant') or geometry_row['parameters']['tank_area_unit'] != 'm^2':
            raise ValueError('Unsupported source geometry')
        leaves = []
        for leaf in template['leaf_variables']:
            v = streams['native'][path + '::' + leaf['name']]
            validate_grid(v['time'], 1800, 1810, .001)
            if v['unit'] != leaf['unit']:
                raise ValueError('Native unit changed')
            leaves.append(dict(name=leaf['name'], unit=v['unit'], time_s=v['time'], values=v['values'][:, 0]))
        parameters = geometry_row['parameters']
        if (parameters['g_unit'] != 'm/s^2' or parameters['inlet_height_A_unit'] != 'm'
                or not parameters['num_inlet'].endswith('.One')):
            raise ValueError('Unexpected gravity or inlet contract')
        row = analyze(dict(template, leaf_variables=leaves), ledger.tables[ledger.basis[path]['settings_path']],
                      geometry_row['resolved']['tank_area'], float(parameters['g']), float(parameters['inlet_height_A']))
        coupled.append(row)
    result = dict(schema='heatdrive_ecc_tank_energy_basis_v2', input_sha256=hashes,
                  trial_execution_commit=trial['execution_commit'], independent_cases=cases, coupled_C181_tanks=coupled,
                  independent_dead_volume_hypothesis_pass=all(c['all_intervals_within_roundoff_allowance'] for c in cases),
                  geometry_intervention_complete=True, dead_height_m=DEAD_HEIGHT_M, fitted_correction_used=False,
                  protected_source_decoded=False, historical_ledger_overwritten=False,
                  coupled_tank_discrete_equations_match=all(r['extra_volume_and_head_BE_roundoff_match'] for r in coupled),
                  independent_hydrostatic_intervention_run=False,
                  hydrostatic_scope='Actual one-inlet head transport at native samples; related public source and C181 residual comparison',
                  scope='Extra thermal coefficient identified independently; not an additional transported liquid mass',
                  equation_matched_cycle_closure_verified=False, full_internal_periodicity_verified=False,
                  production_recovery_allowed=False, table4_reproduction_claim=False)
    source = Path('C:/Program Files/MATLAB/R2025b/toolbox/physmod/fluids/library/m/+fluids/+thermal_liquid/+tanks_accumulators/tank_G_TL.ssc')
    result['related_public_source'] = dict(path=str(source), sha256=sha256(source),
        scope='Adjacent G-TL implementation analogy, not a decoding of the protected Tank (TL) implementation')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
    if not result['independent_dead_volume_hypothesis_pass']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
