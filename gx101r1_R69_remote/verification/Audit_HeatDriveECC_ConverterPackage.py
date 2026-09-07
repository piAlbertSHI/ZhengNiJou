"""Package converter timing controls while preserving all rejected recovery gates."""
import argparse
import csv
from datetime import datetime
import json
from pathlib import Path
import subprocess
import sys

from Audit_HeatDriveECC_C201CyclePackage import cache,read,write
from Audit_HeatDriveECC_ConverterEvidence import compute as scalar
from Audit_HeatDriveECC_ConverterReplay import compute as replay
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--create',action='store_true')
    args=parser.parse_args();repo=Path(__file__).resolve().parents[1];workspace=repo.parent
    audit=repo/'outputs_storage_audit';root=audit/'converter_phase_release_20260908'
    names=('converter_boundary_isolation_20260908','converter_boundary_isolation_20260908_v2',
           'converter_discrete_boundary_isolation_20260908','converter_falling_boundary_isolation_20260908',
           'converter_snapshot_phase_isolation_20260908','c200_converter_history_replay_20260908',
           'c200_converter_history_replay_20260908_v2')
    for name in names[1:5]:
        actual=scalar(audit/name);saved=read(audit/name/'independent_delivery_audit.json')
        if actual!=saved or not saved['isolated_physical_delivery_pass'] or saved['production_recovery_allowed']:
            raise ValueError('Scalar recomputation changed: '+name)
    result=replay(repo)
    if (result!=read(audit/names[-1]/'independent_replay_audit.json')
            or result['strict_replay_gate_pass'] or result['production_recovery_allowed']
            or result['exact_time_count']!=42 or result['exact_heat_count']!=26
            or result['reported_snapshot_previous_input_exact_count']!=42):
        raise ValueError('Rejected replay result changed')
    subprocess.run([sys.executable,'-X','utf8',str(repo/'verification/Audit_HeatDriveECC_JointInitializationPackage.py')],
                   check=True,stdout=subprocess.DEVNULL)
    if args.create:
        if root.exists() or subprocess.check_output(['git','status','--porcelain'],cwd=workspace,text=True).strip():
            raise ValueError('Require clean source and fresh package')
        root.mkdir();commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=workspace,text=True).strip()
        base=read(audit/'tl_inventory_release_20260906/release.json')
        source_zip=audit/'tl_inventory_release_20260906/source_snapshot.zip'
        if sha256(source_zip)!=base['source_archive_sha256']:raise ValueError('Source base changed')
        patch=root/'source_delta.patch'
        subprocess.run(['git','diff','--binary',f'--output={patch}',base['source_commit'],commit],cwd=workspace,check=True)
        subprocess.run(['git','apply','--reverse','--check',str(patch)],cwd=workspace,check=True)
        with (root/'python_tests.log').open('w',encoding='utf-8') as f:
            subprocess.run([sys.executable,'-m','unittest','discover','-s',str(repo/'verification'),'-p','test_*.py','-v'],
                           check=True,stdout=f,stderr=subprocess.STDOUT)
        files=[p for p in workspace.rglob('*') if p.is_file()]
        size=sum(p.stat().st_size for p in files)
        folders=[audit/name for name in names]
        write(root/'storage_snapshot.json',dict(measured_at=datetime.now().astimezone().isoformat(),
            workspace_bytes=size,workspace_GiB=size/2**30,file_count=len(files),
            new_evidence_bytes=sum(p.stat().st_size for folder in folders for p in folder.rglob('*') if p.is_file()),
            production_raw_copied_bytes=0,deleted_bytes=0,
            git_objects=subprocess.check_output(['git','count-objects','-vH'],cwd=workspace,text=True)))
        paths={p for folder in folders+[root] for p in folder.rglob('*') if p.is_file() and not cache(p)}
        paths.add(source_zip)
        paths.add(audit/'c200_converter_input_history_20260908.json')
        paths.update(audit/'joint_initialization_release_20260908'/n for n in ('release.json','result_manifest.csv'))
        paths.update(audit/n for n in ('cleanup_candidates_20260908_062741.csv','cleanup_summary_20260908_062741.txt'))
        paths.add(workspace/'项目文档/报告/SMA-SE正逆耦合_第三十九阶段转换器恢复时序诊断报告.md')
        rows=[dict(relative_path=str(p.relative_to(workspace)),bytes=p.stat().st_size,sha256=sha256(p)) for p in sorted(paths)]
        with (root/'result_manifest.csv').open('w',encoding='utf-8',newline='') as f:
            writer=csv.DictWriter(f,fieldnames=['relative_path','bytes','sha256']);writer.writeheader();writer.writerows(rows)
        write(root/'release.json',dict(schema='heatdrive_ecc_converter_phase_release_v1',source_commit=commit,
            source_base_commit=base['source_commit'],required_file_count=len(rows),tests_exit_code=0,
            independent_recomputation_pass=True,strict_replay_gate_pass=False,
            replay_program_exit_code=1,replay_scientific_audit_exit_code=1,
            production_recovery_allowed=False,whole_model_migration_verified=False,
            full_device_first_law_verified=False))
    release=read(root/'release.json')
    if (release['tests_exit_code']!=0 or not release['independent_recomputation_pass']
            or release['strict_replay_gate_pass'] or release['production_recovery_allowed']
            or release['replay_program_exit_code']!=1 or release['replay_scientific_audit_exit_code']!=1):
        raise ValueError('Release scope changed')
    with (root/'result_manifest.csv').open(encoding='utf-8',newline='') as f:rows=list(csv.DictReader(f))
    if len(rows)!=release['required_file_count'] or len({r['relative_path'] for r in rows})!=len(rows):
        raise ValueError('Manifest incomplete')
    for row in rows:
        p=(workspace/row['relative_path']).resolve()
        if not p.is_relative_to(workspace) or p.stat().st_size!=int(row['bytes']) or sha256(p)!=row['sha256']:
            raise ValueError('Evidence changed: '+str(p))
    print(json.dumps(dict(package_integrity_pass=True,required_files=len(rows),source_commit=release['source_commit'],
        strict_replay_gate_pass=False,production_recovery_allowed=False),indent=2))


if __name__=='__main__':main()
