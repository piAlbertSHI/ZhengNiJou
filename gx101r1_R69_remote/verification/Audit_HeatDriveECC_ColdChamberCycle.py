"""Independent cold-cycle ledger, never a matched-state or recovery qualification."""
import argparse
from collections import Counter, defaultdict
import copy
import csv
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_C201Inventory import ledgers, stage_totals
from Audit_HeatDriveECC_C201BoundaryCycle import integral_summary
from Audit_HeatDriveECC_C201Cycle import metrics
from Audit_HeatDriveECC_C201TankBasis import geometry
from Audit_HeatDriveECC_ColdChamberRejection import CHAMBERS, check_topology, edges, read
from Audit_HeatDriveECC_ColdCoordinateSmoke import compare_initial, scalar_series, ledger
from Audit_HeatDriveECC_NativeAccumulation import energy_tables, ENERGY_ATOL_J_KG
from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_NativeWindowLedger import EXPECTED_COUNTS, validate_grid
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field
from Audit_HeatDriveECC_TankEnergyBasis import analyze
from Audit_HeatDriveECC_ThermalConnectivity import wire_nets
from Audit_HeatDriveECC_TLDomainInventory import resolve_domains, density_table, scalar, DENSITY_ATOL_KG_M3


PRODUCER = '791b113feccca8a35f80b3c0ca24b4bb4129d894'
EXPERIMENT = 'cold_chamber_public_coordinates_cycle_20260909'
SOURCE_COUNTS = {'foundation.thermal_liquid.sources.pressure_source': 3,
                 'foundation.thermal.sources.temperature': 3,
                 'foundation.thermal.sources.controlled_heat_flow': 43}


def checked_rows(f, dataset, count, stop=10, start=0):
    rows = named_rows(f, f[dataset])
    if len(rows) != count:
        raise ValueError('Incomplete ' + dataset)
    for row in rows.values():
        validate_grid(row['time_s'][:].reshape(-1), start, stop, .001)
        if row['values'].shape != (1, round(stop/.001)+1) or not np.isfinite(row['values'][:]).all():
            raise ValueError('Nonfinite or incomplete scalar trace')
    return rows


def tank_endpoint_split(mass, cp, temperature, enthalpy):
    arrays = [np.asarray(v, dtype=float) for v in (mass, cp, temperature, enthalpy)]
    mass, cp, temperature, enthalpy = arrays
    if (mass.ndim != 1 or mass.size < 2 or any(v.shape != mass.shape for v in arrays)
            or not np.isfinite(arrays).all() or np.any(mass <= 0) or np.any(cp <= 0)):
        raise ValueError('Invalid tank endpoint decomposition')
    # Exact discrete product identity, not a fitted missing heat source.
    dm, dt, dh = np.diff(mass), np.diff(temperature), np.diff(enthalpy)
    secant = mass[1:]*(cp[1:]*dt-dh)
    product = dm*dh
    direct = mass[1:]*cp[1:]*dt + enthalpy[1:]*dm - np.diff(mass*enthalpy)
    error = direct-secant-product
    allowance = 32*np.finfo(float).eps*max(1., float(abs(mass*enthalpy).max()))
    if np.any(abs(error) > allowance):
        raise ValueError('Discrete tank product identity failed')
    return dict(cp_vs_enthalpy_secant_J=float(secant.sum()), discrete_product_term_J=float(product.sum()),
                coefficient_minus_enthalpy_endpoint_J=float(direct.sum()),
                identity_max_interval_error_J=float(abs(error).max()), identity_allowance_J=allowance,
                decomposition_is_not_a_physical_heat_correction=True)


