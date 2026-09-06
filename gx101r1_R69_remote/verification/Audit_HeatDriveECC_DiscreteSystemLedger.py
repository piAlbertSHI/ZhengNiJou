"""All 119 native components: BE equations and endpoint inventories in parallel.

This version incorporates the independently identified tank thermal volume and
head transport, without overwriting the historical trapezoid ledger. A discrete
equation match does not prove physical inventory conservation or periodicity.
"""
import argparse
import json
from collections import Counter
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_NativeResidualLocalization import component_terms
from Audit_HeatDriveECC_NativeSystemLedger import align_steps, assemble, stage_endpoints
from Audit_HeatDriveECC_NativeWindowLedger import NativeWindowLedger, evaluate_component, validate_grid, EXPECTED_COUNTS
from Audit_HeatDriveECC_NativeWindowPackets import load_packet
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field
from Audit_HeatDriveECC_TankEnergyBasis import extra_thermal_accumulation, hydrostatic_transport


def be_flow(flow, time):
    flow, time = np.asarray(flow), np.asarray(time)
    if (flow.ndim != 1 or flow.shape != time.shape or len(time) < 2
            or not np.isfinite([flow, time]).all() or np.any(np.diff(time) <= 0)):
        raise ValueError('Require finite matching native samples')
    return flow[1:] * np.diff(time)


def component_balance(block, table=None, nominal_mass=None, geometry=None):
    reference = evaluate_component(block, table, nominal_mass)
    leaves = {r['name']: r for r in block['leaf_variables']}
    time = np.asarray(next(iter(leaves.values()))['time_s'])
    kind = block['mask_type']

    def v(name, unit):
        r = leaves[name]
        return convert(r['values'], r['unit'], unit)

    zero = np.zeros(len(time) - 1)
    mass_flow = np.zeros_like(time)
    head, extra, pdV = zero.copy(), zero.copy(), zero.copy()
    if kind == 'Thermal Mass':
        parameters = block['mask_parameters']
        mass = float(convert(parameters['mass']['value'], parameters['mass']['unit'], 'kg'))
        cp = float(convert(parameters['sp_heat']['value'], parameters['sp_heat']['unit'], 'J/(K*kg)'))
        temp = v('T', 'K')
        flow = v('Q', 'W')
        accumulation = mass * cp * np.diff(temp)
        mass_accumulation = zero.copy()
        coordinate_scale = float(max(abs(mass * cp * temp)))
    else:
        ports = sorted(n[5:] for n in leaves if n.startswith('mdot_'))
        mass_flow = sum((v('mdot_' + port, 'kg/s') for port in ports), np.zeros_like(time))
        flow = sum((v('Phi_' + port, 'W') for port in ports), np.zeros_like(time)) + v('Q_H', 'W')
        temp, p, rho, h = v('T_I', 'K'), v('p_I', 'Pa'), v('rho_I', 'kg/m^3'), v('h_I', 'J/kg')
        if kind == 'Pipe (TL)':
            mass = np.full_like(time, nominal_mass)
            accumulation = nominal_mass * np.diff(v('u_I', 'J/kg'))
            mass_accumulation = zero.copy()
        else:
            _, terms, _ = component_terms(block, table)
            accumulation, mass_accumulation = terms['BE_energy_accumulation_J'], terms['BE_mass_accumulation_kg']
            if kind == 'Tank (TL)':
                if geometry is None or ports != ['A']:
                    raise ValueError('Require actual constant-area single-inlet tank geometry')
                pars = geometry['parameters']
                if (not pars['volume_spec'].endswith('.Constant') or not pars['num_inlet'].endswith('.One')
                        or pars['tank_area_unit'] != 'm^2' or pars['inlet_height_A_unit'] != 'm' or pars['g_unit'] != 'm/s^2'):
                    raise ValueError('Unsupported tank geometry')
                area = geometry['resolved']['tank_area']
                mass, volume = v('mass', 'kg'), v('volume', 'm^3')
                cp = table['cp'](np.column_stack((temp, p)))
                extra, _ = extra_thermal_accumulation(time, temp, rho, cp, area)
                head, _ = hydrostatic_transport(time, mass_flow, volume / area, float(pars['g']), float(pars['inlet_height_A']))
                pdV = p[1:] * np.diff(volume)
                accumulation = accumulation + extra
            else:
                parameter = block['mask_parameters']['volume']
                volume = float(convert(parameter['value'], parameter['unit'], 'm^3'))
                mass = rho * volume
        coordinate_scale = float(max(np.max(abs(mass * h)),
            np.max(abs(mass * table['cp'](np.column_stack((temp, p))) * temp))))
    intervals = dict(port_energy_J=be_flow(flow, time), head_transport_J=head,
                     discrete_accumulation_J=accumulation, extra_tank_thermal_accumulation_J=extra,
                     tank_pressure_volume_work_J=pdV, port_mass_kg=be_flow(mass_flow, time),
                     discrete_mass_accumulation_kg=mass_accumulation)
    intervals['energy_residual_J'] = intervals['port_energy_J'] + head - accumulation
    intervals['mass_residual_kg'] = intervals['port_mass_kg'] - mass_accumulation
    # Separate absolute-coordinate subtraction and large-absolute-clock errors.
    numerical_limit = (64 * np.finfo(float).eps * max(1, coordinate_scale)
                       + 8 * np.spacing(max(1, max(abs(time)))) * max(abs(flow)))
    row = dict(block_path=block['block_path'], mask_type=kind, sample_count=len(time),
               **{n: float(x.sum()) for n, x in intervals.items()},
               energy_residual_absolute_sum_J=float(abs(intervals['energy_residual_J']).sum()),
               max_interval_energy_residual_J=float(abs(intervals['energy_residual_J']).max()),
               numerical_interval_energy_limit_J=float(numerical_limit),
               discrete_energy_equation_match=bool(np.all(abs(intervals['energy_residual_J']) <= numerical_limit)),
               max_interval_mass_residual_kg=float(abs(intervals['mass_residual_kg']).max()),
               endpoint_internal_energy_change_J=reference['energy_endpoint_change_J'],
               endpoint_fluid_mass_change_kg=reference.get('mass_endpoint_change_kg', 0),
               initial_fluid_mass_kg=reference.get('mass_start_kg', 0),
               physical_energy_closure_verified=False, physical_mass_closure_verified=False)
    row['coefficient_vs_endpoint_plus_pV_J'] = (row['discrete_accumulation_J'] - row['endpoint_internal_energy_change_J']
                                              - row['tank_pressure_volume_work_J'])
    row['coefficient_vs_endpoint_mass_kg'] = row['discrete_mass_accumulation_kg'] - row['endpoint_fluid_mass_change_kg']
    return row, intervals, flow, mass_flow


