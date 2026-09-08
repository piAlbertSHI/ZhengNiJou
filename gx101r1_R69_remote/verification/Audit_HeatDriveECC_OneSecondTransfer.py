"""Reject off-grid or divergent transfers; retain index-only diagnostics separately."""
import argparse
import csv
import json
from pathlib import Path
import subprocess
import sys

import numpy as np

from Audit_HeatDriveECC_AdvancedSeedControl import public_rows
from Audit_HeatDriveECC_C200RestoredSignals import compare
from Audit_HeatDriveECC_OPAPIIsolation import require
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_TargetInitialization import rows


def compare_trace(reference, candidate):
    unit, time, value = reference; other_unit, other_time, other = candidate
    require(unit == other_unit and value.shape == other.shape and value.shape[-1] == len(time)
            and other.shape[-1] == len(other_time) and len(time) == len(other_time)
            and len(time) > 1 and np.isfinite(time).all() and np.isfinite(other_time).all()
            and np.all(np.diff(time) > 0) and np.all(np.diff(other_time) > 0), 'Invalid trace identity or shape')
    diagnostics = compare(value, other)
    mismatched = np.flatnonzero(time != other_time)
    common, left, right = np.intersect1d(time, other_time, assume_unique=True, return_indices=True)
    require(len(common) > 0, 'No exact common timestamps')
    matched = compare(value[..., left], other[..., right])
    errors = abs(value[..., left] - other[..., right])
    bound = 1e-10 + 1e-11 * np.maximum(abs(value[..., left]), abs(other[..., right]))
    bad = np.flatnonzero(np.any((errors > bound).reshape(-1, len(common)), axis=0))
    return dict(unit=unit, sample_count=len(time), exact_grid_pass=not len(mismatched),
                mismatched_timestamps=len(mismatched), max_time_delta_s=float(np.max(abs(time-other_time))),
                first_grid_mismatch_reference_s=float(time[mismatched[0]]) if len(mismatched) else None,
                first_grid_mismatch_candidate_s=float(other_time[mismatched[0]]) if len(mismatched) else None,
                common_timestamp_count=len(common), common_timestamp_values_pass=matched['pass_endpoint_match'],
                common_max_scaled_error=matched['max_scaled_error'], common_max_abs_error=matched['max_abs_error'],
                first_common_value_failure_s=float(common[bad[0]]) if len(bad) else None,
                index_only_diagnostic_values_pass=diagnostics['pass_endpoint_match'],
                index_only_diagnostic_max_scaled_error=diagnostics['max_scaled_error'],
                index_only_diagnostic_max_abs_error=diagnostics['max_abs_error'],
                exact_all_values=bool(np.array_equal(value, other)),
                full_transfer_pass=not len(mismatched) and matched['pass_endpoint_match'])


