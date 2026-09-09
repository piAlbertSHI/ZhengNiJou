"""Audit retained differential inventory tags, not initialization target priority."""
import argparse
import csv
import json
from pathlib import Path

from Audit_HeatDriveECC_ColdChamberRejection import read
from Audit_HeatDriveECC_SegmentedEvidence import sha256


CHAMBERS = {'SMA_PumpInletConnectingPipeVolume', 'SMA_PumpOutletConnectingPipeVolume'}
BUFFERS = {'ColdFluidBuffer', 'HotFluidBuffer', 'SHEXFluidBuffer', 'SMAHotFluidBuffer'}
VARIABLES = {'stored_mass', 'stored_energy', 'T_I', 'p_I'}
CASES = [('baseline', 'cold_compiled_states_20260909_v4', '115aa93'),
         ('block_priority_redundant', 'cold_compiled_states_block_priority_20260909', 'd06a172'),
         ('unique_component_priority', 'cold_compiled_states_unique_priority_20260909', 'be31aca')]


def decode_tags(row):
    keys, values = row['tag_values']
    if len(keys) != len(values) or len(set(keys)) != len(keys) or keys != row['tag_names']:
        raise ValueError('Duplicate or mismatched metadata keys')
    tags = dict(zip(keys, values))
    if tags.get('context') != 'Simscape': raise ValueError('Wrong metadata context')
    result = {}
    for key in ('isStateValue', 'isDifferential', 'isRetained'):
        if tags.get(key) not in ('TRUE', 'FALSE'): raise ValueError('Unknown tag boolean')
        result[key] = tags[key] == 'TRUE'
    return result


def component_inventory_preserved(rows, blocks):
    expected = {(b, v) for b in blocks for v in VARIABLES}
    actual = {(r['block_name'], r['variable_name']) for r in rows}
    if len(rows) != len(expected) or actual != expected: raise ValueError('Incomplete component metadata')
    return all(r['isDifferential'] and r['isRetained'] for r in rows if r['variable_name'] in ('stored_mass', 'stored_energy'))


def audit(repo):
    records = []; combined = []; files = []
    for label, folder, producer in CASES:
        root = repo/'outputs_storage_audit'/folder
        source = root/'compiled_states_inspection.json'; record = read(source)
        if (not record['inspection_pass'] or not record['inspector_commit'].startswith(producer)
                or not record['initialization_only'] or record['source_time_s'] != 0 or record['dataset_elements'] != 73
                or any(record[k] for k in ('c200_state_imported', 'failed_terminal_state_imported', 'checkpoint_saved', 'production_recovery_allowed'))):
            raise ValueError('Wrong cold state inspection identity')
        if label == 'unique_component_priority':
            library = root/'component_build/ecc_inventory_priority_lib.slx'
            if (Path(record['loaded_chamber_library']).resolve() != library.resolve() or sha256(library) != record['loaded_library_sha256']
                    or record['chamber_source_file'] != 'ecc_inventory_priority.conservative_chamber'
                    or not record['component_inventory_priority_high']):
                raise ValueError('Ambiguous variant source identity')
            files += [library, root/'component_build/+ecc_inventory_priority/conservative_chamber.ssc']
        rows = [dict(case=label, block_name=r['block_name'], variable_name=r['variable_name'], **decode_tags(r)) for r in record['node_metadata']]
        if len(rows) != 24 or {(r['block_name'], r['variable_name']) for r in rows} != {(b, v) for b in CHAMBERS | BUFFERS for v in VARIABLES}:
            raise ValueError('Incomplete six-component metadata')
        chamber_pass = component_inventory_preserved([r for r in rows if r['block_name'] in CHAMBERS], CHAMBERS)
        buffer_pass = component_inventory_preserved([r for r in rows if r['block_name'] in BUFFERS], BUFFERS)
        records.append(dict(case=label, inspector_commit=record['inspector_commit'],
                            chamber_inventory_differential_gate=chamber_pass, buffer_inventory_differential_gate=buffer_pass))
        combined.extend(rows); files += [source, root/'compiled_initial_state_dataset.mat', root/'matlab_diary.log']
    frozen_path = repo/'verification/c200_mainline_freeze_contract.json'; frozen = read(frozen_path); files.append(frozen_path)
    for key in ('result', 'checkpoint'):
        p = repo/frozen[key+'_relative_path']
        if sha256(p) != frozen[key+'_sha256']: raise ValueError('C200 authority changed')
        files.append(p)
    return dict(schema='heatdrive_ecc_compiled_inventory_state_audit_v1', evidence_audit_pass=True, cases=records,
                all_1020_solver_state_entries_identified=False, selected_24_variable_tags_exported=True,
                priority_change_is_a_verified_repair=False, full_device_first_law_verified=False,
                production_recovery_allowed=False, table4_reproduction_claim=False,
                input_sha256={str(p.relative_to(repo)): sha256(p) for p in files}), combined


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--output-root', type=Path, required=True)
    args = parser.parse_args()
    if args.output_root.exists(): raise FileExistsError('Never overwrite evidence')
    result, rows = audit(Path(__file__).resolve().parents[1]); args.output_root.mkdir(parents=True)
    (args.output_root/'compiled_inventory_state_audit.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    with (args.output_root/'compiled_inventory_states.csv').open('w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)
    print(json.dumps({k: v for k, v in result.items() if k != 'input_sha256'}, indent=2))
    raise SystemExit(0 if all(r['chamber_inventory_differential_gate'] and r['buffer_inventory_differential_gate'] for r in result['cases']) else 1)