def mass_table_bridge(block, table):
    """Exact axis-ordered density differences versus native coefficient steps."""
    leaves = {r['name']: r for r in block['leaf_variables']}
    def v(name, unit):
        r = leaves[name]
        return convert(r['values'], r['unit'], unit)
    temp, p, rho = v('T_I', 'K'), v('p_I', 'Pa'), v('rho_I', 'kg/m^3')
    parameter = block['mask_parameters']['volume']
    volume = float(convert(parameter['value'], parameter['unit'], 'm^3'))
    coords = np.column_stack((temp, p))
    corner = table['rho'](np.column_stack((temp[:-1], p[1:])))
    exact_T = volume * (rho[1:] - corner)
    exact_p = volume * (corner - rho[:-1])
    be_T = -volume * rho[1:] * table['alpha'](coords)[1:] * np.diff(temp)
    be_p = volume * rho[1:] / table['beta'](coords)[1:] * np.diff(p)
    path_T, path_p = mass_path_integrals(temp, p, volume, table, 3)
    check_T, check_p = mass_path_integrals(temp, p, volume, table, 5)
    quadrature_difference = float(max(np.max(abs(path_T - check_T)), np.max(abs(path_p - check_p))))
    if quadrature_difference > 1e-15:
        raise ValueError('Split-cell mass coefficient quadratures disagree')
    return dict(temperature_coefficient_minus_table_mass_kg=float((be_T - exact_T).sum()),
                pressure_coefficient_minus_table_mass_kg=float((be_p - exact_p).sum()),
                exact_table_endpoint_mass_kg=float((exact_T + exact_p).sum()),
                BE_minus_path_integral_mass_kg=float((be_T + be_p - path_T - path_p).sum()),
                path_integral_minus_endpoint_mass_kg=float((path_T + path_p - exact_T - exact_p).sum()),
                path_integral_mass_kg=float((path_T + path_p).sum()),
                path_quadrature_3_vs_5_max_difference_kg=quadrature_difference,
                scope='Exact endpoint split uses p first then T; coefficient path is straight within each saved interval, split at every property-table knot. Offline quadrature only, not a new dynamic trajectory or solver-convergence study')


