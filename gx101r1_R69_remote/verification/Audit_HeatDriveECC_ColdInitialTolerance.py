"""Audit actual t=0 coordinates under distinct, explicitly configured tolerances."""
import argparse
from collections import Counter
import csv
import json
from pathlib import Path

from Audit_HeatDriveECC_ColdChamberRejection import read
from Audit_HeatDriveECC_ColdCoordinateSmoke import compare_initial
from Audit_HeatDriveECC_CompiledInventoryStates import CHAMBERS, BUFFERS, decode_tags, component_inventory_preserved
from Audit_HeatDriveECC_SegmentedEvidence import sha256


CASES = [('default', '4acaab9ec1c3b994e4410250a47d7403ec34ff41'),
         ('tight', '4acaab9ec1c3b994e4410250a47d7403ec34ff41'),
         ('residual', 'fc4a3b4489f5079a3032665f5b3354d271cea257')]
BASE = dict(ConsistencyTolSource='GLOBAL', ConsistencyAbsTol='0.001', ConsistencyRelTol='0.001',
            ConsistencyTolFactor='0.001', ResidualTolerance='0.001', UseLocalSolver='on',
            LocalSolverChoice='NE_BACKWARD_EULER_ADVANCER', LocalSolverSampleTime='0.001')


def check_settings(case, before, after):
    if before != BASE: raise ValueError('Unknown baseline solver settings')
    expected = dict(BASE)
    if case == 'tight': expected.update(ConsistencyTolSource='LOCAL', ConsistencyAbsTol='1e-9', ConsistencyRelTol='1e-9')
    elif case == 'residual': expected['ResidualTolerance'] = '1e-9'
    elif case != 'default': raise ValueError('Unknown tolerance experiment')
    if after != expected: raise ValueError('Settings changed outside the declared experiment')


def coordinates(observed, targets):
    expected = {r['path']: r for r in targets}
    if len(expected) != len(targets) or len(observed) != len(expected): raise ValueError('Incomplete or duplicate target coverage')
    seen = set(); rows = []
    for r in observed:
        if r['path'] in seen or r['path'] not in expected: raise ValueError('Duplicate or unknown coordinate')
        seen.add(r['path']); t = expected[r['path']]
        if (r['source_time_s'] != 0 or r['priority'] != t['priority'] or r['unit'] != t['unit']
                or r['native_unit'] != r['unit'] or r['actual'] != r['native_value'] or r['expected'] != t['value']):
            raise ValueError('Coordinate identity, units, source time or target changed')
        rows.append(dict(path=r['path'], priority=r['priority'], unit=r['unit'], **compare_initial(r['actual'], r['expected'])))
    return rows


