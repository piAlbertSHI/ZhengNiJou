"""Independent cold buffer integration audit. Never grants mainline recovery."""
import argparse
from collections import Counter
import copy
import csv
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_ColdChamberCycle import checked_rows, custom_ledger, source_ledger
from Audit_HeatDriveECC_C201Inventory import ledgers, stage_totals
from Audit_HeatDriveECC_C201BoundaryCycle import integral_summary
from Audit_HeatDriveECC_C201Cycle import metrics
from Audit_HeatDriveECC_ColdChamberRejection import CHAMBERS, ROOT, edges, read
from Audit_HeatDriveECC_ColdCoordinateSmoke import compare_initial, scalar_series, ledger
from Audit_HeatDriveECC_ConservativeBufferTrial import inventory, NAMES
from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_NativeWindowLedger import validate_grid
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field
from Audit_HeatDriveECC_TLDomainInventory import resolve_domains, density_table, scalar
from Audit_HeatDriveECC_CompiledInventoryStates import decode_tags, component_inventory_preserved


PRODUCER = 'fde7153fddc9706d18f5a69b2e198bbbbb11247c'
EXPERIMENT = 'conservative_buffer_coupled_smoke_20260909_v2'
CYCLE_PRODUCER = '6148ebd49c3679821684a0e6206b8661e54fa7fa'
CYCLE_EXPERIMENT = 'conservative_buffer_coupled_cycle_20260909'
SPECIFIC_PRODUCER = '7408b1deda367f2d5324bd75e66ab593114cc459'
SPECIFIC_EXPERIMENT = 'specific_inventory_cold_onset_20260909'
FULL_SPECIFIC_085_PRODUCER = '0234f91a5bc86767abf87dd8d3040d362c6461c9'
FULL_SPECIFIC_TUNED_085_PRODUCER = '728f013ae3037f63473559567eed0fc921396312'
FULL_SPECIFIC_TUNED100_220_085_PRODUCER = '0360cf4bd445d8e49415e118ad499b53cc820b12'
FULL_SPECIFIC_TUNED110_255_085_PRODUCER = '3bbfbda56ab5d0800f147cc42c85d649e9069fed'
FULL_SPECIFIC_TUNED120_225_085_PRODUCER = '6c3d325cb45cc473a3a380d21044674bea5e6bc1'
FULL_SPECIFIC_TUNED125_225_085_PRODUCER = '800ada7f9d1a56039c271cd037fb7b14acfbcbc7'
FULL_SPECIFIC_TUNED124_225_085_PRODUCER = '972e512df80844244d1265fe300d29f4d6911c32'
BUFFERS = {ROOT+n for n in ('ColdFluidBuffer', 'HotFluidBuffer', 'SHEXFluidBuffer', 'SMAHotFluidBuffer')}


def topology_check(native, candidate, chamber_source='ecc_inventory.conservative_chamber'):
    if chamber_source not in ('ecc_inventory.conservative_chamber', 'ecc_inventory_specific.conservative_chamber'):
        raise ValueError('Unknown declared chamber source')
    if edges(native) != edges(candidate):
        raise ValueError('Named physical edges changed')
    projected = copy.deepcopy(candidate)
    source = {b['block_path']: b['source_file'] for b in native['blocks']}
    seen = set()
    for b in projected['blocks']:
        path = b['block_path']
        if path in BUFFERS | CHAMBERS:
            expected = 'ecc_buffer_coupled.conservative_buffer' if path in BUFFERS else chamber_source
            if b['source_file'] != expected:
                raise ValueError('Unexpected replacement class')
            seen.add(path)
            b['source_file'] = source[path]
        elif b['source_file'] != source.get(path):
            raise ValueError('Unexpected physical component changed')
    if seen != BUFFERS | CHAMBERS or len(projected['blocks']) != len(source):
        raise ValueError('Incomplete replacement coverage')
    a, na = resolve_domains(native); b, nb = resolve_domains(projected)
    if na != 2 or nb != 2 or a != b:
        raise ValueError('Fluid domain assignment changed')
    return a


