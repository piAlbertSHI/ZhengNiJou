"""Seal and verify bounded advanced-seed evidence with frozen C200 hashes."""
import argparse
import csv
from datetime import datetime
import json
from pathlib import Path
import subprocess
import sys

from Audit_HeatDriveECC_AdvancedSeedControl import compute
from Audit_HeatDriveECC_C201CyclePackage import read, write
from Audit_HeatDriveECC_OPAPIIsolation import require
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--create', action='store_true')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]; workspace = repo.parent
    base = repo / 'outputs_storage_audit'
    root = base / 'advanced_seed_release_20260908'
    experiment = base / 'advanced_seed_public_snapshot_control_20260908'
    result = compute(repo)
    require(read(experiment / 'independent_advanced_seed_audit.json') == result, 'Independent result changed')
    subprocess.run([sys.executable, '-X', 'utf8', str(repo / 'verification/Audit_HeatDriveECC_AdvancedSeedControl.py')],
                   check=True, stdout=subprocess.DEVNULL)
    subprocess.run([sys.executable, '-X', 'utf8', str(repo / 'verification/Audit_HeatDriveECC_OPAPIIsolation.py')],
                   check=True, stdout=subprocess.DEVNULL)
    summary = {k: v for k, v in result.items() if k not in ('cases', 'input_sha256')}
    summary['cases'] = [{k: v for k, v in c.items() if k != 'comparisons'} for c in result['cases']]
    if args.create:
        require(not root.exists() and not subprocess.check_output(['git', 'status', '--porcelain'],
                cwd=workspace, text=True).strip(), 'Require fresh package and committed source')
        root.mkdir()
        commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=workspace, text=True).strip()
        source_archive = base / 'tl_inventory_release_20260906/source_snapshot.zip'
        require(sha256(source_archive) == 'CC2F0010CD4386990E7A50519445ED1F98BE95A1CAFFF943559B2706B06DA39F',
                'Frozen source archive changed')
        base_commit = '3f1925866cc68f357d71dc413590d049c0f6cc96'
        patch = root / 'source_delta.patch'
        subprocess.run(['git', 'diff', '--binary', f'--output={patch}', base_commit, commit], cwd=workspace, check=True)
        subprocess.run(['git', 'apply', '--reverse', '--check', str(patch)], cwd=workspace, check=True)
        with (root / 'python_tests.log').open('w', encoding='utf-8') as log:
            subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', str(repo / 'verification'),
                            '-p', 'test_*.py', '-v'], check=True, stdout=log, stderr=subprocess.STDOUT)
        write(root / 'evidence_summary.json', summary)
        files = [p for p in workspace.rglob('*') if p.is_file()]
        size = sum(p.stat().st_size for p in files)
        write(root / 'storage_snapshot.json', dict(measured_at=datetime.now().astimezone().isoformat(),
                workspace_bytes=size, workspace_GiB=size / 2**30, file_count=len(files),
                production_raw_copied_bytes=0, files_deleted_this_package=0,
                git_objects=subprocess.check_output(['git', 'count-objects', '-vH'], cwd=workspace, text=True)))
        paths = {repo / p for p in result['input_sha256']}
        paths.update(root.iterdir())
        paths.update((source_archive, experiment / 'independent_advanced_seed_audit.json',
                      experiment / 'full_observation_comparison.csv',
                      base / 'operating_point_api_isolation_20260908_v2/supplement_manifest.json',
                      workspace / '项目文档/报告/SMA-SE正逆耦合_第四十三阶段非零时长种子完整公开状态审核报告.md'))
        contract_path = repo / 'verification/c200_mainline_freeze_contract.json'
        contract = read(contract_path); paths.add(contract_path)
        for key, digest in (('result_relative_path', 'result_sha256'), ('checkpoint_relative_path', 'checkpoint_sha256')):
            target = repo / contract[key]
            require(sha256(target) == contract[digest], 'C200 authority changed')
            paths.add(target)
        manifest = [dict(relative_path=str(p.relative_to(workspace)), bytes=p.stat().st_size, sha256=sha256(p))
                    for p in sorted(paths)]
        with (root / 'result_manifest.csv').open('w', encoding='utf-8', newline='') as stream:
            writer = csv.DictWriter(stream, fieldnames=['relative_path', 'bytes', 'sha256'])
            writer.writeheader(); writer.writerows(manifest)
        write(root / 'release.json', dict(source_commit=commit, source_base_commit=base_commit,
                required_files=len(manifest), tests_exit_code=0, production_recovery_allowed=False))
    require(read(root / 'evidence_summary.json') == summary, 'Packaged result changed')
    release = read(root / 'release.json')
    require(release['tests_exit_code'] == 0 and release['production_recovery_allowed'] is False, 'Wrong release scope')
    with (root / 'result_manifest.csv').open(encoding='utf-8', newline='') as stream:
        manifest = list(csv.DictReader(stream))
    require(len(manifest) == release['required_files']
            and len({r['relative_path'] for r in manifest}) == len(manifest), 'Manifest coverage changed')
    for item in manifest:
        target = (workspace / item['relative_path']).resolve()
        require(target.is_relative_to(workspace) and target.stat().st_size == int(item['bytes'])
                and sha256(target) == item['sha256'], 'Evidence changed: ' + str(target))
    print(json.dumps(dict(package_integrity_pass=True, required_files=len(manifest),
                          source_commit=release['source_commit'], **summary), indent=2))


if __name__ == '__main__':
    main()