def audit(repo):
    source = repo/'outputs_storage_audit/conservative_buffer_coupled_cycle_20260909'
    targets_file = source/'conservative/public_inventory_targets.json'
    target_record = read(targets_file); targets = target_record['targets']
    if (len(targets) != 204 or Counter(t['priority'] for t in targets) != {'High': 125, 'Low': 79}
            or target_record['has_private_data'] or target_record['source_time_s'] != 0):
        raise ValueError('Invalid frozen public cold target contract')
    native = source/'native/observations.mat'
    if sha256(native) != target_record['source_sha256']: raise ValueError('Native cold source changed')
    original = repo/'verification/simscape_inventory/+ecc_inventory/conservative_chamber.ssc'
    expected_component = original.read_text(encoding='utf-8').replace('stored_mass == volume * rho_I;', 'rho_I == stored_mass / volume;')
    expected_component = expected_component.replace('stored_energy == stored_mass * u_I;', 'u_I == stored_energy / stored_mass;')
    files = [targets_file, native, original]; records = []; all_rows = []; baseline = None
    for case, commit in CASES:
        root = repo/'outputs_storage_audit'/f'specific_inventory_initial_{case}_20260909'
        path = root/'compiled_states_inspection.json'; r = read(path)
        if (r['inspector_commit'] != commit or not r['inspection_pass'] or not r['initialization_only'] or r['source_time_s'] != 0
                or any(r[k] for k in ('failed_terminal_state_imported', 'c200_state_imported', 'checkpoint_saved', 'production_recovery_allowed'))
                or r['inventory_formulation'] != 'specific_inventory' or r['source_native_sha256'] != target_record['source_sha256']
                or not r['post_initialization_source_file_verified'] or r['component_inventory_priority_high']
                or r['block_temperature_pressure_priority_low'] or r['global_tolerances'] != {'RelTol': '1e-2', 'AbsTol': '1e-3'}):
            raise ValueError('Wrong diagnostic identity or undeclared change')
        check_settings(case, r['consistency_settings_before'], r['consistency_settings_after'])
        library = root/'component_build/ecc_inventory_specific_lib.slx'
        component = root/'component_build/+ecc_inventory_specific/conservative_chamber.ssc'
        if (Path(r['loaded_chamber_library']).resolve() != library.resolve() or sha256(library) != r['loaded_library_sha256']
                or r['chamber_source_file'] != 'ecc_inventory_specific.conservative_chamber'
                or component.read_text(encoding='utf-8') != expected_component):
            raise ValueError('Component identity changed')
        tags = [dict(block_name=t['block_name'], variable_name=t['variable_name'], **decode_tags(t)) for t in r['node_metadata']]
        compiled = component_inventory_preserved(tags, CHAMBERS | BUFFERS)
        rows = coordinates(r['initial_coordinates'], targets)
        measured = {t['path']: t['actual'] for t in rows}
        if baseline is None: baseline = measured
        strict = all(t['within_strict_comparison'] for t in rows)
        records.append(dict(case=case, inspector_commit=commit, configured_settings=r['consistency_settings_after'],
                            strict_initial_coordinate_match=strict, compiled_inventory_gate=compiled,
                            initial_matching_counts={p: sum(t['within_strict_comparison'] for t in rows if t['priority'] == p) for p in ('High', 'Low')},
                            actual_coordinates_identical_to_default=measured == baseline,
                            failed_by_unit=dict(Counter(t['unit'] for t in rows if not t['within_strict_comparison']))))
        all_rows.extend(dict(case=case, **t) for t in rows)
        files += [path, library, component, root/'compiled_initial_state_dataset.mat', root/'matlab_diary.log']
    frozen_path = repo/'verification/c200_mainline_freeze_contract.json'; frozen = read(frozen_path); files.append(frozen_path)
    for key in ('result', 'checkpoint'):
        p = repo/frozen[key+'_relative_path']
        if sha256(p) != frozen[key+'_sha256']: raise ValueError('C200 changed')
        files.append(p)
    return dict(schema='heatdrive_ecc_cold_initial_tolerance_audit_v1', evidence_audit_pass=True, cases=records,
                runtime_effective_tolerances_exported=False, tolerance_repair_verified=any(
                    r['strict_initial_coordinate_match'] and r['compiled_inventory_gate'] for r in records[1:]),
                production_recovery_allowed=False, full_device_first_law_verified=False, table4_reproduction_claim=False,
                input_sha256={str(p.relative_to(repo)): sha256(p) for p in files}), all_rows


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--output-root', type=Path, required=True)
    args = parser.parse_args()
    if args.output_root.exists(): raise FileExistsError('Never overwrite evidence')
    result, rows = audit(Path(__file__).resolve().parents[1]); args.output_root.mkdir(parents=True)
    (args.output_root/'initial_tolerance_audit.json').write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    with (args.output_root/'initial_coordinates.csv').open('w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)
    print(json.dumps({k: v for k, v in result.items() if k != 'input_sha256'}, indent=2))
    raise SystemExit(0 if result['tolerance_repair_verified'] else 1)
