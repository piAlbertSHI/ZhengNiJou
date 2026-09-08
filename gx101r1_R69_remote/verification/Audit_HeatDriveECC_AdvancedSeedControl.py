"""Verify the advanced-seed same-graph control, not structural migration."""
import argparse
import csv
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C200RestoredSignals import compare
from Audit_HeatDriveECC_OPAPIIsolation import ARMS, observation, require
from Audit_HeatDriveECC_PublicSnapshotEvidence import compare_window, observed, validate_source
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field
from Audit_HeatDriveECC_TargetInitialization import rows


SEED_COMMITS = {
    'zero_duration': 'cb37f959f79ca614547a6cef619cf664debaa4c8',
    'zero_duration_advanced_donor': 'dd62befcd0791efce2f2161b6652a7d376e66eaa',
}


def validate_isolation(meta, mode):
    require(meta['schema'] == 'heatdrive_ecc_op_api_isolation_v1'
            and meta['execution_commit'] == SEED_COMMITS[mode] and meta['seed_mode'] == mode
            and meta['matlab_release'] == '2025b', 'Isolation producer identity changed')
    require(meta['collection_complete'] is True and meta['error_message'] == ''
            and all(meta[k] is False for k in ('production_model_loaded',
                    'production_checkpoint_loaded', 'production_recovery_allowed')), 'Wrong isolation scope')
    require(meta['low_seed'] == dict(time_s=2000.001, memory_time_s=2000.001,
                                    temperature_K=340, memory=7.25), 'Wrong zero-duration recipient')
    if mode == 'zero_duration':
        require(meta['high_seed'] == dict(time_s=2000.001, memory_time_s=2000.001,
                                         temperature_K=400, memory=7.25), 'Wrong zero-duration donor')
    else:
        observation(meta['high_seed'], [2000, 2000.001], 400, 7.25)
    require([r['name'] for r in meta['cases']] == list(ARMS), 'Incomplete isolation arms')
    for row in meta['cases']:
        arm = row['name']
        require(row['target_temperature_K'] == (400 if arm == ARMS[1] else 340), 'Target confound')
        require(row['public_assignment_completed'] is (arm in ARMS[2:]), 'Wrong public assignment status')
        require(row['requested_memory'] == (8.25 if arm == ARMS[2] else 7.25), 'Wrong memory request')
        if arm == ARMS[1]:
            require(row['computation_complete'] is False and bool(row['error_message'])
                    and 'observed' not in row, 'Rejected target conflict produced a trajectory')
        else:
            require(row['computation_complete'] is True and row['error_message'] == '', 'Unexpected failed arm')
            observation(row['observed'], [2000.001, 2000.002], 340, 8.25 if arm == ARMS[2] else 7.25)
        expected = (7.25, 8.25) if arm == ARMS[2] else ((0, 400 if mode.endswith('advanced_donor') else 0)
                    if arm == ARMS[3] else ([], []))
        require((row['state_before'], row['state_after']) == expected, 'Wrong public readback')


def public_rows(path, name):
    result = {}
    with h5py.File(path) as handle:
        for ref in handle[name]['states'][:].flat:
            row = handle[ref]
            key = 'state/' + text_field(row['block_path']) + '/' + text_field(row['state_name'])
            require(key not in result, 'Duplicate public state identity')
            result[key] = (text_field(row['unit']), row['time_s'][:].reshape(-1), row['values'][:])
    return result


def summarize(comparisons):
    return dict(comparison_group_count=len(comparisons),
                failed_initial_groups=sum(not r['comparisons'][0]['pass_endpoint_match'] for r in comparisons),
                failed_one_step_groups=sum(not r['comparisons'][1]['pass_endpoint_match'] for r in comparisons),
                exact_initial_groups=sum(r['exact'][0] for r in comparisons),
                exact_one_step_groups=sum(r['exact'][1] for r in comparisons),
                max_scaled_error=max(c['max_scaled_error'] for r in comparisons for c in r['comparisons']),
                all_observations_pass=all(c['pass_endpoint_match'] for r in comparisons for c in r['comparisons']))


