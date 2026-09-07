"""Recompute and preserve complete-cycle sources while retaining failed closure."""
import argparse
import csv
from datetime import datetime
from pathlib import Path
import json
import subprocess
import sys

from Audit_HeatDriveECC_C201BoundaryCycle import compute
from Audit_HeatDriveECC_C201CyclePackage import cache,read,write
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--create',action='store_true')
    args=parser.parse_args()
    repo=Path(__file__).resolve().parents[1];workspace=repo.parent
    audit=repo/'outputs_storage_audit'
    evidence=audit/'c201_boundary_full_20260907'
    root=audit/'c201_full_boundary_release_20260908'
    result=read(evidence/'full_boundary_audit_v1.json')
    if (not result['complete_cycle_source_observation'] or not result['all_samples_port_sum_match']
            or result['samples']!=10001 or result['source_count']!=49 or result['source_trace_count']!=162
            or result['intervals_omitted']!=0 or len(result['original_trajectory_comparisons'])!=3
            or any(r['exact_groups']!=1474 for r in result['original_trajectory_comparisons'])
            or any(result[k] for k in ('all_mechanism_gates_evaluated','ten_new_steady_cycles_verified',
                                      'full_device_first_law_verified','production_recovery_allowed','table4_reproduction_claim'))):
        raise ValueError('Cycle scope changed')
    for path,digest in result['input_sha256'].items():
        if sha256(Path(path))!=digest:
            raise ValueError('Changed scientific input: '+path)
    subprocess.run([sys.executable,'-X','utf8',str(repo/'verification/Audit_HeatDriveECC_C201BoundaryPackage.py')],
                   check=True,stdout=subprocess.DEVNULL)
    if args.create:
        if root.exists() or subprocess.check_output(['git','status','--porcelain'],cwd=workspace,text=True).strip():
            raise ValueError('Require clean source and fresh package')
        recomputed,_,_,_=compute(repo)
        if recomputed!=result:
            raise ValueError('Full-cycle source recomputation changed')
        root.mkdir()
        write(root/'recomputation.json',dict(recomputed_equal=True,samples=10001,source_count=49,
              full_device_first_law_verified=False,production_recovery_allowed=False))
        commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=workspace,text=True).strip()
        base=read(audit/'tl_inventory_release_20260906/release.json')
        source_zip=audit/'tl_inventory_release_20260906/source_snapshot.zip'
        if sha256(source_zip)!=base['source_archive_sha256']:
            raise ValueError('Base source changed')
        patch=root/'source_delta.patch'
        subprocess.run(['git','diff','--binary',f'--output={patch}',base['source_commit'],commit],cwd=workspace,check=True)
        subprocess.run(['git','apply','--reverse','--check',str(patch)],cwd=workspace,check=True)
        with (root/'python_tests.log').open('w',encoding='utf-8') as log:
            subprocess.run([sys.executable,'-m','unittest','discover','-s',str(repo/'verification'),'-p','test_*.py','-v'],
                           check=True,stdout=log,stderr=subprocess.STDOUT)
        files=[p for p in workspace.rglob('*') if p.is_file()]
        write(root/'storage_snapshot.json',dict(measured_at=datetime.now().astimezone().isoformat(),
              workspace_bytes=sum(p.stat().st_size for p in files),file_count=len(files),
              new_complete_cycle_evidence_bytes=sum(p.stat().st_size for p in evidence.rglob('*') if p.is_file() and not cache(p)),
              copied_production_raw_bytes=0,deleted_bytes=0,
              git_objects=subprocess.check_output(['git','count-objects','-vH'],cwd=workspace,text=True)))
        paths={p for d in (evidence,root) for p in d.rglob('*') if p.is_file() and not cache(p)}
        paths.add(source_zip)
        paths.update(audit/'c201_boundary_source_release_20260907'/n for n in ('release.json','result_manifest.csv'))
        paths.update(audit/n for n in ('c201_boundary_full_s01_stdout_20260907.log',
            'c201_boundary_full_s02_stdout_20260907.log','c201_boundary_full_s02_recovered_stdout_20260908.log',
            'c201_boundary_full_s03_stdout_20260908.log','cleanup_candidates_20260908_041731.csv',
            'cleanup_summary_20260908_041731.txt'))
        paths.add(workspace/'项目文档/报告/SMA-SE正逆耦合_第三十六阶段C201完整源端周期审核报告.md')
        rows=[dict(relative_path=str(p.relative_to(workspace)),bytes=p.stat().st_size,sha256=sha256(p)) for p in sorted(paths)]
        with (root/'result_manifest.csv').open('w',encoding='utf-8',newline='') as f:
            writer=csv.DictWriter(f,fieldnames=['relative_path','bytes','sha256']);writer.writeheader();writer.writerows(rows)
        write(root/'release.json',dict(schema='heatdrive_ecc_c201_full_boundary_release_v1',source_commit=commit,
              source_base_commit=base['source_commit'],required_file_count=len(rows),tests_exit_code=0,
              independent_recomputation_pass=True,simulation_source_commit='2711e7f',completed_program_exit_codes=[0,0,0],
              interrupted_second_attempt_exit_code=None,interrupted_attempt_host_restart_recorded=True,
              complete_cycle_source_observation=True,full_device_first_law_verified=False,
              production_recovery_allowed=False,table4_reproduction_claim=False))
    release=read(root/'release.json')
    if (release['tests_exit_code']!=0 or not release['independent_recomputation_pass']
            or not release['complete_cycle_source_observation']
            or any(release[k] for k in ('full_device_first_law_verified','production_recovery_allowed','table4_reproduction_claim'))):
        raise ValueError('Invalid release scope')
    with (root/'result_manifest.csv').open(encoding='utf-8',newline='') as f:
        rows=list(csv.DictReader(f))
    if len(rows)!=release['required_file_count'] or len({r['relative_path'] for r in rows})!=len(rows):
        raise ValueError('Incomplete manifest')
    for row in rows:
        p=(workspace/row['relative_path']).resolve()
        if not p.is_relative_to(workspace) or p.stat().st_size!=int(row['bytes']) or sha256(p)!=row['sha256']:
            raise ValueError('Changed evidence: '+str(p))
    print(json.dumps(dict(package_integrity_pass=True,required_files=len(rows),source_commit=release['source_commit'],
                          complete_cycle_source_observation=True,full_device_first_law_verified=False,
                          production_recovery_allowed=False,table4_reproduction_claim=False),indent=2))


if __name__=='__main__':
    main()
