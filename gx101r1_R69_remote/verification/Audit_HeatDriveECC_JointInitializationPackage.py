"""Preserve a rejected initialization route and its successful diagnostic controls."""
import argparse
import csv
from datetime import datetime
from pathlib import Path
import json
import subprocess
import sys

from Audit_HeatDriveECC_C201CyclePackage import cache,read,write
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_TargetInitialization import compute


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--create',action='store_true')
    args=parser.parse_args();repo=Path(__file__).resolve().parents[1];workspace=repo.parent
    audit=repo/'outputs_storage_audit';root=audit/'joint_initialization_release_20260908'
    evidence=audit/'joint_target_controller_seeded_op_20260908'
    result=read(evidence/'independent_initialization_audit.json')
    if compute(repo,evidence)!=result:
        raise ValueError('Independent initialization recomputation changed')
    if (result['all_observations_roundtrip_pass'] or result['production_recovery_allowed']
            or result['initial_target_failures'] or len(result['initial_memory_failures'])!=42
            or result['failed_initial_groups']!=49 or result['failed_one_step_groups']!=197):
        raise ValueError('Rejected scientific outcome changed')
    iso=read(audit/'joint_init_interface_isolation_20260908_v5/joint_initialization_isolation.json')
    cases=iso['cases']
    if (len(cases)!=5 or any(iso[k] for k in ('production_model_loaded','production_checkpoint_loaded','production_recovery_allowed'))
            or any(not cases[i]['computation_complete'] or not cases[i]['temperature_target_pass']
                   or not cases[i]['memory_target_pass'] for i in (0,2,4))
            or any(cases[i]['computation_complete'] or 'absolute zero' not in cases[i]['error_message'] for i in (1,3))):
        raise ValueError('Isolated causal controls changed')
    lag=read(audit/'lag_state_space_equivalence_20260908/lag_equivalence.json')
    if not lag['equivalence_pass'] or lag['state_max_difference']!=0 or lag['output_max_difference']!=0:
        raise ValueError('Canonical lag equivalence changed')
    subprocess.run([sys.executable,'-X','utf8',str(repo/'verification/Audit_HeatDriveECC_StateTargetPackage.py')],
                   check=True,stdout=subprocess.DEVNULL)
    folders=[audit/name for name in (
        'joint_target_initialization_20260908','joint_target_initialization_20260908_v2',
        'joint_target_initialization_20260908_v3','joint_target_seeded_op_20260908',
        'joint_target_controller_seeded_op_20260908','lag_state_space_equivalence_20260908',
        'joint_init_interface_isolation_20260908','joint_init_interface_isolation_20260908_v2',
        'joint_init_interface_isolation_20260908_v3','joint_init_interface_isolation_20260908_v4',
        'joint_init_interface_isolation_20260908_v5')]
    if args.create:
        if root.exists() or subprocess.check_output(['git','status','--porcelain'],cwd=workspace,text=True).strip():
            raise ValueError('Require clean source and fresh package')
        root.mkdir();commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=workspace,text=True).strip()
        base=read(audit/'tl_inventory_release_20260906/release.json')
        source_zip=audit/'tl_inventory_release_20260906/source_snapshot.zip'
        if sha256(source_zip)!=base['source_archive_sha256']:
            raise ValueError('Source base changed')
        patch=root/'source_delta.patch'
        subprocess.run(['git','diff','--binary',f'--output={patch}',base['source_commit'],commit],cwd=workspace,check=True)
        subprocess.run(['git','apply','--reverse','--check',str(patch)],cwd=workspace,check=True)
        with (root/'python_tests.log').open('w',encoding='utf-8') as log:
            subprocess.run([sys.executable,'-m','unittest','discover','-s',str(repo/'verification'),'-p','test_*.py','-v'],
                           check=True,stdout=log,stderr=subprocess.STDOUT)
        files=[p for p in workspace.rglob('*') if p.is_file()]
        write(root/'storage_snapshot.json',dict(measured_at=datetime.now().astimezone().isoformat(),
            workspace_bytes=sum(p.stat().st_size for p in files),file_count=len(files),
            new_evidence_bytes=sum(p.stat().st_size for folder in folders for p in folder.rglob('*') if p.is_file()),
            production_raw_copied_bytes=0,deleted_bytes=0,
            git_objects=subprocess.check_output(['git','count-objects','-vH'],cwd=workspace,text=True)))
        paths={p for folder in folders+[root] for p in folder.rglob('*') if p.is_file() and not cache(p)}
        paths.add(source_zip)
        paths.update(audit/'state_target_release_20260908'/n for n in ('release.json','result_manifest.csv'))
        paths.update(audit/n for n in ('cleanup_candidates_20260908_055841.csv','cleanup_summary_20260908_055841.txt'))
        paths.add(workspace/'项目文档/报告/SMA-SE正逆耦合_第三十八阶段联合初始化诊断报告.md')
        rows=[dict(relative_path=str(p.relative_to(workspace)),bytes=p.stat().st_size,sha256=sha256(p)) for p in sorted(paths)]
        with (root/'result_manifest.csv').open('w',encoding='utf-8',newline='') as f:
            writer=csv.DictWriter(f,fieldnames=['relative_path','bytes','sha256']);writer.writeheader();writer.writerows(rows)
        write(root/'release.json',dict(schema='heatdrive_ecc_joint_initialization_release_v1',source_commit=commit,
            source_base_commit=base['source_commit'],required_file_count=len(rows),tests_exit_code=0,
            independent_recomputation_pass=True,scientific_initialization_gate_pass=False,
            final_probe_program_exit_code=0,scientific_audit_exit_code=1,
            production_recovery_allowed=False,full_device_first_law_verified=False))
    release=read(root/'release.json')
    if (release['tests_exit_code']!=0 or not release['independent_recomputation_pass']
            or release['scientific_initialization_gate_pass'] or release['production_recovery_allowed']
            or release['scientific_audit_exit_code']!=1):
        raise ValueError('Release scope changed')
    with (root/'result_manifest.csv').open(encoding='utf-8',newline='') as f:rows=list(csv.DictReader(f))
    if len(rows)!=release['required_file_count'] or len({r['relative_path'] for r in rows})!=len(rows):
        raise ValueError('Manifest incomplete')
    for row in rows:
        path=(workspace/row['relative_path']).resolve()
        if not path.is_relative_to(workspace) or path.stat().st_size!=int(row['bytes']) or sha256(path)!=row['sha256']:
            raise ValueError('Evidence changed: '+str(path))
    print(json.dumps(dict(package_integrity_pass=True,required_files=len(rows),source_commit=release['source_commit'],
        scientific_initialization_gate_pass=False,production_recovery_allowed=False),indent=2))


if __name__=='__main__':main()