def custom_ledger(block, table):
    leaves = {r['name']: r for r in block['leaf_variables']}
    def get(name, unit):
        r = leaves[name]
        return convert(r['values'], r['unit'], unit)
    t = leaves['rho_I']['time_s']
    p = block['mask_parameters']['volume']
    volume = float(convert(p['value'], p['unit'], 'm^3'))
    temp, pressure = get('T_I', 'K'), get('p_I', 'Pa')
    coords = np.column_stack((temp, pressure))
    rho, u = get('rho_I', 'kg/m^3'), get('u_I', 'J/kg')
    if (volume <= 0 or np.any(temp <= 0) or
            abs(table['rho'](coords)-rho).max() > DENSITY_ATOL_KG_M3 or
            abs(table['u'](coords)-u).max() > ENERGY_ATOL_J_KG):
        raise ValueError('Custom chamber property or geometry mismatch')
    mass, energy = volume*rho, volume*rho*u
    power = get('Phi_A', 'W') + get('Phi_B', 'W') + get('Q_H', 'W')
    mdot = get('mdot_A', 'kg/s') + get('mdot_B', 'kg/s')
    inp = np.r_[0, np.cumsum(power[1:]*np.diff(t))]
    mass_in = np.r_[0, np.cumsum(mdot[1:]*np.diff(t))]
    de, dm = inp-(energy-energy[0]), mass_in-(mass-mass[0])
    history = dict(BE_energy_input_J=inp, BE_coefficient_energy_residual_J=de,
                   endpoint_energy_residual_J=de, BE_coefficient_mass_residual_kg=dm,
                   endpoint_mass_residual_kg=dm)
    row = dict(block_path=block['block_path'], mask_type=block['mask_type'],
               equation_basis='dM/dt=sum(mdot); dU/dt=sum(Phi)+Q_H; M=V*rho; U=M*u',
               energy_endpoint_change_J=float(energy[-1]-energy[0]), pressure_volume_work_J=0.,
               mass_start_kg=float(mass[0]), mass_end_kg=float(mass[-1]),
               energy_start_J=float(energy[0]), energy_end_J=float(energy[-1]),
               temperature_start_K=float(temp[0]), temperature_end_K=float(temp[-1]),
               stored_mass_alias_max_error_kg=float(abs(mass-get('stored_mass', 'kg')).max()),
               stored_energy_alias_max_error_J=float(abs(energy-get('stored_energy', 'J')).max()),
               local_chamber_gate=ledger(t, mass, energy, mdot, power))
    row.update({k+'_end': float(v[-1]) for k, v in history.items()})
    row.update({k+'_max_abs': float(abs(v).max()) for k, v in history.items()})
    return row, history


