"""Verify target discovery/candidate provenance without claiming model migration."""
import argparse
import csv
from datetime import datetime
import json
from pathlib import Path
import subprocess
import sys

from Audit_HeatDriveECC_C201CyclePackage import cache, read, write
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_StateTargetMapping import compute


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--create',action='store_true')
    args=parser.parse_args()
    repo=Path(__file__).resolve().parents[1]; workspace=repo.parent
    audit=repo/'outputs_storage_audit'
    evidence=audit/'state_target_catalog_20260908'
    root=audit/'state_target_release_20260908'
    mapping=read(evidence/'c200_target_mapping.json')
    if compute(repo)!=mapping:
        raise ValueError('Independent target mapping recomputation changed')
    candidate=read(evidence/'candidate/target_candidate_audit.json')
    if (not candidate['serialization_pass'] or candidate['target_count']!=125
            or candidate['high_priority_count']!=121 or candidate['low_priority_count']!=4
            or any(candidate[k] for k in ('contains_private_data','model_initialized','simulation_run',
                                         'state_preservation_verified','production_recovery_allowed'))
            or candidate['mapping_sha256']!=sha256(evidence/'c200_target_mapping.json')
            or candidate['candidate_sha256']!=sha256(evidence/'candidate/DO_NOT_RESUME_TARGET_CANDIDATE.mat')):
        raise ValueError('Candidate serialization evidence changed')
    subprocess.run([sys.executable,'-X','utf8',str(repo/'verification/Audit_HeatDriveECC_C201FullBoundaryPackage.py')],
                   check=True,stdout=subprocess.DEVNULL)
    if args.create:
        if root.exists() or subprocess.check_output(['git','status','--porcelain'],cwd=workspace,text=True).strip():
            raise ValueError('Require fresh package and clean committed source')
        root.mkdir()
        commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=workspace,text=True).strip()
        base=read(audit/'tl_inventory_release_20260906/release.json')
        source_zip=audit/'tl_inventory_release_20260906/source_snapshot.zip'
        if sha256(source_zip)!=base['source_archive_sha256']:
            raise ValueError('Source baseline changed')
        patch=root/'source_delta.patch'
        subprocess.run(['git','diff','--binary',f'--output={patch}',base['source_commit'],commit],cwd=workspace,check=True)
        subprocess.run(['git','apply','--reverse','--check',str(patch)],cwd=workspace,check=True)
        with (root/'python_tests.log').open('w',encoding='utf-8') as log:
            subprocess.run([sys.executable,'-m','unittest','discover','-s',str(repo/'verification'),'-p','test_*.py','-v'],
                           check=True,stdout=log,stderr=subprocess.STDOUT)
        files=[p for p in workspace.rglob('*') if p.is_file()]
        write(root/'storage_snapshot.json',dict(measured_at=datetime.now().astimezone().isoformat(),
            workspace_bytes=sum(p.stat().st_size for p in files),file_count=len(files),
            target_evidence_bytes=sum(p.stat().st_size for p in evidence.rglob('*') if p.is_file()),
            copied_production_raw_bytes=0,deleted_bytes=0,
            git_objects=subprocess.check_output(['git','count-objects','-vH'],cwd=workspace,text=True)))
        paths={p for d in (evidence,root) for p in d.rglob('*') if p.is_file() and not cache(p)}
        paths.add(source_zip)
        paths.update(audit/'c201_full_boundary_release_20260908'/n for n in ('release.json','result_manifest.csv'))
        paths.update(audit/n for n in ('cleanup_candidates_20260908_044205.csv','cleanup_summary_20260908_044205.txt'))
        paths.add(workspace/'项目文档/报告/SMA-SE正逆耦合_第三十七阶段状态目标映射审核报告.md')
        rows=[dict(relative_path=str(p.relative_to(workspace)),bytes=p.stat().st_size,sha256=sha256(p)) for p in sorted(paths)]
        with (root/'result_manifest.csv').open('w',encoding='utf-8',newline='') as f:
            writer=csv.DictWriter(f,fieldnames=['relative_path','bytes','sha256']);writer.writeheader();writer.writerows(rows)
        write(root/'release.json',dict(schema='heatdrive_ecc_state_target_release_v1',source_commit=commit,
            source_base_commit=base['source_commit'],required_file_count=len(rows),tests_exit_code=0,
            independent_mapping_recomputation_pass=True,public_target_serialization_pass=True,
            model_initialization_executed=False,state_migration_verified=False,production_recovery_allowed=False))
    release=read(root/'release.json')
    if (release['tests_exit_code']!=0 or not release['independent_mapping_recomputation_pass']
            or not release['public_target_serialization_pass'] or any(release[k] for k in (
                'model_initialization_executed','state_migration_verified','production_recovery_allowed'))):
        raise ValueError('Release scope changed')
    with (root/'result_manifest.csv').open(encoding='utf-8',newline='') as f:
        rows=list(csv.DictReader(f))
    if len(rows)!=release['required_file_count'] or len({r['relative_path'] for r in rows})!=len(rows):
        raise ValueError('Incomplete manifest')
    for row in rows:
        path=(workspace/row['relative_path']).resolve()
        if not path.is_relative_to(workspace) or path.stat().st_size!=int(row['bytes']) or sha256(path)!=row['sha256']:
            raise ValueError('Evidence changed: '+str(path))
    print(json.dumps(dict(package_integrity_pass=True,required_file_count=len(rows),
        source_commit=release['source_commit'],target_serialization_pass=True,
        state_migration_verified=False,production_recovery_allowed=False),indent=2))


if __name__=='__main__':
    main()