def mass_path_integrals(temp, pressure, volume, table, order, include_energy=False):
    temp, pressure = np.asarray(temp), np.asarray(pressure)
    if (temp.ndim != 1 or len(temp) < 2 or temp.shape != pressure.shape
            or not np.isfinite([temp, pressure]).all() or not np.isfinite(volume) or volume <= 0
            or order not in (3, 4, 5) or (include_energy and order < 4) or np.ptp(table['beta'].values) != 0):
        raise ValueError('Require finite path, positive volume and constant beta for exact cell quadrature')
    nodes, weights = np.polynomial.legendre.leggauss(order)
    owners, starts, stops = [], [], []
    for i, (dT, dp) in enumerate(zip(np.diff(temp), np.diff(pressure))):
        breaks = [0., 1.]
        for grid, start, delta in zip(table['rho'].grid, (temp[i], pressure[i]), (dT, dp)):
            if delta != 0:
                fractions = (grid - start) / delta
                breaks.extend(fractions[(fractions > 0) & (fractions < 1)].tolist())
        breaks = sorted(set(breaks))
        owners.extend([i] * (len(breaks) - 1))
        starts.extend(breaks[:-1])
        stops.extend(breaks[1:])
    owner = np.asarray(owners)
    a, b = np.asarray(starts), np.asarray(stops)
    fraction = .5 * (a[:, None] + b[:, None]) + .5 * (b - a)[:, None] * nodes
    dT, dp = np.diff(temp)[owner], np.diff(pressure)[owner]
    coords = np.column_stack(((temp[owner, None] + dT[:, None] * fraction).ravel(),
                              (pressure[owner, None] + dp[:, None] * fraction).ravel()))
    rho = table['rho'](coords).reshape(fraction.shape)
    alpha = table['alpha'](coords).reshape(fraction.shape)
    beta = table['beta'](coords).reshape(fraction.shape)
    integral_T = (-volume * rho * alpha) @ weights * .5 * (b - a) * dT
    integral_p = (volume * rho / beta) @ weights * .5 * (b - a) * dp
    result = [np.bincount(owner, weights=integral_T, minlength=len(temp)-1),
              np.bincount(owner, weights=integral_p, minlength=len(temp)-1)]
    if include_energy:
        # rho*h = rho*u+p removes the rational enthalpy expression. Within
        # a bilinear table cell the energy coefficient has degree at most six.
        cp = table['cp'](coords).reshape(fraction.shape)
        u = table['u'](coords).reshape(fraction.shape)
        sampled_T, sampled_p = coords[:, 0].reshape(fraction.shape), coords[:, 1].reshape(fraction.shape)
        rho_h = rho * u + sampled_p
        dUdT = volume * (rho * cp - rho_h * alpha)
        dUdp = volume * (rho_h / beta - sampled_T * alpha)
        for coefficient, delta in ((dUdT, dT), (dUdp, dp)):
            integral = coefficient @ weights * .5 * (b - a) * delta
            result.append(np.bincount(owner, weights=integral, minlength=len(temp)-1))
    return tuple(result)