def port_contract(record):
    ports = record['original_conserving_ports']; outputs = record['removed_unconnected_outputs']
    if len(ports) != 2 or len(outputs) != 3:
        raise ValueError('Wrong original port inventory')
    expected = {'A': ('LConn', 1, 'foundation.thermal_liquid.thermal_liquid', True),
                'H': ('RConn', 1, 'foundation.thermal.thermal', False)}
    if {p['name'] for p in ports} != set(expected):
        raise ValueError('Wrong conserving ports')
    for p in ports:
        if p['interface_type'] != 'Domain' or tuple(p[k] for k in ('side', 'index', 'domain', 'connected')) != expected[p['name']]:
            raise ValueError('Wrong conserving port layout or connection')
    if {p['name'] for p in outputs} != {'L_out', 'T_out', 'V_out'} or any(
            p['interface_type'] != 'Output' or p['domain'] or p['connected'] for p in outputs):
        raise ValueError('Removed connected or unknown output')


def buffer_ledger(rows, path, table, contract):
    if {k[1] for k in rows if k[0] == path} != NAMES:
        raise ValueError('Incomplete buffer native leaves')
    def get(n, u):
        r = rows[path, n]
        if u == 'J/K' and text_field(r['unit']) == 'kJ/K':
            return r['values'][:].reshape(-1)*1000
        return scalar_series(r, u)
    mass, temp = get('stored_mass', 'kg'), get('T_I', 'K')
    c = contract
    r = inventory(table, temp, mass, c['p_environment_Pa'], c['tank_area_m2'], c['gravity_m_s2'],
                  c['reference_temperature_K'], c['auxiliary_depth_m'])
    errors = {k: float(abs(v-get(k, 'J')).max()) for k, v in r['parts'].items()}
    errors['stored_energy'] = float(abs(r['total']-get('stored_energy', 'J')).max())
    auxiliary = {}
    for k, name, unit, limit in [('volume', 'volume', 'm^3', 1e-12), ('level', 'level', 'm', 1e-10),
            ('rho', 'rho_I', 'kg/m^3', 1e-7), ('u', 'u_I', 'J/kg', 1e-6), ('u_port', 'u_port', 'J/kg', 1e-6),
            ('port_pressure', 'p_A', 'Pa', 1e-6), ('capacity', 'auxiliary_capacity', 'J/K', 1e-8)]:
        error = float(abs(r[k]-get(name, unit)).max())
        auxiliary[name] = dict(max_abs_error=error, limit=limit, passed=error <= limit)
    t = rows[path, 'T_I']['time_s'][:].reshape(-1)
    local = ledger(t, mass, r['total'], get('mdot_A', 'kg/s'), get('Phi_A', 'W')+get('Q_H', 'W'))
    alias_pass = max(errors.values()) <= 1e-8 and all(v['passed'] for v in auxiliary.values())
    # Unit conversion from an MPa trace can produce a sub-nanopascal roundoff;
    # the physical contract is equality within the declared measurement scale.
    if np.any(abs(get('p_I', 'Pa') - c['p_environment_Pa']) > 1e-6) or np.any(get('Q_H', 'W') != 0):
        raise ValueError('Unconnected thermal port or constant pressure contract changed')
    return dict(block_path=path, independent_ledger=local, inventory_alias_pass=alias_pass,
                energy_alias_errors_J=errors, auxiliary_alias_errors=auxiliary,
                energy_parts_change_J={k: float(v[-1]-v[0]) for k, v in r['parts'].items()},
                candidate_component_pass=bool(alias_pass and local['mass_closure_pass'] and local['energy_closure_pass']))