def compute(repo):
    base = repo / 'outputs_storage_audit'; root = base / 'one_second_public_transfer_20260908'
    execution_path = root / 'one_second_execution.json'; execution = json.loads(execution_path.read_text(encoding='utf-8-sig'))
    commit = 'e6fa63fa88c2350fd48747f727d0706a2d3b5af3'
    require(execution['schema'] == 'heatdrive_ecc_one_second_transfer_execution_v1'
            and execution['execution_commit'] == commit and execution['computation_complete'] is True
            and execution['error_message'] == '' and execution['start_time_s'] == 2000.001
            and execution['stop_time_s'] == 2001.001, 'Wrong execution identity or window')
    require(all(execution[k] is False for k in ('production_recovery_allowed', 'final_checkpoint_saved',
                'command_horizon_extended')) and execution['boundary_sample_hold_diagnostic'] is True,
            'Wrong execution scope')
    paths = [execution_path]; observations = []; inputs = []; prefixes = []
    variants = [('reference', 'full_op_roundtrip.json', 'untouched', 'observation',
                 'full_op_roundtrip_20260908/untouched_observations.mat'),
                ('candidate', 'public_snapshot_control.json', 'whole_snapshot', 'input_snapshot',
                 'advanced_seed_public_snapshot_control_20260908/whole_snapshot_observations.mat')]
    for role, name, arm, public_name, old_name in variants:
        folder = root / role; meta_path = folder / name; meta = json.loads(meta_path.read_text(encoding='utf-8-sig'))
        require(meta['execution_commit'] == commit and meta['computation_complete'] is True and meta['error_message'] == ''
                and meta['production_recovery_allowed'] is False and meta['source_op_edited'] is False
                and meta['final_checkpoint_saved'] is False and meta['anonymous_indices_edited'] is False
                and meta['command_horizon_extended'] is False and meta['boundary_sample_hold_diagnostic'] is True
                and meta['start_time_s'] == 2000.001 and meta['stop_time_s'] == 2001.001
                and len(meta['cases']) == 1 and meta['cases'][0]['arm'] == arm, 'Producer scope changed')
        if role == 'reference':
            require(meta['physical_options_changed'] is False and meta['controller_representation_changed'] is False
                    and meta['window_mode'] == 'one_second_reference', 'Reference model changed')
        else:
            require(meta['source_physical_model_changed'] is False and meta['controller_representation_changed'] is True
                    and meta['window_mode'] == 'one_second_complete_only'
                    and meta['seed_source'] == 'advanced_differential_targets' and meta['seed_target_pass'] is True
                    and len(meta['seed_matches']) == 196 and all(r['pass'] is True for r in meta['seed_matches'])
                    and meta['cases'][0]['copied_public_groups'] == 73 and meta['cases'][0]['whole_solver_groups'] == 1,
                    'Advanced seed or copied group coverage changed')
        require(meta['source_snapshot_sha256'] == '8ACBED525F7F45170EF308B5F6BCB8E008AAEB87A4A90900982052786273E321',
                'Wrong donor snapshot identity')
        raw = folder / (arm + '_observations.mat'); input_path = folder / (arm + '_input_public_states.mat')
        require(sha256(raw) == meta['cases'][0]['observation_sha256'], 'Raw observations changed')
        actual = rows(raw); old_path = base / old_name; previous = rows(old_path)
        require(len(actual) == 1474 and set(actual) == set(previous), 'Incomplete observation coverage')
        require(all(v[1].shape == (1001,) and v[2].shape[-1] == 1001
                    and v[1][0] == 2000.001 and v[1][-1] == 2001.001 for v in actual.values()), 'Wrong observation window')
        prefix = all(actual[k][0] == previous[k][0] and np.array_equal(actual[k][1][:2], previous[k][1])
                     and np.array_equal(actual[k][2][..., :2], previous[k][2]) for k in actual)
        require(prefix, 'Previously frozen one-step prefix changed')
        observations.append(actual); prefixes.append(prefix); inputs.append(public_rows(input_path, public_name))
        paths.extend((meta_path, raw, input_path, old_path, folder / 'control_inputs.mat', folder / 'matlab_diary.log'))
    require(len(inputs[0]) == 73 and set(inputs[0]) == set(inputs[1]) and all(
        inputs[0][k][0] == inputs[1][k][0] and np.array_equal(inputs[0][k][1], inputs[1][k][1])
        and np.array_equal(inputs[0][k][2], inputs[1][k][2]) for k in inputs[0]), 'Full donor input copy changed')
    source = base / 'c200_source_compatibility_20260907/archived_source_probe_v4/DO_NOT_RESUME_FOR_PRODUCTION.mat'
    require(sha256(source) == '8ACBED525F7F45170EF308B5F6BCB8E008AAEB87A4A90900982052786273E321', 'Donor file changed')
    paths.append(source)
    comparisons = [dict(key=k, **compare_trace(observations[0][k], observations[1][k])) for k in observations[0]]
    signals = [r for r in comparisons if r['key'].startswith('signal/')]
    require(len(signals) == 161, 'Incomplete signal evidence')
    return dict(schema='heatdrive_ecc_one_second_transfer_audit_v1', execution_commit=commit,
                group_count=1474, sample_count_per_group=1001, imported_public_groups_exact=73,
                reference_and_candidate_one_step_prefixes_exact=all(prefixes),
                time_grid_failed_groups=sum(not r['exact_grid_pass'] for r in comparisons),
                exact_common_timestamp_value_failed_groups=sum(not r['common_timestamp_values_pass'] for r in comparisons),
                index_only_diagnostic_value_failed_groups=sum(not r['index_only_diagnostic_values_pass'] for r in comparisons),
                signal_time_grids_exact=all(r['exact_grid_pass'] for r in signals),
                signal_value_failed_groups=sum(not r['common_timestamp_values_pass'] for r in signals),
                earliest_signal_value_failure_s=min((r['first_common_value_failure_s'] for r in signals
                    if r['first_common_value_failure_s'] is not None), default=None),
                max_time_grid_delta_s=max(r['max_time_delta_s'] for r in comparisons),
                whole_window_transfer_pass=all(r['full_transfer_pass'] for r in comparisons),
                interpolation_used=False, tolerances_relaxed=False, production_recovery_allowed=False,
                full_device_first_law_verified=False, periodic_steady_state_verified=False,
                comparisons=comparisons, input_sha256={str(p.relative_to(repo)):sha256(p) for p in paths})