def source_ledger(f, thermal, time):
    rows = checked_rows(f, 'source_traces', 162, stop=float(time[-1]), start=float(time[0]))
    nets = {p: net for net in wire_nets(thermal) for p in net}
    references = {b['block_path'] for b in thermal['blocks']
                  if b['source_file'] == 'foundation.thermal.elements.reference'}
    def is_reference(net):
        return any(p.rsplit(':', 1)[0] in references for p in net)
    def get(path, name, unit):
        return scalar_series(rows[path, name], unit)
    rates = defaultdict(lambda: np.zeros_like(time))
    counts = Counter(); sources = []; pumps = []; paths = set()
    for ref in f['boundary_metadata/blocks'][:].flat:
        b = f[ref]; path = text_field(b['block_path']); source = text_field(b['source_file'])
        if path in paths:
            raise ValueError('Duplicate source')
        paths.add(path); counts[source] += 1
        if source == 'foundation.thermal_liquid.sources.pressure_source':
            if text_field(b['parameters/power_spec']) != 'foundation.enum.power_spec.none':
                raise ValueError('Pressure source power mode changed')
            power = get(path, 'power', 'W')
            residual = get(path, 'Phi_A', 'W') + get(path, 'Phi_B', 'W') + power
            if np.any(power != 0) or abs(residual).max() > 1e-8:
                raise ValueError('Native pump algebraic balance failed')
            rho = .5*(get(path, 'rho_A', 'kg/m^3')+get(path, 'rho_B', 'kg/m^3'))
            if np.any(rho <= 0):
                raise ValueError('Nonpositive pump density')
            hydraulic = get(path, 'P', 'Pa')*get(path, 'mdot_A', 'kg/s')/rho
            pumps.append(dict(block_path=path, native=integral_summary(power, time),
                              signed_hydraulic_estimate=integral_summary(hydraulic, time),
                              hydraulic_estimate_not_added_as_heat=True))
            rates['native_pump_input'] += power
            continue
        a = nets[path+':A']
        q = get(path, 'Q', 'W')
        if source == 'foundation.thermal.sources.controlled_heat_flow':
            bnet = nets[path+':B']
            if not is_reference(a) or is_reference(bnet) or not np.array_equal(q, get(path, 'S', 'W')):
                raise ValueError('Unverified controlled-source sign or command')
            role = ('SMA_constitutive_in' if '/SMA/' in path else 'SE_constitutive_in') if '/Subsystem2/' in path else 'external_load_in'
        elif source == 'foundation.thermal.sources.temperature':
            # Public temperature.ssc has one port: Q : A.Q -> *.
            if path+':B' in nets or is_reference(a):
                raise ValueError('Unverified temperature-source sign')
            q = -q
            role = 'SHEX_source_in' if '/SHEX/' in path else ('CHEX_reservoir_in' if 'CHEXFixedReservoir' in path else 'HHEX_ambient_in')
        else:
            raise ValueError('Unclassified source')
        rates[role] += q
        sources.append(dict(block_path=path, role=role, **integral_summary(q, time)))
    if dict(counts) != SOURCE_COUNTS or paths != {k[0] for k in rows}:
        raise ValueError('Incomplete source coverage')
    return dict(rates), sources, pumps


