"""Package a full diagnostic cycle, not a production or Table 4 qualification."""
import argparse
import csv
from datetime import datetime
import json
from pathlib import Path
import subprocess
import sys

from Audit_HeatDriveECC_SegmentedEvidence import sha256


def read(p):
    return json.loads(p.read_text(encoding='utf-8-sig'))


def write(p,r):
    p.write_text(json.dumps(r,indent=2,allow_nan=False)+'\n',encoding='utf-8')


def cache(p):
    return bool(set(p.parts)&{'build_cache','generated_code','slprj'}) or p.suffix in ('.slxc','.mexw64')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--create',action='store_true')
    args=parser.parse_args()
    repo=Path(__file__).resolve().parents[1]
    workspace=repo.parent
    audit=repo/'outputs_storage_audit'
    evidence=audit/'c201_bounded_20260907'
    interrupted=audit/'c201_fullcycle_20260907'
    root=audit/'c201_cycle_release_20260907'
    result=read(evidence/'cycle_diagnostic_v1.json')
    if (not result['complete_cycle_observation'] or result['samples']!=10001 or result['all_mechanism_gates_evaluated']
            or result['ten_new_steady_cycles_verified'] or result['whole_model_first_law_verified']
            or result['production_recovery_allowed'] or result['table4_reproduction_claim']):
        raise ValueError('Cycle scientific scope changed')
    retirement=read(interrupted/'duplicate_retirement_audit.json')
    receipt=read(interrupted/'retirement_receipt.json')
    if receipt['deleted_bytes']!=182430077 or receipt['deleted_files']!=2 or not retirement['retirement_authorized']:
        raise ValueError('Invalid duplicate retirement')
    for row in retirement['rows']:
        old,new=Path(row['old_path']),Path(row['replacement_path'])
        if (old.exists() or not new.resolve().is_relative_to(evidence.resolve())
                or sha256(new)!=row['replacement_sha256'] or row['exact_groups']!=1474):
            raise ValueError('Retirement replacement changed')
    # The previous package's required evidence excludes the generated caches.
    subprocess.run([sys.executable,'-X','utf8',str(repo/'verification/Audit_HeatDriveECC_C201Package.py')],
                   check=True,stdout=subprocess.DEVNULL)
    if args.create:
        if root.exists() or subprocess.check_output(['git','status','--porcelain'],cwd=workspace,text=True).strip():
            raise ValueError('Require clean source and a new package')
        commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=workspace,text=True).strip()
        root.mkdir()
        base=read(audit/'tl_inventory_release_20260906/release.json')
        source_zip=audit/'tl_inventory_release_20260906/source_snapshot.zip'
        if sha256(source_zip)!=base['source_archive_sha256']:
            raise ValueError('Base source changed')
        patch=root/'source_delta.patch'
        subprocess.run(['git','diff','--binary',f'--output={patch}',base['source_commit'],commit],cwd=workspace,check=True)
        subprocess.run(['git','apply','--reverse','--check',str(patch)],cwd=workspace,check=True)
        with (root/'python_tests.log').open('w',encoding='utf-8') as log:
            subprocess.run([sys.executable,'-m','unittest','discover','-s',str(repo/'verification'),'-p','test_*.py','-v'],
                           stdout=log,stderr=subprocess.STDOUT,check=True)
        for i in range(1,4):
            folder=evidence/f'nominal_s{i:02d}'
            target=root/f'recomputed_segment_{i}.json'
            extra=['--prior-root',str(evidence/f'nominal_s{i-1:02d}')] if i>1 else []
            subprocess.run([sys.executable,'-X','utf8',str(repo/'verification/Audit_HeatDriveECC_C201Segments.py'),
                            '--run-root',str(folder),'--output',str(target),*extra],check=True,stdout=subprocess.DEVNULL)
            if sha256(target)!=sha256(folder/'independent_segment_audit.json'):
                raise ValueError('Segment recomputation differs')
        target=root/'recomputed_cycle.json'
        subprocess.run([sys.executable,'-X','utf8',str(repo/'verification/Audit_HeatDriveECC_C201Cycle.py'),
                        '--repo',str(repo),'--output',str(target)],check=True,stdout=subprocess.DEVNULL)
        if sha256(target)!=sha256(evidence/'cycle_diagnostic_v1.json'):
            raise ValueError('Cycle recomputation differs')
        files=[p for p in workspace.rglob('*') if p.is_file()]
        write(root/'workspace_storage_snapshot.json',dict(measured_at=datetime.now().astimezone().isoformat(),
              workspace_bytes=sum(p.stat().st_size for p in files),file_count=len(files),
              new_retained_evidence_bytes=sum(p.stat().st_size for p in evidence.rglob('*') if p.is_file() and not cache(p)),
              deleted_duplicate_bytes=receipt['deleted_bytes'],copied_production_raw_bytes=0,
              git_objects=subprocess.check_output(['git','count-objects','-vH'],cwd=workspace,text=True)))
        authority_path=repo/'verification/c200_mainline_freeze_contract.json'
        authority=read(authority_path)
        protected={authority_path}
        for kind in ('result','checkpoint'):
            p=repo/authority[kind+'_relative_path']
            if sha256(p)!=authority[kind+'_sha256']:
                raise ValueError('Protected C200 changed')
            protected.add(p)
        paths=protected|set(root.iterdir())|{source_zip}
        paths|={p for directory in (evidence,interrupted) for p in directory.rglob('*') if p.is_file() and not cache(p)}
        paths|={audit/n for n in ('c201_fullcycle_stdout_20260907.log','c201_bounded_s01_stdout_20260907.log',
                                 'c201_bounded_s02_stdout_20260907.log','c201_bounded_s03_stdout_20260907.log')}
        paths|={audit/'c201_boundary_release_20260907'/n for n in ('release.json','result_manifest.csv')}
        paths|={workspace/'项目文档/报告/SMA-SE正逆耦合_第三十四阶段C201完整观测与持久化续算审核报告.md'}
        rows=[dict(relative_path=str(p.relative_to(workspace)),bytes=p.stat().st_size,sha256=sha256(p)) for p in sorted(paths)]
        with (root/'result_manifest.csv').open('w',encoding='utf-8',newline='') as f:
            writer=csv.DictWriter(f,fieldnames=['relative_path','bytes','sha256'])
            writer.writeheader()
            writer.writerows(rows)
        write(root/'release.json',dict(schema='heatdrive_ecc_c201_cycle_release_v1',source_commit=commit,
              source_base_commit=base['source_commit'],required_file_count=len(rows),tests_exit_code=0,
              simulation_source_commit='6ce599c',bounded_program_exit_codes=[0,0,0],
              complete_cycle_observation=True,independent_boundaries_exact=True,
              isolated_cache_model_restore_verified=True,parent_package_reaudit_pass=True,
              original_interrupted_exit_code=None,retired_equality_recomputed_at_packaging=False,
              all_mechanism_gates_evaluated=False,ten_new_steady_cycles_verified=False,
              whole_model_first_law_verified=False,production_recovery_allowed=False,table4_reproduction_claim=False))
    release=read(root/'release.json')
    if (not release['complete_cycle_observation'] or not release['independent_boundaries_exact']
            or release['all_mechanism_gates_evaluated'] or release['ten_new_steady_cycles_verified']
            or release['whole_model_first_law_verified'] or release['production_recovery_allowed']
            or release['table4_reproduction_claim'] or release['tests_exit_code']!=0):
        raise ValueError('Release overclaims its scientific status')
    with (root/'result_manifest.csv').open(encoding='utf-8',newline='') as f:
        rows=list(csv.DictReader(f))
    if len(rows)!=release['required_file_count'] or len({r['relative_path'] for r in rows})!=len(rows):
        raise ValueError('Incomplete manifest')
    for row in rows:
        p=(workspace/row['relative_path']).resolve()
        if not p.is_relative_to(workspace) or p.stat().st_size!=int(row['bytes']) or sha256(p)!=row['sha256']:
            raise ValueError('Changed required evidence: '+str(p))
    print(json.dumps(dict(package_integrity_pass=True,required_files=len(rows),source_commit=release['source_commit'],
                          complete_cycle_observation=True,production_recovery_allowed=False,
                          whole_model_first_law_verified=False,table4_reproduction_claim=False),indent=2))


if __name__=='__main__':
    main()