def seal_and_verify(repo, root, result, seal):
    workspace = repo.parent; manifest_path = root / 'rejected_evidence_manifest.json'
    if seal:
        require(not manifest_path.exists() and not subprocess.check_output(['git', 'status', '--porcelain'],
                cwd=workspace, text=True).strip(), 'Require fresh manifest and committed source')
        source_commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=workspace, text=True).strip()
        baseline = repo / 'outputs_storage_audit/tl_inventory_release_20260906/source_snapshot.zip'
        require(sha256(baseline) == 'CC2F0010CD4386990E7A50519445ED1F98BE95A1CAFFF943559B2706B06DA39F',
                'Source baseline changed')
        patch = root / 'source_delta.patch'; require(not patch.exists(), 'Do not overwrite source delta')
        base_commit = '3f1925866cc68f357d71dc413590d049c0f6cc96'
        subprocess.run(['git', 'diff', '--binary', f'--output={patch}', base_commit, source_commit], cwd=workspace, check=True)
        subprocess.run(['git', 'apply', '--reverse', '--check', str(patch)], cwd=workspace, check=True)
        with (root / 'python_tests.log').open('w', encoding='utf-8') as stream:
            subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', str(repo / 'verification'),
                            '-p', 'test_*.py', '-v'], check=True, stdout=stream, stderr=subprocess.STDOUT)
        paths = {repo / p for p in result['input_sha256']}
        paths.update((root / 'independent_one_second_audit.json', root / 'comparison_by_group.csv',
                      root / 'python_tests.log', patch, baseline,
                      root / 'candidate/seed_native.mat', root / 'candidate/seed_public_states.mat',
                      workspace / '项目文档/研究笔记/2026-09-08_一秒公开状态迁移拒绝与偏离定位.md'))
        contract_path = repo / 'verification/c200_mainline_freeze_contract.json'
        contract = json.loads(contract_path.read_text(encoding='utf-8-sig')); paths.add(contract_path)
        for name, digest in (('result_relative_path', 'result_sha256'), ('checkpoint_relative_path', 'checkpoint_sha256')):
            path = repo / contract[name]; require(sha256(path) == contract[digest], 'C200 authority changed'); paths.add(path)
        manifest = dict(source_commit=source_commit, source_base_commit=base_commit,
                        production_recovery_allowed=False, scientific_status='rejected_diagnostic_only',
                        files=[dict(path=str(p.relative_to(workspace)), bytes=p.stat().st_size,
                                    sha256=sha256(p)) for p in sorted(paths)])
        manifest_path.write_text(json.dumps(manifest, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
        require(manifest['production_recovery_allowed'] is False
                and manifest['scientific_status'] == 'rejected_diagnostic_only'
                and len({r['path'] for r in manifest['files']}) == len(manifest['files']), 'Wrong evidence scope')
        for item in manifest['files']:
            path = (workspace / item['path']).resolve()
            require(path.is_relative_to(workspace) and path.stat().st_size == item['bytes']
                    and sha256(path) == item['sha256'], 'Evidence changed: ' + str(path))
        print(json.dumps(dict(rejected_package_integrity_pass=True, required_files=len(manifest['files']),
                              scientific_status=manifest['scientific_status'])))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--create', action='store_true'); mode.add_argument('--seal', action='store_true')
    args = parser.parse_args(); repo = Path(__file__).resolve().parents[1]
    root = repo / 'outputs_storage_audit/one_second_public_transfer_20260908'
    result = compute(repo); path = root / 'independent_one_second_audit.json'; table = root / 'comparison_by_group.csv'
    if args.create:
        require(not path.exists() and not table.exists(), 'Do not overwrite evidence')
        path.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
        with table.open('w', encoding='utf-8', newline='') as stream:
            writer = csv.DictWriter(stream, fieldnames=list(result['comparisons'][0]))
            writer.writeheader(); writer.writerows(result['comparisons'])
    require(json.loads(path.read_text(encoding='utf-8')) == result, 'Saved audit changed')
    with table.open(encoding='utf-8', newline='') as stream:
        records = list(csv.DictReader(stream))
    require(records == [{k: '' if v is None else str(v) for k,v in r.items()} for r in result['comparisons']],
            'CSV evidence changed')
    seal_and_verify(repo, root, result, args.seal)
    print(json.dumps({k:v for k,v in result.items() if k not in ('comparisons','input_sha256')}, indent=2))
    if not result['whole_window_transfer_pass']: raise SystemExit(1)


if __name__ == '__main__': main()