def compute(repo):
    base = repo / 'outputs_storage_audit'
    root = base / 'advanced_seed_public_snapshot_control_20260908'
    paths = []
    for mode, folder in (('zero_duration', 'operating_point_zero_duration_isolation_20260908'),
                         ('zero_duration_advanced_donor', 'operating_point_cross_seed_isolation_20260908')):
        path = base / folder / 'operating_point_api_isolation.json'
        validate_isolation(json.loads(path.read_text(encoding='utf-8-sig')), mode)
        paths.extend((path, path.parent / 'matlab_diary.log'))
    metadata_path = root / 'public_snapshot_control.json'
    meta = json.loads(metadata_path.read_text(encoding='utf-8-sig'))
    require(meta['schema'] == 'heatdrive_ecc_public_snapshot_control_v1'
            and meta['execution_commit'] == '27f5d61259995781fcdfd26873800cefa3af3ef0'
            and meta['computation_complete'] is True and meta['error_message'] == '', 'Wrong completed producer')
    require(all(meta[k] is False for k in ('production_recovery_allowed', 'source_physical_model_changed',
                'source_op_edited', 'final_checkpoint_saved', 'anonymous_indices_edited'))
            and meta['controller_representation_changed'] is True, 'Wrong model or recovery scope')
    require(meta['seed_source'] == 'advanced_differential_targets'
            and meta['seed_target_comparison'] == 'initial_sample_before_advance'
            and meta['seed_trajectory_is_diagnostic_only'] is True
            and meta['seed_initial_time_s'] == 2000 and meta['seed_snapshot_time_s'] == 2000.001
            and meta['start_time_s'] == 2000.001 and meta['stop_time_s'] == 2000.002
            and meta['seed_simscape_use_operating_points'] == meta['resume_simscape_use_operating_points'] == 'on',
            'Seed duration, window or initialization config changed')
    require(meta['seed_target_pass'] is True and len(meta['seed_matches']) == 196
            and len({r['path'] for r in meta['seed_matches']}) == 196, 'Incomplete seed targets')
    reference_root = base / 'c200_two_step_snapshot_20260908'
    reference_metadata = reference_root / 'source_restore_audit.json'
    validate_source(json.loads(reference_metadata.read_text(encoding='utf-8-sig')), sha256(reference_metadata))
    reference = observed(reference_root)
    paths.extend((reference_metadata, reference_root / 'restored_step_signals.mat',
                  reference_root / 'registered_states.mat'))
    with h5py.File(root / 'seed_native.mat') as handle:
        seed_native = {}
        for ref in handle['seed_native'][:].flat:
            row = handle[ref]
            key = text_field(row['block_path']) + '/' + text_field(row['state_name'])
            require(key not in seed_native, 'Duplicate native seed identity')
            seed_native[key] = (text_field(row['unit']), row['time_s'][:].reshape(-1), row['values'][:])
    require(len(seed_native) == 1240, 'Incomplete seed native inventory')
    for target in meta['seed_matches']:
        key = 'heatdrive_ecc_coupled_se21/' + target['path']
        unit, times, values = seed_native[key]
        reference_unit, _, reference_values = reference['native/' + key]
        require(unit == target['unit'] == reference_unit and np.array_equal(times, [2000, 2000.001])
                and target['actual'] == float(values[..., 0].item())
                and target['expected'] == float(reference_values[..., 1].item()), 'Seed target origin changed')
        calculated = compare([target['actual']], [target['expected']])
        require(calculated['pass_endpoint_match'] and target['pass'] is True, 'Seed initial state failed')
    source = base / 'c200_source_compatibility_20260907/archived_source_probe_v4/DO_NOT_RESUME_FOR_PRODUCTION.mat'
    require(sha256(source) == meta['source_snapshot_sha256'] ==
            '8ACBED525F7F45170EF308B5F6BCB8E008AAEB87A4A90900982052786273E321', 'C200 donor snapshot changed')
    source_public = base / 'full_op_roundtrip_20260908/untouched_input_public_states.mat'
    source_proof = json.loads((source_public.parent / 'full_op_roundtrip.json').read_text(encoding='utf-8-sig'))
    require(source_proof['source_snapshot_sha256'] == meta['source_snapshot_sha256']
            and source_proof['cases'][0]['arm'] == 'untouched'
            and sha256(source_public) == source_proof['cases'][0]['input_sha256'], 'Source public record changed')
    donor = public_rows(source_public, 'observation')
    cases = []
    require([r['arm'] for r in meta['cases']] == ['nonnetwork_snapshot', 'whole_snapshot'], 'Incomplete paired control')
    for case in meta['cases']:
        arm = case['arm']
        count = 73 if arm == 'whole_snapshot' else 72
        require(case['copied_public_groups'] == count and case['whole_solver_groups'] == count - 72,
                'Whole-group copy scope changed')
        raw = root / (arm + '_observations.mat')
        require(sha256(raw) == case['observation_sha256'], 'Output observations changed')
        compared = compare_window(reference, rows(raw), [2000, 2000.001, 2000.002], [2000.001, 2000.002], 1)
        require(len(compared) == 1474, 'Incomplete 1474-group comparison')
        input_path = root / (arm + '_input_public_states.mat')
        copied = public_rows(input_path, 'input_snapshot')
        before = compare_window(donor, copied, [2000.001], [2000.001], 0)
        selected = before if count == 73 else [r for r in before if '/Solver Configuration/' not in r['key']]
        require(len(before) == 73 and len(selected) == count and all(r['exact'][0] for r in selected),
                'Public source copy is not exact')
        cases.append(dict(arm=arm, copied_input_groups_exact=count, **summarize(compared), comparisons=compared))
        paths.extend((raw, input_path))
    paths.extend((source, source_public, source_public.parent / 'full_op_roundtrip.json', metadata_path,
                  root / 'seed_native.mat', root / 'seed_public_states.mat', root / 'control_inputs.mat', root / 'matlab_diary.log'))
    return dict(schema='heatdrive_ecc_advanced_seed_evidence_v1', execution_commit=meta['execution_commit'],
                seed_initial_targets_verified=196, zero_duration_recipient_cross_copy_effect_observed=False,
                advanced_seed_full_public_copy_one_step_pass=cases[1]['all_observations_pass'],
                all_observations_bitwise_equal=cases[1]['exact_initial_groups'] == cases[1]['exact_one_step_groups'] == 1474,
                absolute_tolerance=1e-10, relative_tolerance=1e-11, cases=cases,
                production_recovery_allowed=False, changed_physical_graph_transfer_verified=False,
                full_device_first_law_verified=False, periodic_steady_state_verified=False,
                input_sha256={str(p.relative_to(repo)): sha256(p) for p in paths})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--create', action='store_true')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    root = repo / 'outputs_storage_audit/advanced_seed_public_snapshot_control_20260908'
    path = root / 'independent_advanced_seed_audit.json'
    table = root / 'full_observation_comparison.csv'
    result = compute(repo)
    records = [dict(arm=c['arm'], key=r['key'], sample=i, bitwise_equal=r['exact'][i], **v)
               for c in result['cases'] for r in c['comparisons'] for i, v in enumerate(r['comparisons'])]
    if args.create:
        require(not path.exists() and not table.exists(), 'Do not overwrite evidence')
        path.write_text(json.dumps(result, indent=2, allow_nan=False) + '\n', encoding='utf-8')
        with table.open('w', encoding='utf-8', newline='') as stream:
            writer = csv.DictWriter(stream, fieldnames=list(records[0]))
            writer.writeheader(); writer.writerows(records)
    require(json.loads(path.read_text(encoding='utf-8')) == result, 'Saved independent result changed')
    with table.open(encoding='utf-8', newline='') as stream:
        actual = list(csv.DictReader(stream))
    require(actual == [{k: str(v) for k, v in row.items()} for row in records], 'Full comparison CSV changed')
    print(json.dumps({k: v for k, v in result.items() if k not in ('cases', 'input_sha256')}, indent=2))
    print(json.dumps([{k: v for k, v in c.items() if k != 'comparisons'} for c in result['cases']], indent=2))
    if not result['advanced_seed_full_public_copy_one_step_pass']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
