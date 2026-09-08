"""Independently check isolated OP edits without qualifying C200 migration."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

from Audit_HeatDriveECC_SegmentedEvidence import sha256


COMMITS = {
    'v1': '699731c06ac1df15859652234e0170367ad1f557',
    'v2': 'f426f1c58532d1e5122cb066a44d0b40bbe9506a',
}
ARMS = ('baseline', 'conflicting_simscape_target', 'builtin_memory_edit',
        'whole_solver_group_copy')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def observation(row, times, temperature, memory):
    require(set(row) == {'time_s', 'temperature_K', 'memory_time_s', 'memory'},
            'Observation coverage changed')
    for name, expected in (('time_s', times), ('memory_time_s', times),
                           ('temperature_K', [temperature] * 2), ('memory', [memory] * 2)):
        actual = row[name]
        require(isinstance(actual, list) and len(actual) == 2
                and all(type(v) in (int, float) for v in actual) and actual == expected,
                'Observation values, types or grid changed: ' + name)


def validate(meta, variant):
    require(meta['schema'] == 'heatdrive_ecc_op_api_isolation_v1'
            and meta['execution_commit'] == COMMITS[variant] and meta['matlab_release'] == '2025b',
            'Producer identity changed')
    require(meta['collection_complete'] is True and meta['error_message'] == '',
            'Incomplete collection')
    require(all(meta[k] is False for k in ('production_model_loaded',
            'production_checkpoint_loaded', 'production_recovery_allowed')), 'Production scope changed')
    observation(meta['low_seed'], [2000, 2000.001], 340, 7.25)
    observation(meta['high_seed'], [2000, 2000.001], 400, 7.25)
    require(len(meta['cases']) == 4 and [r['name'] for r in meta['cases']] == list(ARMS),
            'Missing, duplicate or reordered arms')
    for row in meta['cases']:
        arm = row['name']
        expected_success = arm == 'baseline' or (variant == 'v2' and arm != ARMS[1])
        require(row['computation_complete'] is expected_success, 'Unexpected simulation outcome')
        target = 400 if arm == ARMS[1] or (variant == 'v1' and arm != 'baseline') else 340
        require(row['target_temperature_K'] == target, 'Conflicting target confound changed')
        edited = arm in ARMS[2:]
        require(row['public_assignment_completed'] is edited, 'Assignment evidence changed')
        require(row['requested_memory'] == (8.25 if arm == ARMS[2] else 7.25),
                'Memory request changed')
        before, after = (7.25, 8.25) if arm == ARMS[2] else ((340, 400) if arm == ARMS[3] else ([], []))
        require(row['state_before'] == before and row['state_after'] == after,
                'Public state readback changed')
        if expected_success:
            require(row['error_message'] == '', 'Successful arm contains an error')
            observation(row['observed'], [2000.001, 2000.002],
                        400 if arm == ARMS[3] else 340, 8.25 if arm == ARMS[2] else 7.25)
        else:
            require(isinstance(row['error_message'], str) and bool(row['error_message'])
                    and 'observed' not in row, 'Rejected arm must not contain a trajectory')


def compute(repo):
    base = repo / 'outputs_storage_audit'
    paths = []
    for variant, suffix in (('v1', ''), ('v2', '_v2')):
        root = base / ('operating_point_api_isolation_20260908' + suffix)
        path = root / 'operating_point_api_isolation.json'
        validate(json.loads(path.read_text(encoding='utf-8-sig')), variant)
        paths.extend((path, root / 'matlab_diary.log'))
    return dict(schema='heatdrive_ecc_op_api_independent_audit_v1',
                matlab_release='2025b', isolated_evidence_pass=True,
                baseline_temperature_K=340, edited_memory=8.25, copied_solver_temperature_K=400,
                target_conflict_rejected_without_trajectory=True,
                first_variant_state_edit_arms_confounded=True,
                generic_simscape_state_edit_qualified=False,
                whole_model_migration_verified=False, production_recovery_allowed=False,
                full_device_first_law_verified=False,
                input_sha256={str(p.relative_to(repo)): sha256(p) for p in paths})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seal', action='store_true')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    workspace = repo.parent
    root = repo / 'outputs_storage_audit/operating_point_api_isolation_20260908_v2'
    result = compute(repo)
    evidence = root / 'independent_api_audit.json'
    manifest_path = root / 'supplement_manifest.json'
    if args.seal:
        require(not evidence.exists() and not manifest_path.exists(), 'Do not overwrite evidence')
        require(not subprocess.check_output(['git', 'status', '--porcelain'], cwd=workspace,
                                           text=True).strip(), 'Commit source before sealing')
        commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=workspace, text=True).strip()
        source_archive = repo / 'outputs_storage_audit/tl_inventory_release_20260906/source_snapshot.zip'
        require(sha256(source_archive) == 'CC2F0010CD4386990E7A50519445ED1F98BE95A1CAFFF943559B2706B06DA39F',
                'Frozen source archive changed')
        with (root / 'python_tests.log').open('w', encoding='utf-8') as log:
            subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', str(repo / 'verification'),
                            '-p', 'test_*.py', '-v'], check=True, stdout=log, stderr=subprocess.STDOUT)
        evidence.write_text(json.dumps(result, indent=2, allow_nan=False) + '\n', encoding='utf-8')
        base_commit = '3f1925866cc68f357d71dc413590d049c0f6cc96'
        patch = root / 'source_delta.patch'
        require(not patch.exists(), 'Do not overwrite source patch')
        subprocess.run(['git', 'diff', '--binary', f'--output={patch}', base_commit, commit],
                       cwd=workspace, check=True)
        subprocess.run(['git', 'apply', '--reverse', '--check', str(patch)], cwd=workspace, check=True)
        files = [repo / p for p in result['input_sha256']]
        files.extend((evidence, patch, source_archive, root / 'python_tests.log',
                      workspace / '项目文档/研究笔记/2026-09-08_OP接口隔离试验与迁移边界.md'))
        manifest = dict(source_commit=commit, source_base_commit=base_commit,
                        production_recovery_allowed=False,
                        files=[dict(path=str(p.relative_to(workspace)), bytes=p.stat().st_size,
                                    sha256=sha256(p)) for p in files])
        manifest_path.write_text(json.dumps(manifest, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    require(json.loads(evidence.read_text(encoding='utf-8')) == result, 'Independent audit changed')
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    require(manifest['production_recovery_allowed'] is False and len(manifest['files']) == 9
            and len({r['path'] for r in manifest['files']}) == 9, 'Supplement scope or coverage changed')
    for item in manifest['files']:
        path = (workspace / item['path']).resolve()
        require(path.is_relative_to(workspace) and path.stat().st_size == item['bytes']
                and sha256(path) == item['sha256'], 'Supplement file changed: ' + str(path))
    print(json.dumps(dict(package_integrity_pass=True, required_files=9,
                          **{k: v for k, v in result.items() if k != 'input_sha256'}), indent=2))


if __name__ == '__main__':
    main()