def cycle_arm(folder, assignment, contracts):
    meta = read(folder/'inventory_metadata.json')
    tables = {r['block_path']: energy_tables(r['parameters']) for r in meta['settings_tables']}
    densities = {r['block_path']: density_table(r['parameters']) for r in meta['settings_tables']}
    sources = {b['block_path']: b['source_file'] for b in read(folder/'tl_connectivity.json')['blocks']}
    time = np.arange(10001)*.001; components = []; consumed = set()
    with h5py.File(folder/'observations.mat') as f:
        rows = checked_rows(f, 'native', 1240 if folder.name == 'native' else 1258)
        for original in meta['storage_blocks']:
            block = copy.deepcopy(original); path = block['block_path']; kind = block['mask_type']
            block['reference_block'] = sources.get(path, 'foundation.thermal.elements.mass')
            block['leaf_variables'] = []
            for key, r in rows.items():
                if key[0] == path:
                    consumed.add(key)
                    block['leaf_variables'].append(dict(name=key[1], unit=text_field(r['unit']),
                        time_s=r['time_s'][:].reshape(-1), values=r['values'][:].reshape(-1)))
            table = tables.get(assignment.get(path)); nominal = None
            if kind == 'Pipe (TL)':
                mode = block['model_modes']; p = block['mask_parameters']
                temp = scalar(mode['T_nominal'], mode['T_nominal_unit'], 'K')
                pressure = scalar(mode['p_nominal'], mode['p_nominal_unit'], 'Pa')
                if p['area']['unit'] != 'm^2' or p['length']['unit'] != 'm': raise ValueError('Unexpected native pipe geometry units')
                nominal = float(densities[assignment[path]]([[temp, pressure]])[0])*p['area']['value']*p['length']['value']
            if kind == 'Conservative Buffer (TL)':
                detail = buffer_ledger(rows, path, table, contracts[path]); c = contracts[path]
                get = lambda n, u: scalar_series(rows[path, n], u)
                mass = get('stored_mass', 'kg')
                reconstructed = inventory(table, get('T_I', 'K'), mass, c['p_environment_Pa'], c['tank_area_m2'],
                    c['gravity_m_s2'], c['reference_temperature_K'], c['auxiliary_depth_m'])
                energy = reconstructed['total']
                energy_input = np.r_[0, np.cumsum((get('Phi_A', 'W')+get('Q_H', 'W'))[1:]*np.diff(time))]
                mass_input = np.r_[0, np.cumsum(get('mdot_A', 'kg/s')[1:]*np.diff(time))]
                h = dict(endpoint_energy_residual_J=energy_input-(energy-energy[0]),
                         endpoint_mass_residual_kg=mass_input-(mass-mass[0]))
                row = dict(block_path=path, mask_type=kind, energy_endpoint_change_J=float(energy[-1]-energy[0]),
                           pressure_volume_work_J=0., endpoint_energy_residual_J_end=float(h['endpoint_energy_residual_J'][-1]),
                           endpoint_mass_residual_kg_end=float(h['endpoint_mass_residual_kg'][-1]),
                           energy_basis='M*u + p_environment*V + M*g*level/2 + C_aux*(T-T_ref); do not add p*dV again',
                           component_detail=detail)
            elif block['conservative_diagnostic']:
                if path not in CHAMBERS: raise ValueError('Unknown custom storage')
                row, h = custom_ledger(block, table)
            else:
                row, h = ledgers(block, table, nominal)
            row['stages'] = stage_totals(h); components.append(row)
        if consumed != set(rows) or len(components) != 119 or len({r['block_path'] for r in components}) != 119:
            raise ValueError('Unaccounted storage leaves')
        rates, source_rows, pumps = source_ledger(f, read(folder/'thermal_connectivity.json'), time)
        signals = {}
        for key, r in f['signals'].items():
            validate_grid(r['time_s'][:].reshape(-1), 0, 10, .001)
            values = r['values'][:]
            if values.ndim != 2 or values.shape[1] != 10001 or not np.isfinite(values).all(): raise ValueError('Incomplete public signals')
            signals[key] = values
        with h5py.File(folder/'configuration.mat') as config:
            performance, solids, flows = metrics(signals, config['options'], time, origin=0)
        storage = sum(scalar_series(r, 'W') for (_, n), r in rows.items() if n.startswith('Phi_') or n in ('Q_H', 'Q'))
        kcl = sum(rates.values())-storage
    endpoint = sum(r['energy_endpoint_change_J']+r.get('pressure_volume_work_J', 0) for r in components)
    source_input = integral_summary(sum(rates.values()), time)['BE_energy_J']
    residual = source_input-endpoint
    if abs(residual-sum(r['endpoint_energy_residual_J_end'] for r in components)-integral_summary(kcl, time)['BE_energy_J']) > 1e-7:
        raise ValueError('Full source/storage ledger identity failed')
    groups = {kind: dict(count=sum(r['mask_type'] == kind for r in components),
                        endpoint_energy_residual_J=sum(r['endpoint_energy_residual_J_end'] for r in components if r['mask_type'] == kind))
              for kind in sorted({r['mask_type'] for r in components})}
    return dict(arm=folder.name, storage_count=119, source_count=49, samples=10001, omitted_intervals=0,
                components=components, component_groups=groups, source_rows=source_rows, pumps=pumps,
                source_ledger={k: integral_summary(v, time) for k, v in rates.items()},
                source_stages=stage_totals({k: np.r_[0, np.cumsum(v[1:]*np.diff(time))] for k, v in rates.items()}),
                BE_source_net_energy_J=source_input, actual_endpoint_storage_plus_pdv_J=endpoint,
                source_minus_actual_endpoint_storage_J=residual, selected_flow_gates=flows,
                performance=performance, selected_solid_balances=solids, own_actual_initial_inventory_used=True,
                full_device_first_law_verified=False, production_recovery_allowed=False,
                interpretation='One cold cycle, declared lumped storage and native ideal source boundaries only; not full device validation')


