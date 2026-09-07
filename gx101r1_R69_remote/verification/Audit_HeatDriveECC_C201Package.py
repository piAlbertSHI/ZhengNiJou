"""Seal C201 boundary diagnostics, including rejected science and cache incident."""
import argparse
import csv
from datetime import datetime
import json
from pathlib import Path
import subprocess
import sys

from Audit_HeatDriveECC_SegmentedEvidence import sha256


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def write(path, value):
    path.write_text(json.dumps(value,indent=2,allow_nan=False)+'\n',encoding='utf-8')


def is_cache(path):
    return 'slprj' in path.parts or path.suffix in ('.slxc','.mexw64')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--create',action='store_true')
    args=parser.parse_args()
    repo=Path(__file__).resolve().parents[1]
    workspace=repo.parent
    audit=repo/'outputs_storage_audit'
    evidence=audit/'c200_horizon_20260907'
    root=audit/'c201_boundary_release_20260907'
    parent=audit/'c200_source_restore_release_20260907'
    rejected=read(evidence/'horizon_audit_v1.json')
    ablation=read(evidence/'boundary_ablation_audit_v1.json')
    if (rejected['audit_pass'] or rejected['failed_initial_comparison_groups']!=767
            or not ablation['audit_pass'] or ablation['failed_initial_comparison_groups']!=0
            or ablation['maximum_initial_difference']!=0 or ablation['production_boundary_shift_authorized']):
        raise ValueError('Diagnostic findings changed')
    for result in (rejected,ablation):
        if (result['inherited_initial_comparison_groups']!=1474 or result['full_cycle_verified']
                or result['whole_model_first_law_verified'] or result['new_model_recovery_allowed']
                or result['table4_reproduction_claim']):
            raise ValueError('Scientific scope changed')
    if args.create:
        if root.exists() or subprocess.check_output(['git','status','--porcelain'],cwd=workspace,text=True).strip():
            raise ValueError('Require a new package and clean source')
        commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=workspace,text=True).strip()
        with (parent/'result_manifest.csv').open(encoding='utf-8',newline='') as f:
            prior=list(csv.DictReader(f))
        changed, core = [], []
        for row in prior:
            p=(workspace/row['relative_path']).resolve()
            if not p.is_relative_to(workspace):
                raise ValueError('Prior manifest escapes workspace')
            actual=sha256(p)
            if actual!=row['sha256'] or p.stat().st_size!=int(row['bytes']):
                if not is_cache(p):
                    raise ValueError('Prior scientific evidence changed: '+str(p))
                changed.append(dict(**row,actual_sha256=actual,actual_bytes=p.stat().st_size))
            if not is_cache(p):
                core.append(p)
        expected_suffixes={
            'slprj/_sfprj/heatdrive_ecc_coupled_se21/amsi_serial.mat',
            'slprj/accel/heatdrive_ecc_coupled_se21/heatdrive_ecc_coupled_se21_instrumentation_settings.mat'}
        if (len(prior)!=87 or len(core)!=71 or len(changed)!=2
                or not all(any(Path(r['relative_path']).as_posix().endswith(s) for s in expected_suffixes) for r in changed)):
            raise ValueError('Unexpected parent cache incident')
        root.mkdir()
        write(root/'parent_cache_incident.json',dict(original_manifest_unedited=True,
              original_package_full_integrity_pass=False,original_file_count=87,unchanged_file_count=85,
              changed_generated_cache_files=changed,noncache_required_count=71,noncache_all_pass=True,
              new_package_excludes_generated_cache=True))
        base=read(audit/'tl_inventory_release_20260906/release.json')
        source_zip=audit/'tl_inventory_release_20260906/source_snapshot.zip'
        if sha256(source_zip)!=base['source_archive_sha256']:
            raise ValueError('Base source archive changed')
        patch=root/'source_delta.patch'
        subprocess.run(['git','diff','--binary',f'--output={patch}',base['source_commit'],commit],cwd=workspace,check=True)
        subprocess.run(['git','apply','--reverse','--check',str(patch)],cwd=workspace,check=True)
        with (root/'python_tests.log').open('w',encoding='utf-8') as log:
            subprocess.run([sys.executable,'-m','unittest','discover','-s',str(repo/'verification'),'-p','test_*.py','-v'],
                           stdout=log,stderr=subprocess.STDOUT,check=True)
        for name,reference,exit_code in [('probe201','horizon_audit_v1.json',1),
                                        ('boundary_hold_diagnostic','boundary_ablation_audit_v1.json',0)]:
            target=root/('recomputed_'+reference)
            with (root/(name+'_audit_stdout.log')).open('w',encoding='utf-8') as log:
                completed=subprocess.run([sys.executable,'-X','utf8',str(repo/'verification/Audit_HeatDriveECC_C201Horizon.py'),
                                          '--repo',str(repo),'--probe',name,'--output',str(target)],stdout=log,stderr=subprocess.STDOUT)
            if completed.returncode!=exit_code or sha256(target)!=sha256(evidence/reference):
                raise ValueError('Independent recomputation differs')
        files=[p for p in workspace.rglob('*') if p.is_file()]
        write(root/'workspace_storage_snapshot.json',dict(measured_at=datetime.now().astimezone().isoformat(),
              workspace_bytes=sum(p.stat().st_size for p in files),file_count=len(files),
              new_evidence_bytes=sum(p.stat().st_size for p in evidence.rglob('*') if p.is_file()),
              copied_production_raw_bytes=0,deleted_bytes_this_stage=0,
              git_objects=subprocess.check_output(['git','count-objects','-vH'],cwd=workspace,text=True)))
        paths=set(core)|set(root.iterdir())|{source_zip,parent/'result_manifest.csv',parent/'release.json'}
        paths|={p for p in evidence.rglob('*') if p.is_file() and not is_cache(p)}
        paths|={audit/n for n in ('c200_horizon_probe_stdout_20260907.log','c200_horizon_ablation_stdout_20260907.log',
                                 'c200_cache_config_smoke_20260907.log','cleanup_candidates_20260907_102047.csv',
                                 'cleanup_summary_20260907_102047.txt')}
        paths|={workspace/'项目文档/报告/SMA-SE正逆耦合_第三十三阶段C201边界事件与恢复连续性审核报告.md'}
        rows=[dict(relative_path=str(p.relative_to(workspace)),bytes=p.stat().st_size,sha256=sha256(p)) for p in sorted(paths)]
        with (root/'result_manifest.csv').open('w',encoding='utf-8',newline='') as f:
            writer=csv.DictWriter(f,fieldnames=['relative_path','bytes','sha256'])
            writer.writeheader()
            writer.writerows(rows)
        write(root/'release.json',dict(schema='heatdrive_ecc_c201_boundary_release_v1',source_commit=commit,
              source_base_commit=base['source_commit'],required_file_count=len(rows),tests_exit_code=0,
              nominal_simulation_source_commit='7268268',ablation_simulation_source_commit='4b43a1d',
              nominal_continuity_pass=False,ablation_initial_continuity_pass=True,
              original_stage32_full_integrity_pass=False,parent_noncache_reaudit_pass=True,
              full_cycle_verified=False,production_boundary_shift_authorized=False,
              whole_model_first_law_verified=False,new_model_recovery_allowed=False,table4_reproduction_claim=False,
              cache_config_smoke_pass=True,isolated_cache_full_model_simulation_verified=False))
    release=read(root/'release.json')
    if (release['nominal_continuity_pass'] or not release['ablation_initial_continuity_pass']
            or release['original_stage32_full_integrity_pass'] or not release['parent_noncache_reaudit_pass']
            or release['full_cycle_verified'] or release['production_boundary_shift_authorized']
            or release['whole_model_first_law_verified'] or release['new_model_recovery_allowed']
            or release['table4_reproduction_claim'] or release['tests_exit_code']!=0):
        raise ValueError('Release scientific boundaries changed')
    with (root/'result_manifest.csv').open(encoding='utf-8',newline='') as f:
        rows=list(csv.DictReader(f))
    if len(rows)!=release['required_file_count'] or len({r['relative_path'] for r in rows})!=len(rows):
        raise ValueError('Incomplete manifest')
    for row in rows:
        p=(workspace/row['relative_path']).resolve()
        if not p.is_relative_to(workspace) or p.stat().st_size!=int(row['bytes']) or sha256(p)!=row['sha256']:
            raise ValueError('Changed package evidence: '+str(p))
    print(json.dumps(dict(package_integrity_pass=True,required_files=len(rows),source_commit=release['source_commit'],
                          nominal_continuity_pass=False,ablation_initial_continuity_pass=True,
                          full_cycle_verified=False,whole_model_first_law_verified=False),indent=2))


if __name__=='__main__':
    main()