def energy_table_bridge(block, table, row):
    leaves = {r['name']: r for r in block['leaf_variables']}
    def v(name, unit):
        r = leaves[name]
        return convert(r['values'], r['unit'], unit)
    parameter = block['mask_parameters']['volume']
    volume = float(convert(parameter['value'], parameter['unit'], 'm^3'))
    x = mass_path_integrals(v('T_I', 'K'), v('p_I', 'Pa'), volume, table, 4, True)
    y = mass_path_integrals(v('T_I', 'K'), v('p_I', 'Pa'), volume, table, 5, True)
    difference = float(max(np.max(abs(x[2] - y[2])), np.max(abs(x[3] - y[3]))))
    if difference > 1e-9:
        raise ValueError('Split-cell energy coefficient quadratures disagree')
    path_energy = float((x[2] + x[3]).sum())
    return dict(path_integral_energy_J=path_energy,
                BE_minus_path_integral_energy_J=row['discrete_accumulation_J'] - path_energy,
                path_integral_minus_endpoint_U_J=path_energy - row['endpoint_internal_energy_change_J'],
                path_quadrature_4_vs_5_max_difference_J=difference,
                scope='Offline coefficient integration on the fixed native piecewise-linear p,T path, not physical time-step refinement')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite a ledger')
    audit = args.repo / 'outputs_storage_audit'
    cycle = args.repo / 'outputs/qian_native_inventory_pilot_from_c180_20260906/cycle_181'
    paths = dict(topology=audit / 'tl_domain_energy_tables_20260906/tl_domain_metadata.json',
                 probe=audit / 'native_inventory_port_comparison_20260906/native_inventory_probe.json',
                 metadata=audit / 'native_inventory_model_metadata_20260906/storage_model_metadata.json',
                 geometry=audit / 'tank_energy_basis_20260907/geometry_v2/tank_geometry.json',
                 trial=audit / 'tank_energy_basis_20260907/isolated_trial/isolated_tank_result.json',
                 tank_audit=audit / 'tank_energy_basis_20260907/tank_energy_basis_v3.json',
                 packet=cycle / 'native_window.mat', physical=cycle / 'segment_physical.mat',
                 ledger=cycle / 'native_ledger.json', mechanism=cycle / 'cycle_audit.json')
    data = {k: json.loads(p.read_text(encoding='utf-8-sig')) for k, p in paths.items() if k not in ('packet', 'physical')}
    hashes = {k: sha256(p) for k, p in paths.items()}
    tank_audit = data['tank_audit']
    if (not tank_audit['independent_dead_volume_hypothesis_pass'] or not tank_audit['coupled_tank_discrete_equations_match']
            or tank_audit['production_recovery_allowed'] or hashes['packet'] != data['ledger']['packet_sha256']
            or not data['mechanism']['strict_restore_pass'] or not data['mechanism']['mechanism_pass']
            or data['mechanism']['production_recovery_allowed']
            or any(hashes[k] != tank_audit['input_sha256'][k] for k in tank_audit['input_sha256'])):
        raise ValueError('Frozen diagnostic source or tank evidence changed')
    ledger = NativeWindowLedger(*(data[k] for k in ('topology', 'probe', 'metadata')))
    header, streams = load_packet(paths['packet'])
    native = streams['native']
    if set(native) != ledger.keys or any(header[k] != v for k, v in ledger.source.items()):
        raise ValueError('Incomplete or different native inventory')
    time = next(iter(native.values()))['time']
    geometry = {r['block_path']: r for r in data['geometry']['tanks']}
    rows, total = [], {}
    summed_energy, summed_mass = np.zeros_like(time), np.zeros_like(time)
    old_rows = {r['block_path']: r for r in data['ledger']['components']}
    for path, template in ledger.templates.items():
        leaves = []
        for leaf in template['leaf_variables']:
            trace = native[path + '::' + leaf['name']]
            validate_grid(trace['time'], 1800, 1810, .001)
            if (trace['unit'] != leaf['unit'] or trace['values'].shape != (len(time), 1)
                    or not np.array_equal(trace['time'], time)):
                raise ValueError('Native unit, shape or time mismatch')
            leaves.append(dict(name=leaf['name'], unit=trace['unit'], time_s=time, values=trace['values'][:, 0]))
        block = dict(template, leaf_variables=leaves)
        basis = ledger.basis.get(path, {})
        table = ledger.tables.get(basis.get('settings_path'))
        row, terms, energy, mass = component_balance(block, table, basis.get('equation_mass_kg'), geometry.get(path))
        if row['endpoint_internal_energy_change_J'] != old_rows[path]['energy_endpoint_change_J']:
            raise ValueError('Endpoint ledger changed during BE reconstruction')
        if row['mask_type'] == 'Constant Volume Chamber (TL)':
            row['mass_table_bridge'] = mass_table_bridge(block, table)
            row['energy_table_bridge'] = energy_table_bridge(block, table, row)
            mass_bridge, energy_bridge = row['mass_table_bridge'], row['energy_table_bridge']
            if (abs(mass_bridge['BE_minus_path_integral_mass_kg'] + mass_bridge['path_integral_minus_endpoint_mass_kg']
                    - row['coefficient_vs_endpoint_mass_kg']) > 1e-15
                    or abs(energy_bridge['BE_minus_path_integral_energy_J'] + energy_bridge['path_integral_minus_endpoint_U_J']
                           - row['coefficient_vs_endpoint_plus_pV_J']) > 1e-9):
                raise ValueError('Coefficient/path/endpoint bridge does not reconstruct original difference')
        rows.append(row)
        for k, values in terms.items():
            total[k] = total.get(k, np.zeros_like(values)) + values
        summed_energy += energy
        summed_mass += mass
    if dict(Counter(r['mask_type'] for r in rows)) != EXPECTED_COUNTS:
        raise ValueError('Storage class coverage differs')
    with h5py.File(paths['physical'], 'r') as file:
        solver = file['options/simscape']
        if (not bool(solver['local_solver_enabled'][0, 0])
                or text_field(solver['local_solver_choice']) != 'NE_BACKWARD_EULER_ADVANCER'
                or float(solver['local_solver_sample_time_s'][0, 0]) != .001):
            raise ValueError('Require actual local BE on the retained sample grid')
        group = file['physical']
        physical_time = group['time_s'][:].reshape(-1)
        alignment = align_steps(time, physical_time, 1800, 1810, .001)
        physical = {n: v[:].T if 'constitutive_21' in n else v[:].reshape(-1)
                    for n, v in group.items() if n.startswith(('Q_', 'pump_power_', 'P_pressure_'))}
        if text_field(file['options/system/cold_load_mode']) != 'no_load':
            raise ValueError('Only measured no-load boundary supported')
        load = float(file['options/system/cold_load_heat_W'][0, 0])
        stages = stage_endpoints(file['options/schedule/stage_durations_s'][:].reshape(-1), .001, len(time))
    # Reuse the measured boundary validity checks, without inheriting its v1 accumulation.
    previous = assemble(physical_time, physical, summed_energy, summed_mass, data['ledger'], load, time)
    q_latent = sum((physical[n].sum(axis=1) for n in ('Q_SMA_constitutive_21_W', 'Q_SE_constitutive_21_W')), np.zeros_like(time))
    external = physical['Q_SHEX_source_to_sink_W'] - physical['Q_HHEX_sink_to_ambient_W'] - physical['Q_CHEX_fixed_source_W']
    external_BE, constitutive_BE = be_flow(external, physical_time), be_flow(q_latent, physical_time)
    boundary_BE = external_BE + constitutive_BE
    system_residual = boundary_BE + total['head_transport_J'] - total['discrete_accumulation_J']
    endpoint_U = sum(r['endpoint_internal_energy_change_J'] for r in rows)
    endpoint_M = sum(r['endpoint_fluid_mass_change_kg'] for r in rows)
    summary = dict(component_count=len(rows), native_trace_count=len(native), sample_count=len(time),
                   scalar_energy_intervals=sum(r['sample_count'] - 1 for r in rows),
                   component_classes=dict(Counter(r['mask_type'] for r in rows)),
                   **{k: float(v.sum()) for k, v in total.items()},
                   external_thermal_BE_J=float(external_BE.sum()), constitutive_BE_J=float(constitutive_BE.sum()),
                   external_plus_constitutive_BE_J=float(boundary_BE.sum()),
                   external_BE_equation_residual_J=float(system_residual.sum()),
                   max_interval_external_BE_equation_residual_J=float(abs(system_residual).max()),
                   spatial_energy_identity_rms_W=previous['spatial_energy_boundary_identity_rms_W'],
                   spatial_mass_identity_max_kg_s=previous['spatial_mass_boundary_identity_max_kg_s'],
                   endpoint_internal_energy_change_J=endpoint_U, endpoint_fluid_mass_change_kg=endpoint_M,
                   initial_fluid_mass_kg=sum(r['initial_fluid_mass_kg'] for r in rows),
                   coefficient_minus_endpoint_mass_kg=float(total['discrete_mass_accumulation_kg'].sum()) - endpoint_M,
                   raw_boundary_minus_endpoint_U_J=float(boundary_BE.sum()) - endpoint_U,
                   coefficient_minus_endpoint_U_and_pV_J=float(total['discrete_accumulation_J'].sum()) - endpoint_U - float(total['tank_pressure_volume_work_J'].sum()),
                   raw_boundary_minus_endpoint_U_and_pV_J=float(boundary_BE.sum()) - endpoint_U - float(total['tank_pressure_volume_work_J'].sum()),
                   discrete_equation_matching_components=sum(r['discrete_energy_equation_match'] for r in rows))
    stage_rows = [dict(stage=i, start_s=float(time[a]), stop_s=float(time[b]),
                       **{k: float(v[a:b].sum()) for k, v in total.items()},
                       external_plus_constitutive_BE_J=float(boundary_BE[a:b].sum()),
                       external_BE_equation_residual_J=float(system_residual[a:b].sum()))
                  for i, (a, b) in enumerate(zip(stages[:-1], stages[1:]), 1)]
    result = dict(schema='heatdrive_ecc_discrete_system_ledger_v1', summary=summary, components=rows, stages=stage_rows,
                  input_sha256=hashes, time_alignment=alignment, source=ledger.source,
                  all_discrete_component_energy_equations_match=all(r['discrete_energy_equation_match'] for r in rows),
                  computation_complete=True, historical_ledger_overwritten=False,
                  head_transport_is_internal_not_external_input=True, extra_tank_volume_is_not_added_to_fluid_mass=True,
                  full_device_first_law_verified=False, physical_mass_closure_verified=False,
                  full_internal_periodicity_verified=False, production_recovery_allowed=False, table4_reproduction_claim=False)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in result.items() if k not in ('components', 'stages', 'input_sha256')}, indent=2))


if __name__ == '__main__':
    main()
