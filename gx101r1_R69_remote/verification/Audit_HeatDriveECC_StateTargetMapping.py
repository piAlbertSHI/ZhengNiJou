"""Bind public target names to observed C200 values, without authorizing restore."""
import argparse
from collections import Counter
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C200StateCapture import archived_source
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field


def match_targets(targets, native):
    paths = [row['path'] for row in targets]
    if len(set(paths)) != len(paths):
        raise ValueError('Duplicate public target identity')
    mapped, missing = [], []
    for target in targets:
        priority = target['priority']
        if priority not in ('None', 'Low', 'High'):
            raise ValueError('Unknown priority')
        path = target['path']
        if path not in native:
            if priority != 'None':
                raise ValueError('Active target lacks a named observation: ' + path)
            missing.append(path)
            continue
        row = native[path]
        if row['unit'] != target['unit']:
            raise ValueError('Unit mismatch: ' + path)
        values = np.asarray(row['values'], dtype=float)
        if (values.shape != (2,) or not np.isfinite(values).all()
                or not np.array_equal(row['time_s'], [2000, 2000.001])):
            raise ValueError('Require the exact two-sample C200 observed window')
        declared = np.asarray(target['value'], dtype=float)
        if declared.size != 1 or not np.isfinite(declared).all():
            raise ValueError('Expected finite scalar declared target')
        mapped.append(dict(path=path, unit=row['unit'], priority=priority,
                           declared_value=float(declared.item()), c200_value=float(values[0]),
                           sample_time_s=2000, difference_from_declared=float(values[0]-declared.item())))
    return mapped, missing


def read_native(path, model):
    rows = {}
    with h5py.File(path) as f:
        for ref in f['native'][:].flat:
            row = f[ref]
            block = text_field(row['block_path'])
            if not block.startswith(model + '/'):
                raise ValueError('Unexpected source model')
            key = block[len(model)+1:] + '/' + text_field(row['state_name'])
            if key in rows:
                raise ValueError('Duplicate observation identity')
            rows[key] = dict(unit=text_field(row['unit']),
                             time_s=row['time_s'][:].reshape(-1), values=row['values'][:].reshape(-1))
    return rows


def compute(repo):
    base = repo/'outputs_storage_audit'
    origin = base/'c200_source_compatibility_20260907'
    source = archived_source(origin)
    capture_path = origin/'c200_state_capture_v1.json'
    capture = json.loads(capture_path.read_text(encoding='utf-8-sig'))
    native_path = origin/'archived_source_probe_v4/restored_step_signals.mat'
    registered_path = origin/'archived_source_probe_v4/registered_states.mat'
    if (capture['schema'] != 'heatdrive_ecc_c200_state_capture_v1'
            or not capture['all_observation_comparisons_pass'] or capture['maximum_observation_difference'] != 0
            or capture['packed_solver_semantic_mapping_verified'] or capture['new_model_recovery_allowed']
            or sha256(native_path) != capture['input_sha256']['observed']
            or sha256(registered_path) != capture['input_sha256']['registered']):
        raise ValueError('Unverified C200 observations')
    catalog_path = base/'state_target_catalog_20260908/target_catalog.json'
    catalog = json.loads(catalog_path.read_text(encoding='utf-8-sig'))
    mat = catalog_path.with_name('public_targets.mat')
    if (catalog['schema'] != 'heatdrive_ecc_state_target_catalog_v1' or not catalog['collection_pass']
            or catalog['extraction_phase'] != 'Prestart' or catalog['simulation_run']
            or catalog['model_initialization_requested'] or catalog['production_checkpoint_loaded']
            or catalog['state_migration_verified'] or catalog['production_recovery_allowed']
            or sha256(mat) != catalog['public_targets_sha256']):
        raise ValueError('Unexpected public target extraction')
    authority_path = repo/'verification/c200_mainline_freeze_contract.json'
    authority = json.loads(authority_path.read_text(encoding='utf-8-sig'))
    if (catalog['source_checkpoint_sha256'] != authority['checkpoint_sha256']
            or sha256(repo/authority['checkpoint_relative_path']) != authority['checkpoint_sha256']
            or sha256(repo/authority['result_relative_path']) != authority['result_sha256']):
        raise ValueError('Frozen authority changed')
    native = read_native(native_path, catalog['root_identifier'])
    mapped, missing = match_targets(catalog['targets'], native)
    active = [r for r in mapped if r['priority'] != 'None']
    counts = Counter(r['priority'] for r in active)
    if (len(native) != 1240 or len(mapped) != 619 or len(catalog['targets']) != 2668
            or counts != {'High': 121, 'Low': 4}):
        raise ValueError('Public target or observation coverage changed')
    # Cross-check the compact recorded memories against their actual MAT observations.
    memories, opaque = [], []
    expected = {(r['block_path'], r['state_name']): r for r in capture['all_registered_states']}
    seen = set()
    with h5py.File(registered_path) as f:
        for ref in f['observation']['states'][:].flat:
            row = f[ref]
            key = (text_field(row['block_path']), text_field(row['state_name']))
            values, times = row['values'][:], row['time_s'][:].reshape(-1)
            if (key in seen or key not in expected or not np.array_equal(times,[2000,2000.001])
                    or not np.array_equal(values[:,0],expected[key]['initial_values'])
                    or not np.array_equal(values[:,1],expected[key]['final_values'])):
                raise ValueError('Registered state provenance mismatch')
            seen.add(key)
            record = dict(block_path=key[0], state_name=key[1], channels=values.shape[0],
                          c200_values=values[:,0].tolist())
            (opaque if key[0].endswith('/Solver Configuration') else memories).append(record)
    if len(seen) != 73 or len(opaque) != 1 or opaque[0]['channels'] != 995:
        raise ValueError('Registered-state coverage changed')
    return dict(schema='heatdrive_ecc_state_target_mapping_v1', computation_complete=True,
                source=source, source_time_s=2000, target_count=2668, native_count=1240,
                exact_name_unit_matches=619, active_target_count=125,
                active_priority_counts=dict(counts),
                active_defaults_differ_from_c200=sum(r['difference_from_declared'] != 0 for r in active),
                mapped_targets=mapped, initialization_candidates=active,
                unobserved_public_target_paths=missing,
                named_nonnetwork_state_groups=memories, named_nonnetwork_scalar_channels=sum(r['channels'] for r in memories),
                opaque_solver_channels=995, opaque_solver_mapping_attempted=False,
                original_catalog_contains_private_data=catalog['has_private_data'],
                original_operating_point_edited=False, model_initialized=False,
                initial_state_preservation_verified=False, unchanged_model_roundtrip_verified=False,
                structural_migration_verified=False, production_recovery_allowed=False,
                whole_model_first_law_verified=False, table4_reproduction_claim=False,
                limitations=['Prestart values are defaults, not C200 states.',
                             'Target values do not replace ModelOperatingPoint hidden execution state.',
                             'Low priorities retained; initialization may move these values.',
                             'Unobserved algebraic targets are not assigned guessed values.',
                             'No state reset, event shift, or physical connector replacement has been executed.'],
                input_sha256=dict(catalog=sha256(catalog_path),public_targets=sha256(mat),
                                  capture=sha256(capture_path),native=sha256(native_path),registered=sha256(registered_path),
                                  authority=sha256(authority_path)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite mapping evidence')
    result = compute(args.repo)
    args.output.write_text(json.dumps(result,indent=2,ensure_ascii=False,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in (
        'mapped_targets','initialization_candidates','unobserved_public_target_paths','named_nonnetwork_state_groups')},indent=2))


if __name__ == '__main__':
    main()
