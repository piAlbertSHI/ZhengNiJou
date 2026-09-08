"""Verify raw-data retirement and preserve rejected initialization evidence."""
import argparse
import csv
from datetime import datetime
import json
from pathlib import Path
import subprocess
import sys

from Audit_HeatDriveECC_C201CyclePackage import cache,read,write
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def evidence(repo):
    base=repo/'outputs_storage_audit';archive=base/'c40_c60_prefix_archive_20260908_v3'
    result=json.loads(subprocess.check_output([sys.executable,'-X','utf8',
        str(repo/'verification/Archive_HeatDriveECC_RawPrefixes.py'),'--verify'],text=True))
    if not result['archive_verification_pass'] or result['source_raw_bytes']!=2509754297:
        raise ValueError('Archive reconstruction failed')
    subprocess.run([sys.executable,'-X','utf8',str(repo/'verification/Audit_HeatDriveECC_FullOPRoundtrip.py'),'--verify'],
                   check=True,stdout=subprocess.DEVNULL)
    matlab=read(archive/'matlab_materialization_audit.json')
    if (not matlab['load_and_value_comparison_pass'] or matlab['error_message'] or len(matlab['cases'])!=2
            or any(len(c['variables'])!=5 or not all(v['isequaln_pass'] for v in c['variables']) for c in matlab['cases'])):
        raise ValueError('MATLAB materialization proof changed')
    receipt=read(archive/'retirement_receipt_20260908_111450.json')
    plan=read(archive/'retirement_plan_20260908_111450.json')
    if not plan['apply'] or receipt!=plan['targets'] or len(receipt)!=4:
        raise ValueError('Retirement receipt changed')
    for item in receipt:
        target=Path(item['path']).resolve()
        if not target.is_relative_to(repo.resolve()) or target.exists():
            raise ValueError('Retired target escaped scope or still exists')
    post=read(archive/'post_retirement_package/package_audit.json')
    if not post['recovery_package_pass'] or post['compacted_raw_files_used']!=2:
        raise ValueError('Post-retirement legacy package failed')
    diagnostic=base/'seed_full_op_without_target_reinit_20260908'
    failed=read(diagnostic/'public_snapshot_control.json')
    if (failed['computation_complete'] or failed['production_recovery_allowed'] or failed['cases']
            or not failed['error_message'] or not failed['seed_target_pass']
            or len(failed['seed_matches'])!=196 or not all(r['pass'] for r in failed['seed_matches'])
            or failed['seed_simscape_use_operating_points']!='on'
            or failed['resume_simscape_use_operating_points']!='off'
            or failed['final_checkpoint_saved'] or list(diagnostic.glob('*_observations.mat'))):
        raise ValueError('Rejected configuration-switch experiment changed')
    old_raw=sum(r['bytes'] for r in receipt if r['reason']=='old_raw_replaced_by_exact_logical_prefix_archive')
    if old_raw!=2509754297:raise ValueError('Retired raw byte count changed')
    return dict(schema='heatdrive_ecc_raw_retirement_evidence_v1',retired_old_raw_bytes=old_raw,
        deleted_temporary_validation_bytes=sum(r['bytes'] for r in receipt)-old_raw,
        original_mat_container_hash_preserved=False,logical_data_reconstruction_verified=True,
        matlab_top_level_variables_verified=10,old_endpoint_differences_retained=True,
        initialization_configuration_switch_rejected=True,configuration_switch_trajectory_observed=False,
        production_recovery_allowed=False,full_device_first_law_verified=False)


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--create',action='store_true');args=parser.parse_args()
    repo=Path(__file__).resolve().parents[1];workspace=repo.parent;base=repo/'outputs_storage_audit'
    root=base/'raw_retirement_release_20260908';summary=evidence(repo)
    if args.create:
        if root.exists() or subprocess.check_output(['git','status','--porcelain'],cwd=workspace,text=True).strip():
            raise ValueError('Require clean source and fresh release')
        root.mkdir();commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=workspace,text=True).strip()
        baseline=read(base/'tl_inventory_release_20260906/release.json')
        source_archive=base/'tl_inventory_release_20260906/source_snapshot.zip'
        if sha256(source_archive)!=baseline['source_archive_sha256']:raise ValueError('Source base changed')
        patch=root/'source_delta.patch'
        subprocess.run(['git','diff','--binary',f'--output={patch}',baseline['source_commit'],commit],cwd=workspace,check=True)
        subprocess.run(['git','apply','--reverse','--check',str(patch)],cwd=workspace,check=True)
        with (root/'python_tests.log').open('w',encoding='utf-8') as log:
            subprocess.run([sys.executable,'-m','unittest','discover','-s',str(repo/'verification'),'-p','test_*.py','-v'],
                           check=True,stdout=log,stderr=subprocess.STDOUT)
        write(root/'evidence_summary.json',summary)
        files=[p for p in workspace.rglob('*') if p.is_file()];size=sum(p.stat().st_size for p in files)
        write(root/'storage_snapshot.json',dict(measured_at=datetime.now().astimezone().isoformat(),
            workspace_bytes=size,workspace_GiB=size/2**30,file_count=len(files),
            production_raw_copied_bytes=0,retired_old_raw_bytes=summary['retired_old_raw_bytes'],
            git_objects=subprocess.check_output(['git','count-objects','-vH'],cwd=workspace,text=True)))
        folders=[root,base/'c40_c60_prefix_archive_20260908_v3',base/'seed_full_op_without_target_reinit_20260908']
        paths={p for folder in folders for p in folder.rglob('*') if p.is_file() and not cache(p)}
        paths.update((source_archive,base/'c40_c60_raw_prefix_coverage_20260908.json'))
        paths.update(base/'full_op_roundtrip_20260908'/n for n in ('supplement_manifest.json','independent_roundtrip_audit.json'))
        for name in ('c200_mainline_freeze_contract.json','runtime_c180_recovery_contract.json'):
            contract_path=repo/'verification'/name;contract=read(contract_path);paths.add(contract_path)
            paths.update(repo/contract[k] for k in ('result_relative_path','checkpoint_relative_path'))
        for cycles,suffix in ((40,'183855'),(60,'204717')):
            paths.add(repo/f'outputs/qian_coupled_runtime_strict_coldstart_gate3_20260904/qian2019_table2_table4_simscape_{cycles}cycle_20260904_{suffix}/final_operating_point.mat')
        paths.update(base/n for n in ('cleanup_candidates_20260908_112113.csv','cleanup_summary_20260908_112113.txt'))
        paths.add(workspace/'项目文档/报告/SMA-SE正逆耦合_第四十二阶段初始化拒绝与数据压缩审核报告.md')
        manifest=[dict(relative_path=str(p.relative_to(workspace)),bytes=p.stat().st_size,sha256=sha256(p)) for p in sorted(paths)]
        with (root/'result_manifest.csv').open('w',encoding='utf-8',newline='') as stream:
            writer=csv.DictWriter(stream,fieldnames=['relative_path','bytes','sha256']);writer.writeheader();writer.writerows(manifest)
        write(root/'release.json',dict(schema='heatdrive_ecc_raw_retirement_release_v1',source_commit=commit,
            source_base_commit=baseline['source_commit'],required_files=len(manifest),tests_exit_code=0,
            production_recovery_allowed=False,full_device_first_law_verified=False))
    if read(root/'evidence_summary.json')!=summary:raise ValueError('Evidence summary changed')
    release=read(root/'release.json')
    if release['tests_exit_code']!=0 or release['production_recovery_allowed'] or release['full_device_first_law_verified']:
        raise ValueError('Release scope changed')
    with (root/'result_manifest.csv').open(encoding='utf-8',newline='') as stream:manifest=list(csv.DictReader(stream))
    if len(manifest)!=release['required_files'] or len({r['relative_path'] for r in manifest})!=len(manifest):
        raise ValueError('Incomplete manifest')
    for item in manifest:
        path=(workspace/item['relative_path']).resolve()
        if not path.is_relative_to(workspace) or path.stat().st_size!=int(item['bytes']) or sha256(path)!=item['sha256']:
            raise ValueError('Release evidence changed: '+str(path))
    print(json.dumps(dict(package_integrity_pass=True,required_files=len(manifest),source_commit=release['source_commit'],**summary),indent=2))


if __name__=='__main__':main()