def audit_arm(folder, assignment, expected_count):
    meta = read(folder/'inventory_metadata.json')
    if dict(Counter(b['mask_type'] for b in meta['storage_blocks'])) != EXPECTED_COUNTS:
        raise ValueError('Wrong storage component coverage')
    tables = {r['block_path']: energy_tables(r['parameters']) for r in meta['settings_tables']}
    densities = {r['block_path']: density_table(r['parameters']) for r in meta['settings_tables']}
    if set(tables) != set(assignment.values()):
        raise ValueError('Property domain mismatch')
    topology = read(folder/'tl_connectivity.json')
    source_files = {b['block_path']: b['source_file'] for b in topology['blocks']}
    time = np.arange(10001)*.001
    components = []; tanks = []; histories = {}; consumed = set()
    with h5py.File(folder/'observations.mat') as f:
        native = checked_rows(f, 'native', expected_count)
        storage = np.zeros_like(time)
        for (_, name), row in native.items():
            if name.startswith('Phi_') or name in ('Q_H', 'Q'):
                storage += scalar_series(row, 'W')
        for original in meta['storage_blocks']:
            block = copy.deepcopy(original); path = block['block_path']
            block['reference_block'] = source_files.get(path, 'foundation.thermal.elements.mass')
            block['leaf_variables'] = []
            for key, r in native.items():
                if key[0] == path:
                    consumed.add(key)
                    block['leaf_variables'].append(dict(name=key[1], unit=text_field(r['unit']),
                        time_s=r['time_s'][:].reshape(-1), values=r['values'][:].reshape(-1)))
            nominal = None; table = tables.get(assignment.get(path))
            if block['mask_type'] == 'Pipe (TL)':
                mode = block['model_modes']; p = block['mask_parameters']
                temp = scalar(mode['T_nominal'], mode['T_nominal_unit'], 'K')
                pressure = scalar(mode['p_nominal'], mode['p_nominal_unit'], 'Pa')
                if p['area']['unit'] != 'm^2' or p['length']['unit'] != 'm':
                    raise ValueError('Invalid pipe geometry units')
                nominal = float(densities[assignment[path]]([[temp, pressure]])[0])*p['area']['value']*p['length']['value']
            if block['conservative_diagnostic']:
                if path not in CHAMBERS:
                    raise ValueError('Unexpected custom storage')
                row, h = custom_ledger(block, table)
            else:
                row, h = ledgers(block, table, nominal)
            if block['mask_type'] == 'Tank (TL)':
                tank = analyze(block, table, *geometry(block))
                get = lambda n, u: scalar_series(native[path, n], u)
                temp, pressure = get('T_I', 'K'), get('p_I', 'Pa')
                tank['endpoint_decomposition'] = tank_endpoint_split(get('mass', 'kg'),
                    table['cp'](np.column_stack((temp, pressure))), temp, get('h_I', 'J/kg'))
                tank['endpoint_residual_J'] = row['endpoint_energy_residual_J_end']
                split = tank['endpoint_decomposition']
                reconstructed = (tank['original_BE_energy_residual_J'] + split['cp_vs_enthalpy_secant_J']
                                 + split['discrete_product_term_J'])
                if abs(reconstructed-tank['endpoint_residual_J']) > 1e-7:
                    raise ValueError('Tank endpoint/coefficient decomposition does not reconcile')
                tanks.append(tank)
            row['stages'] = stage_totals(h)
            components.append(row); histories[path] = h
        if consumed != set(native) or len(histories) != 119:
            raise ValueError('Unaccounted storage traces or duplicate blocks')
        rates, sources, pumps = source_ledger(f, read(folder/'thermal_connectivity.json'), time)
        signals = {}
        for key, r in f['signals'].items():
            validate_grid(r['time_s'][:].reshape(-1), 0, 10, .001)
            values = r['values'][:]
            if values.ndim != 2 or values.shape[1] != 10001 or not np.isfinite(values).all():
                raise ValueError('Invalid public signal')
            signals[key] = values
        with h5py.File(folder/'configuration.mat') as config:
            solver = config['options/simscape']
            if (not bool(solver['local_solver_enabled'][0, 0]) or
                    text_field(solver['local_solver_choice']) != 'NE_BACKWARD_EULER_ADVANCER' or
                    float(solver['local_solver_sample_time_s'][0, 0]) != .001):
                raise ValueError('Wrong local solver for BE integral')
            performance, solids, flows = metrics(signals, config['options'], time, origin=0)
    net = sum(rates.values()); kcl = net-storage
    endpoint = sum(r['energy_endpoint_change_J']+r.get('pressure_volume_work_J', 0) for r in components)
    source_energy = integral_summary(net, time)['BE_energy_J']
    groups = {}
    for kind in EXPECTED_COUNTS:
        rows = [r for r in components if r['mask_type'] == kind]
        groups[kind] = dict(count=len(rows), endpoint_energy_residual_J=sum(r['endpoint_energy_residual_J_end'] for r in rows),
                           coefficient_energy_residual_J=sum(r['BE_coefficient_energy_residual_J_end'] for r in rows),
                           endpoint_mass_residual_kg=sum(r['endpoint_mass_residual_kg_end'] for r in rows))
    endpoint_residual = source_energy-endpoint
    if abs(endpoint_residual-sum(v['endpoint_energy_residual_J'] for v in groups.values())-integral_summary(kcl, time)['BE_energy_J']) > 1e-7:
        raise ValueError('Independent source/storage ledger identity failed')
    positive_source = integral_summary(np.maximum(rates['SHEX_source_in'], 0), time)['trapezoid_mean_W']
    return dict(arm=folder.name, samples=10001, intervals_omitted=0, storage_count=119, native_trace_count=expected_count,
                source_count=49, source_trace_count=162, components=components, component_groups=groups,
                tank_coefficient_diagnostics=tanks, source_rows=sources, pumps=pumps,
                source_ledger={k: integral_summary(v, time) for k, v in rates.items()},
                source_stages=stage_totals({k: np.r_[0, np.cumsum(v[1:]*np.diff(time))] for k, v in rates.items()}),
                instantaneous_port_sum_max_abs_W=float(abs(kcl).max()), port_sum_tolerance_W=1e-8,
                instantaneous_port_sum_pass=bool(np.all(abs(kcl) <= 1e-8)),
                BE_source_net_energy_J=source_energy, actual_endpoint_storage_plus_pdv_J=endpoint,
                source_minus_actual_endpoint_storage_J=endpoint_residual,
                tank_extra_coefficient_and_head_not_removed_from_endpoint_residual=True,
                own_actual_initial_inventory_used=True, performance=performance, selected_solid_balances=solids,
                selected_flow_gates=flows, diagnostic_heat_driven_COP=performance['cooling_power_W']/positive_source if positive_source > 0 else None,
                COP_scope='One cold cycle only, excludes pump electricity; not qualified system COP',
                all_mechanism_gates_evaluated=False, full_device_first_law_verified=False,
                periodic_steady_state=False, production_recovery_allowed=False, table4_reproduction_claim=False)


