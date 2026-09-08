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
from Audit_HeatDriveECC_ColdChamberRejection import CHAMBERS, ROOT, edges, read
from Audit_HeatDriveECC_ColdCoordinateSmoke import compare_initial, scalar_series, ledger
from Audit_HeatDriveECC_ConservativeBufferTrial import inventory, NAMES
from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field
from Audit_HeatDriveECC_TLDomainInventory import resolve_domains


PRODUCER = 'fde7153fddc9706d18f5a69b2e198bbbbb11247c'
EXPERIMENT = 'conservative_buffer_coupled_smoke_20260909_v2'
BUFFERS = {ROOT+n for n in ('ColdFluidBuffer', 'HotFluidBuffer', 'SHEXFluidBuffer', 'SMAHotFluidBuffer')}


def topology_check(native, candidate):
    if edges(native) != edges(candidate):
        raise ValueError('Named physical edges changed')
    projected = copy.deepcopy(candidate)
    source = {b['block_path']: b['source_file'] for b in native['blocks']}
    seen = set()
    for b in projected['blocks']:
        path = b['block_path']
        if path in BUFFERS | CHAMBERS:
            expected = 'ecc_buffer_coupled.conservative_buffer' if path in BUFFERS else 'ecc_inventory.conservative_chamber'
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
    if np.any(get('p_I', 'Pa') != c['p_environment_Pa']) or np.any(get('Q_H', 'W') != 0):
        raise ValueError('Unconnected thermal port or constant pressure contract changed')
    return dict(block_path=path, independent_ledger=local, inventory_alias_pass=alias_pass,
                energy_alias_errors_J=errors, auxiliary_alias_errors=auxiliary,
                energy_parts_change_J={k: float(v[-1]-v[0]) for k, v in r['parts'].items()},
                candidate_component_pass=bool(alias_pass and local['mass_closure_pass'] and local['energy_closure_pass']))


def audit(repo):
    root = repo/'outputs_storage_audit'/EXPERIMENT
    execution = read(root/'cold_chamber_execution.json'); stop = .01
    if (execution['execution_commit'] != PRODUCER or not execution['collection_pass'] or not execution['conservative_buffers']
            or execution['start_time_s'] != 0 or execution['stop_time_s'] != stop
            or any(execution[k] for k in ('c200_state_imported', 'checkpoint_saved', 'production_recovery_allowed'))
            or [c['arm'] for c in execution['cases']] != ['native', 'conservative']):
        raise ValueError('Wrong independent cold experiment')
    for c in execution['cases']:
        if sha256(root/c['arm']/'observations.mat') != c['observation_sha256']:
            raise ValueError('Observation hash mismatch')
    assignment = topology_check(read(root/'native/tl_connectivity.json'), read(root/'conservative/tl_connectivity.json'))
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
    for c in contracts.values():
        port_contract(c)
        if (c['inlet_height_m'] != 0 or c['initial_source_time_s'] != 0 or c['mainline_recovery_allowed']
                or c['tank_area_m2'] != .001 or c['port_area_m2'] != .01 or c['auxiliary_depth_m'] != .001
                or c['gravity_m_s2'] != 9.81 or c['p_environment_Pa'] != 1e6):
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
        time = np.arange(11)*.001
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
    for key in ('result', 'checkpoint'):
        p = repo/frozen[key+'_relative_path']
        if sha256(p) != frozen[key+'_sha256']: raise ValueError('Frozen C200 changed')
        files.append(p)
    files += [p for p in root.rglob('*') if p.is_file() and p.suffix in ('.json', '.mat', '.log', '.ssc') and not any(x in p.parts for x in ('cache', 'codegen'))]
    strict = all(r['within_strict_comparison'] for r in comparisons)
    local_pass = all(r['candidate_component_pass'] for r in local) and all(
        r['local_chamber_gate']['mass_closure_pass'] and r['local_chamber_gate']['energy_closure_pass'] for r in chambers)
    result = dict(schema='heatdrive_ecc_cold_buffer_coupled_smoke_audit_v1', evidence_audit_pass=True,
        execution_commit=PRODUCER, stop_time_s=stop, samples=11, buffers=local, chambers=chambers,
        topology_edges_and_domain_assignment_identical=True, property_tables_identical=True,
        source_storage_port_checks=kcls, local_inventory_conservation_pass=local_pass,
        strict_initial_coordinate_match=strict, initial_matching_counts={p: sum(r['within_strict_comparison'] for r in comparisons if r['priority'] == p) for p in ('High', 'Low')},
        cold_smoke_numerical_gates_pass=bool(local_pass and strict and all(r['passed'] for r in kcls)),
        full_cycle_completed=False, all_mechanism_gates_evaluated=False, full_device_first_law_verified=False,
        production_recovery_allowed=False, table4_reproduction_claim=False,
        input_sha256={str(p.relative_to(repo)): sha256(p) for p in sorted(set(files))})
    return result, comparisons


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--output-root', type=Path, required=True)
    args = parser.parse_args()
    if args.output_root.exists(): raise FileExistsError('Never overwrite evidence')
    result, comparisons = audit(Path(__file__).resolve().parents[1])
    args.output_root.mkdir(parents=True)
    (args.output_root/'cold_buffer_coupled_audit.json').write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    with (args.output_root/'initial_coordinates.csv').open('w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=list(comparisons[0])); writer.writeheader(); writer.writerows(comparisons)
    print(json.dumps({k: result[k] for k in ('evidence_audit_pass', 'local_inventory_conservation_pass',
        'strict_initial_coordinate_match', 'initial_matching_counts', 'source_storage_port_checks', 'cold_smoke_numerical_gates_pass', 'production_recovery_allowed')}, indent=2))
    raise SystemExit(0 if result['cold_smoke_numerical_gates_pass'] else 1)