def audit(repo, full_cycle=False, specific_onset=False, experiment_root=None):
    if experiment_root is not None:
        root = Path(experiment_root).resolve()
        producer = {FULL_SPECIFIC_085_PRODUCER, FULL_SPECIFIC_TUNED_085_PRODUCER,
                    FULL_SPECIFIC_TUNED100_220_085_PRODUCER,
                    FULL_SPECIFIC_TUNED110_255_085_PRODUCER,
                    FULL_SPECIFIC_TUNED120_225_085_PRODUCER,
                    FULL_SPECIFIC_TUNED125_225_085_PRODUCER,
                    FULL_SPECIFIC_TUNED124_225_085_PRODUCER}
    else:
        if full_cycle and specific_onset: raise ValueError('Onset probe is not a full cycle')
        root = repo/'outputs_storage_audit'/(SPECIFIC_EXPERIMENT if specific_onset else CYCLE_EXPERIMENT if full_cycle else EXPERIMENT)
        producer = SPECIFIC_PRODUCER if specific_onset else CYCLE_PRODUCER if full_cycle else PRODUCER
    execution = read(root/'cold_chamber_execution.json'); stop = 10 if full_cycle else .2 if specific_onset else .01
    if (execution['execution_commit'] not in producer or not execution['collection_pass'] or not execution['conservative_buffers']
            or execution['start_time_s'] != 0 or execution['stop_time_s'] != stop
            or any(execution[k] for k in ('c200_state_imported', 'checkpoint_saved', 'production_recovery_allowed'))
            or [c['arm'] for c in execution['cases']] != ['native', 'conservative']):
        raise ValueError('Wrong independent cold experiment')
    for c in execution['cases']:
        if sha256(root/c['arm']/'observations.mat') != c['observation_sha256']:
            raise ValueError('Observation hash mismatch')
    compiled_gate = None
    if specific_onset:
        prereq = repo/'outputs_storage_audit/compiled_specific_inventory_audit_20260909/compiled_inventory_state_audit.json'
        pre = read(prereq)
        component = root/'component_build/+ecc_inventory_specific/conservative_chamber.ssc'
        original = (repo/'verification/simscape_inventory/+ecc_inventory/conservative_chamber.ssc').read_text(encoding='utf-8')
        expected = original.replace('stored_mass == volume * rho_I;', 'rho_I == stored_mass / volume;')
        expected = expected.replace('stored_energy == stored_mass * u_I;', 'u_I == stored_energy / stored_mass;')
        if (execution['inventory_formulation'] != 'specific_inventory' or execution['chamber_source_file'] != 'ecc_inventory_specific.conservative_chamber'
                or execution['compiled_inventory_gate_sha256'] != sha256(prereq) or not pre['specific_inventory_compiled_gate_pass']
                or not pre['evidence_audit_pass'] or pre['production_recovery_allowed']
                or component.read_text(encoding='utf-8') != expected
                or execution['chamber_library_sha256'] != sha256(root/'component_build/ecc_inventory_specific_lib.slx')):
            raise ValueError('Specific inventory onset source or compiled prerequisite changed')
        tags = read(root/'conservative/compiled_inventory_tags.json')
        if tags['chamber_source_file'] != execution['chamber_source_file'] or not tags['post_simulation_source_verified']:
            raise ValueError('Wrong trajectory source identity')
        tag_rows = [dict(block_name=r['block_name'], variable_name=r['variable_name'], **decode_tags(r)) for r in tags['node_metadata']]
        compiled_gate = component_inventory_preserved(tag_rows, {p.removeprefix(ROOT) for p in BUFFERS | CHAMBERS})
    assignment = topology_check(read(root/'native/tl_connectivity.json'), read(root/'conservative/tl_connectivity.json'),
                                'ecc_inventory_specific.conservative_chamber' if specific_onset else 'ecc_inventory.conservative_chamber')
    if edges(read(root/'native/thermal_connectivity.json')) != edges(read(root/'conservative/thermal_connectivity.json')):
        raise ValueError('Thermal physical edges changed')
    metas = {a: read(root/a/'inventory_metadata.json') for a in ('native', 'conservative')}
    if metas['native']['settings_tables'] != metas['conservative']['settings_tables']:
        raise ValueError('Fluid tables changed')
    for a, meta in metas.items():
        expected = {'Pipe (TL)': 67, 'Constant Volume Chamber (TL)': 2, 'Thermal Mass': 46,
                    'Tank (TL)' if a == 'native' else 'Conservative Buffer (TL)': 4}
        if dict(Counter(b['mask_type'] for b in meta['storage_blocks'])) != expected:
            raise ValueError('Incomplete storage coverage')
    tables = {r['block_path']: energy_tables(r['parameters']) for r in metas['native']['settings_tables']}
    replacement = read(root/'conservative/buffer_replacement_contract.json')
    targets = read(root/'conservative/public_inventory_targets.json')
    for record in (targets, replacement):
        if record['source_sha256'] != execution['cases'][0]['observation_sha256'] or record['source_time_s'] != 0:
            raise ValueError('Non-native or nonzero-time initialization source')
    if targets['has_private_data'] or len(targets['targets']) != 204 or Counter(t['priority'] for t in targets['targets']) != {'High': 125, 'Low': 79}:
        raise ValueError('Unexpected public initialization target coverage')
    contracts = {r['block_path']: r for r in replacement['buffers']}
    if set(contracts) != BUFFERS or len(replacement['buffers']) != 4:
        raise ValueError('Incomplete buffer replacement contract')
    expected_environment = (execution['diagnostic_network_absolute_pressure_MPa'] * 1e6
                            if experiment_root is not None else 1e6)
    for c in contracts.values():
        port_contract(c)
        if (c['inlet_height_m'] != 0 or c['initial_source_time_s'] != 0 or c['mainline_recovery_allowed']
            or c['tank_area_m2'] != .001 or c['port_area_m2'] != .01 or c['auxiliary_depth_m'] != .001
            or c['gravity_m_s2'] != 9.81 or c['p_environment_Pa'] != expected_environment):
            raise ValueError('Actual buffer geometry differs from declared experiment')
    comparisons = []; local = []; kcls = []
    with h5py.File(root/'native/observations.mat') as a, h5py.File(root/'conservative/observations.mat') as b:
        aa, bb = checked_rows(a, 'native', 1240, stop), checked_rows(b, 'native', 1258, stop)
        volumes = {r['block_path']: r['mask_parameters']['volume']['value'] for r in metas['native']['storage_blocks'] if r['block_path'] in CHAMBERS}
        for path, c in contracts.items():
            get = lambda n, u: scalar_series(aa[path, n], u)[0]
            mass, temp, rho, u = get('mass', 'kg'), get('T_I', 'K'), get('rho_I', 'kg/m^3'), get('u_I', 'J/kg')
            v = mass/rho; e = mass*u+c['p_environment_Pa']*v+mass*c['gravity_m_s2']*v/c['tank_area_m2']/2
            for key, expected in [('initial_mass_kg', mass), ('initial_volume_m3', v), ('initial_extended_energy_J', e), ('reference_temperature_K', temp)]:
                if not compare_initial(c[key], expected)['within_strict_comparison']:
                    raise ValueError('Buffer mapping is not measured same-run native t=0')
            actual = next(r for r in metas['conservative']['storage_blocks'] if r['block_path'] == path)['mask_parameters']
            for field, key in [('tank_area', 'tank_area_m2'), ('port_area', 'port_area_m2'), ('gravity', 'gravity_m_s2'),
                               ('p_environment', 'p_environment_Pa'), ('reference_temperature', 'reference_temperature_K'), ('auxiliary_depth', 'auxiliary_depth_m')]:
                if not np.isclose(actual[field]['value'], c[key], rtol=1e-14, atol=0):
                    raise ValueError('Actual model geometry does not match contract')
            local.append(buffer_ledger(bb, path, tables[assignment[path]], c))
        seen = set()
        for target in targets['targets']:
            key = target['block_path'], target['state_name']; unit = target['unit']
            if key in seen or target['source_time_s'] != 0:
                raise ValueError('Duplicate or nonzero-time target')
            seen.add(key)
            if key[1] in ('stored_mass', 'stored_energy'):
                if key[0] in BUFFERS:
                    expected = contracts[key[0]]['initial_mass_kg' if key[1] == 'stored_mass' else 'initial_extended_energy_J']
                elif key[0] in CHAMBERS:
                    expected = volumes[key[0]]*scalar_series(aa[key[0], 'rho_I'], 'kg/m^3')[0]
                    if key[1] == 'stored_energy': expected *= scalar_series(aa[key[0], 'u_I'], 'J/kg')[0]
                else: raise ValueError('Unknown stored inventory target')
            else: expected = scalar_series(aa[key], unit)[0]
            if abs(target['value']-expected) > 1e-12*max(1, abs(expected)):
                raise ValueError('Target differs from measured native initialization')
            comparisons.append(dict(path=target['path'], priority=target['priority'], unit=unit,
                                    **compare_initial(scalar_series(bb[key], unit)[0], expected)))
        chambers = []
        for block in metas['conservative']['storage_blocks']:
            if block['block_path'] not in CHAMBERS: continue
            block = copy.deepcopy(block); path = block['block_path']
            block['leaf_variables'] = [dict(name=k[1], unit=text_field(r['unit']), time_s=r['time_s'][:].reshape(-1),
                                           values=r['values'][:].reshape(-1)) for k, r in bb.items() if k[0] == path]
            row, _ = custom_ledger(block, tables[assignment[path]]); chambers.append(row)
        time = np.arange(round(stop/.001)+1)*.001
        for arm, f, rows in [('native', a, aa), ('conservative', b, bb)]:
            rates, _, _ = source_ledger(f, read(root/arm/'thermal_connectivity.json'), time)
            storage = sum(scalar_series(r, 'W') for (_, n), r in rows.items() if n.startswith('Phi_') or n in ('Q_H', 'Q'))
            error = float(abs(sum(rates.values())-storage).max())
            kcls.append(dict(arm=arm, max_abs_W=error, limit_W=1e-8, passed=error <= 1e-8))
    with h5py.File(root/'native/configuration.mat') as a, h5py.File(root/'conservative/configuration.mat') as b:
        if set(a['commands']) != set(b['commands']) or len(a['commands']) != 5: raise ValueError('Changed command set')
        for f in (a, b):
            s = f['options/simscape']
            if (not s['local_solver_enabled'][0, 0] or s['local_solver_sample_time_s'][0, 0] != .001 or
                    text_field(s['local_solver_choice']) != 'NE_BACKWARD_EULER_ADVANCER'): raise ValueError('Wrong solver')
        for n in a['commands']:
            for field in ('time_s', 'values'):
                if not np.array_equal(a['commands'][n][field][:], b['commands'][n][field][:]): raise ValueError('Changed command trajectory')
    contract_path = repo/'verification/c200_mainline_freeze_contract.json'; frozen = read(contract_path)
    files = [contract_path]
    if specific_onset:
        files += [prereq, component, root/'component_build/ecc_inventory_specific_lib.slx']
    for key in ('result', 'checkpoint'):
        p = repo/frozen[key+'_relative_path']
        if sha256(p) != frozen[key+'_sha256']: raise ValueError('Frozen C200 changed')
        files.append(p)
    files += [p for p in root.rglob('*') if p.is_file() and p.suffix in ('.json', '.mat', '.log', '.ssc') and not any(x in p.parts for x in ('cache', 'codegen'))]
    strict = all(r['within_strict_comparison'] for r in comparisons)
    local_pass = all(r['candidate_component_pass'] for r in local) and all(
        r['local_chamber_gate']['mass_closure_pass'] and r['local_chamber_gate']['energy_closure_pass'] for r in chambers)
    numerical_pass = bool(local_pass and strict and all(r['passed'] for r in kcls) and (not specific_onset or compiled_gate))
    result = dict(schema='heatdrive_ecc_cold_buffer_coupled_audit_v2', evidence_audit_pass=True,
        execution_commit=execution['execution_commit'], stop_time_s=stop, samples=round(stop/.001)+1, buffers=local, chambers=chambers,
        topology_edges_and_domain_assignment_identical=True, property_tables_identical=True,
        source_storage_port_checks=kcls, local_inventory_conservation_pass=local_pass,
        strict_initial_coordinate_match=strict, initial_matching_counts={p: sum(r['within_strict_comparison'] for r in comparisons if r['priority'] == p) for p in ('High', 'Low')},
        declared_window_numerical_gates_pass=numerical_pass,
        specific_inventory_onset_probe=specific_onset, trajectory_compiled_inventory_gate=compiled_gate,
        experiment_root=str(root) if experiment_root is not None else None,
        cold_smoke_numerical_gates_pass=numerical_pass if not full_cycle else None,
        full_cycle_completed=full_cycle, all_mechanism_gates_evaluated=False, full_device_first_law_verified=False,
        production_recovery_allowed=False, table4_reproduction_claim=False,
        input_sha256={str(p.relative_to(repo)): sha256(p) for p in sorted(set(files))})
    if full_cycle:
        result['arms'] = [cycle_arm(root/a, assignment, contracts) for a in ('native', 'conservative')]
    return result, comparisons


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--output-root', type=Path, required=True)
    parser.add_argument('--experiment-root', type=Path)
    parser.add_argument('--full-cycle', action='store_true')
    parser.add_argument('--specific-onset', action='store_true')
    args = parser.parse_args()
    if args.output_root.exists(): raise FileExistsError('Never overwrite evidence')
    result, comparisons = audit(Path(__file__).resolve().parents[1], args.full_cycle, args.specific_onset, args.experiment_root)
    args.output_root.mkdir(parents=True)
    (args.output_root/'cold_buffer_coupled_audit.json').write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    with (args.output_root/'initial_coordinates.csv').open('w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=list(comparisons[0])); writer.writeheader(); writer.writerows(comparisons)
    print(json.dumps({k: result[k] for k in ('evidence_audit_pass', 'local_inventory_conservation_pass',
        'strict_initial_coordinate_match', 'initial_matching_counts', 'source_storage_port_checks', 'declared_window_numerical_gates_pass', 'production_recovery_allowed')}, indent=2))
    if args.full_cycle:
        print(json.dumps([{k: a[k] for k in ('arm', 'source_minus_actual_endpoint_storage_J', 'component_groups', 'selected_flow_gates', 'performance')}
                          for a in result['arms']], indent=2))
    raise SystemExit(0 if result['declared_window_numerical_gates_pass'] else 1)