def audit(repo):
    root = repo/'outputs_storage_audit'/EXPERIMENT
    execution = read(root/'cold_chamber_execution.json')
    if (execution['execution_commit'] != PRODUCER or not execution['collection_pass'] or
            execution['start_time_s'] != 0 or execution['stop_time_s'] != 10 or
            any(execution[k] for k in ('c200_state_imported', 'production_recovery_allowed', 'checkpoint_saved')) or
            [r['arm'] for r in execution['cases']] != ['native', 'conservative']):
        raise ValueError('Wrong independent experiment provenance')
    for r in execution['cases']:
        if sha256(root/r['arm']/'observations.mat') != r['observation_sha256']:
            raise ValueError('Raw evidence hash mismatch')
    native_topo = read(root/'native/tl_connectivity.json')
    topo = check_topology(native_topo, read(root/'conservative/tl_connectivity.json'))
    if edges(read(root/'native/thermal_connectivity.json')) != edges(read(root/'conservative/thermal_connectivity.json')):
        raise ValueError('Thermal edges changed')
    a_meta, b_meta = [read(root/arm/'inventory_metadata.json') for arm in ('native', 'conservative')]
    if a_meta['settings_tables'] != b_meta['settings_tables']:
        raise ValueError('Property tables changed between arms')
    assignment, _ = resolve_domains(native_topo)
    targets = read(root/'conservative/public_inventory_targets.json')
    if targets['has_private_data'] or targets['source_time_s'] != 0 or targets['source_sha256'] != execution['cases'][0]['observation_sha256']:
        raise ValueError('Invalid cold target provenance')
    comparisons = []; seen = set()
    with h5py.File(root/'native/observations.mat') as a, h5py.File(root/'conservative/observations.mat') as b:
        aa, bb = checked_rows(a, 'native', 1240), checked_rows(b, 'native', 1242)
        volumes = {r['block_path']: r['mask_parameters']['volume']['value'] for r in a_meta['storage_blocks'] if r['block_path'] in CHAMBERS}
        for target in targets['targets']:
            key = target['block_path'], target['state_name']; unit = target['unit']
            if key in seen or target['priority'] not in ('High', 'Low') or target['source_time_s'] != 0:
                raise ValueError('Duplicate or invalid public target')
            seen.add(key)
            if key[1] in ('stored_mass', 'stored_energy'):
                expected = volumes[key[0]]*scalar_series(aa[key[0], 'rho_I'], 'kg/m^3')[0]
                if key[1] == 'stored_energy':
                    expected *= scalar_series(aa[key[0], 'u_I'], 'J/kg')[0]
            else:
                expected = scalar_series(aa[key], unit)[0]
            if abs(target['value']-expected) > 1e-12*max(1, abs(expected)):
                raise ValueError('Target is not measured native cold initial state')
            comparisons.append(dict(path=target['path'], unit=unit, priority=target['priority'],
                **compare_initial(scalar_series(bb[key], unit)[0], expected)))
    if len(comparisons) != 200 or sum(r['priority'] == 'High' for r in comparisons) != 125:
        raise ValueError('Incomplete initialization coordinate coverage')
    with h5py.File(root/'native/configuration.mat') as a, h5py.File(root/'conservative/configuration.mat') as b:
        if set(a['commands']) != set(b['commands']) or len(a['commands']) != 5:
            raise ValueError('Command coverage differs')
        for name in a['commands']:
            for field in ('time_s', 'values'):
                if not np.array_equal(a['commands'][name][field][:], b['commands'][name][field][:]):
                    raise ValueError('Arm commands differ')
            t = a['commands'][name]['time_s'][:].reshape(-1)
            if t[0] != 0 or t[-1] != 10 or np.any(np.diff(t) <= 0):
                raise ValueError('Command is not a complete real cold cycle')
    arms = [audit_arm(root/arm, assignment, count) for arm, count in (('native', 1240), ('conservative', 1242))]
    files = [root/'cold_chamber_execution.json', root/'matlab_diary.log', root/'conservative/public_inventory_targets.json', root/'conservative/cold_public_targets.mat']
    for arm in ('native', 'conservative'):
        files.extend(root/arm/n for n in ('configuration.mat', 'observations.mat', 'inventory_metadata.json', 'tl_connectivity.json', 'thermal_connectivity.json'))
    contract_path = repo/'verification/c200_mainline_freeze_contract.json'; contract = read(contract_path); files.append(contract_path)
    for key in ('result', 'checkpoint'):
        p = repo/contract[key+'_relative_path']
        if sha256(p) != contract[key+'_sha256']:
            raise ValueError('Frozen C200 changed')
        files.append(p)
    foundation = Path('C:/Program Files/MATLAB/R2025b/toolbox/physmod/simscape/library/m/+foundation')
    source_hashes = {str(p): sha256(p) for p in [foundation/n for n in (
        '+thermal/+sources/temperature.ssc', '+thermal/+sources/controlled_heat_flow.ssc',
        '+thermal_liquid/+sources/pressure_source.ssc')]}
    result = dict(schema='heatdrive_ecc_independent_cold_cycle_ledger_v1', evidence_audit_pass=True,
        execution_commit=PRODUCER, start_time_s=0, stop_time_s=10, full_cold_cycle_collected=True,
        topology=topo, strict_initial_coordinate_match=all(r['within_strict_comparison'] for r in comparisons),
        initial_matching_counts={p: sum(r['within_strict_comparison'] for r in comparisons if r['priority'] == p) for p in ('High', 'Low')},
        matched_initial_performance_comparison_allowed=False, arms=arms, all_mechanism_gates_evaluated=False,
        full_device_first_law_verified=False, periodic_steady_state=False, production_recovery_allowed=False,
        table4_reproduction_claim=False, initialization_warnings_retained=True,
        source_sign_definition_sha256=source_hashes,
        input_sha256={str(p.relative_to(repo)): sha256(p) for p in files})
    return result, comparisons


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-root', type=Path, required=True)
    args = parser.parse_args()
    if args.output_root.exists():
        raise FileExistsError('Do not overwrite prior evidence')
    result, comparisons = audit(Path(__file__).resolve().parents[1])
    args.output_root.mkdir(parents=True)
    (args.output_root/'cold_cycle_ledger.json').write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    with (args.output_root/'initial_coordinates.csv').open('w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=list(comparisons[0])); writer.writeheader(); writer.writerows(comparisons)
    print(json.dumps(dict(evidence_audit_pass=True, strict_initial_coordinate_match=result['strict_initial_coordinate_match'],
        arms=[{k: a[k] for k in ('arm', 'instantaneous_port_sum_pass', 'source_minus_actual_endpoint_storage_J', 'component_groups', 'performance')} for a in result['arms']],
        production_recovery_allowed=False, output=str(args.output_root)), indent=2))
    # A diagnostic ledger is not a scientific acceptance certificate.
    raise SystemExit(0 if all(a['instantaneous_port_sum_pass'] for a in result['arms']) else 1)
