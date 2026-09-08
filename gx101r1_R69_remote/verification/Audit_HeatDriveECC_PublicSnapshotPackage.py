"""Recompute and package rejected snapshot controls without production promotion."""
import argparse
import csv
from datetime import datetime
import json
from pathlib import Path
import subprocess
import sys

from Audit_HeatDriveECC_C201CyclePackage import cache, read, write
from Audit_HeatDriveECC_PublicSnapshotEvidence import compute, observed
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_TargetInitialization import rows


def comparison_rows(repo, evidence):
    base = repo/'outputs_storage_audit'
    reference = observed(base/'c200_two_step_snapshot_20260908')
    records = []
    for case in evidence['cases']:
        actual = rows(base/case['folder']/(case['arm']+'_observations.mat'))
        for group in case['comparisons']:
            key = group['key']
            unit, _, expected = reference[key]
            _, times, values = actual[key]
            for i, result in enumerate(group['comparisons']):
                records.append(dict(case=case['folder']+'/'+case['arm'], group=key,
                    native_unit=unit, time_s=float(times[i]),
                    pass_existing_tolerance=result['pass_endpoint_match'],
                    bitwise_exact=group['exact'][i], max_abs_error=result['max_abs_error'],
                    max_scaled_error=result['max_scaled_error'],
                    reference_values=json.dumps(expected[..., i+1].reshape(-1).tolist()),
                    actual_values=json.dumps(values[..., i].reshape(-1).tolist())))
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--create', action='store_true')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    workspace = repo.parent
    audit = repo/'outputs_storage_audit'
    root = audit/'public_snapshot_release_20260908'
    evidence = compute(repo)
    evidence_path = audit/'public_snapshot_evidence_20260908_v2.json'
    if evidence != read(evidence_path):
        raise ValueError('Independent evidence changed')
    if any(c['full_observation_match'] for c in evidence['cases']):
        raise ValueError('Re-evaluate scientific scope before changing this rejected release')
    records = comparison_rows(repo, evidence)
    if len(records) != 8844:
        raise ValueError('Incomplete three-arm comparison')
    subprocess.run([sys.executable, '-X', 'utf8',
        str(repo/'verification/Audit_HeatDriveECC_DynamicInitializationPackage.py')],
        check=True, stdout=subprocess.DEVNULL)
    names = ('c200_zero_time_snapshot_20260908', 'c200_two_step_snapshot_20260908',
        'public_snapshot_control_20260908', 'public_snapshot_control_20260908_v2',
        'c200_logged_simscape_op_20260908', 'logged_simscape_snapshot_control_20260908')
    folders = [audit/n for n in names]
    if args.create:
        if root.exists() or subprocess.check_output(
                ['git', 'status', '--porcelain'], cwd=workspace, text=True).strip():
            raise ValueError('Require clean source and a fresh package')
        root.mkdir()
        commit = subprocess.check_output(['git','rev-parse','HEAD'],cwd=workspace,text=True).strip()
        base = read(audit/'tl_inventory_release_20260906/release.json')
        archive = audit/'tl_inventory_release_20260906/source_snapshot.zip'
        if sha256(archive) != base['source_archive_sha256']:
            raise ValueError('Source base archive changed')
        patch = root/'source_delta.patch'
        subprocess.run(['git','diff','--binary',f'--output={patch}',base['source_commit'],commit],
                       cwd=workspace,check=True)
        subprocess.run(['git','apply','--reverse','--check',str(patch)],cwd=workspace,check=True)
        with (root/'python_tests.log').open('w',encoding='utf-8') as log:
            subprocess.run([sys.executable,'-m','unittest','discover','-s',str(repo/'verification'),
                            '-p','test_*.py','-v'],check=True,stdout=log,stderr=subprocess.STDOUT)
        with (root/'full_1474_group_comparison.csv').open('w',encoding='utf-8',newline='') as stream:
            writer=csv.DictWriter(stream,fieldnames=list(records[0]))
            writer.writeheader(); writer.writerows(records)
        files=[p for p in workspace.rglob('*') if p.is_file()]
        size=sum(p.stat().st_size for p in files)
        large=sorted(files,key=lambda p:p.stat().st_size,reverse=True)[:15]
        write(root/'storage_snapshot.json',dict(measured_at=datetime.now().astimezone().isoformat(),
            workspace_bytes=size,workspace_GiB=size/2**30,file_count=len(files),
            new_evidence_bytes=sum(p.stat().st_size for folder in folders for p in folder.rglob('*') if p.is_file()),
            production_raw_copied_bytes=0,deleted_bytes=0,
            largest_files=[dict(path=str(p.relative_to(workspace)),bytes=p.stat().st_size) for p in large],
            git_objects=subprocess.check_output(['git','count-objects','-vH'],cwd=workspace,text=True)))
        paths={p for folder in folders+[root] for p in folder.rglob('*') if p.is_file() and not cache(p)}
        paths.update(repo/name for name in evidence['input_sha256'])
        paths.update((archive,evidence_path,audit/'public_snapshot_evidence_20260908.json'))
        paths.update(audit/'dynamic_initialization_release_20260908'/n for n in ('release.json','result_manifest.csv'))
        paths.update(audit/n for n in ('cleanup_candidates_20260908_095837.csv','cleanup_summary_20260908_095837.txt'))
        paths.add(workspace/'项目文档/报告/SMA-SE正逆耦合_第四十一阶段公开快照与存储审核报告.md')
        manifest=[dict(relative_path=str(p.relative_to(workspace)),bytes=p.stat().st_size,
                       sha256=sha256(p)) for p in sorted(paths)]
        with (root/'result_manifest.csv').open('w',encoding='utf-8',newline='') as stream:
            writer=csv.DictWriter(stream,fieldnames=['relative_path','bytes','sha256'])
            writer.writeheader(); writer.writerows(manifest)
        write(root/'release.json',dict(schema='heatdrive_ecc_public_snapshot_release_v1',
            source_commit=commit,source_base_commit=base['source_commit'],required_file_count=len(manifest),
            comparison_rows=8844,tests_exit_code=0,full_scientific_gate_pass=False,
            production_recovery_allowed=False,full_device_first_law_verified=False))
    with (root/'full_1474_group_comparison.csv').open(encoding='utf-8',newline='') as stream:
        if list(csv.DictReader(stream)) != [{k:str(v) for k,v in r.items()} for r in records]:
            raise ValueError('Comparison CSV changed')
    release=read(root/'release.json')
    if (release['full_scientific_gate_pass'] or release['production_recovery_allowed']
            or release['full_device_first_law_verified'] or release['tests_exit_code']!=0
            or release['comparison_rows']!=8844):
        raise ValueError('Scientific scope changed')
    with (root/'result_manifest.csv').open(encoding='utf-8',newline='') as stream:
        manifest=list(csv.DictReader(stream))
    if len(manifest)!=release['required_file_count'] or len({r['relative_path'] for r in manifest})!=len(manifest):
        raise ValueError('Incomplete manifest')
    for item in manifest:
        path=(workspace/item['relative_path']).resolve()
        if (not path.is_relative_to(workspace) or path.stat().st_size!=int(item['bytes'])
                or sha256(path)!=item['sha256']):
            raise ValueError('Evidence changed: '+str(path))
    print(json.dumps(dict(package_integrity_pass=True,required_files=len(manifest),
        comparison_rows=8844,source_commit=release['source_commit'],
        full_scientific_gate_pass=False,production_recovery_allowed=False),indent=2))


if __name__=='__main__':
    main()
