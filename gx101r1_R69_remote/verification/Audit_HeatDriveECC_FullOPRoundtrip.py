"""Audit an unchanged full-OP identity control, not structural migration."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

from Audit_HeatDriveECC_C201CyclePackage import read
from Audit_HeatDriveECC_PublicSnapshotEvidence import compare_window, observed
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_TargetInitialization import rows


def compute(repo):
    base=repo/'outputs_storage_audit'
    root=base/'full_op_roundtrip_20260908'
    meta=read(root/'full_op_roundtrip.json')
    forbidden=('production_recovery_allowed','physical_options_changed','controller_representation_changed',
               'command_horizon_extended','source_op_edited','final_checkpoint_saved','anonymous_indices_edited')
    if not meta['computation_complete'] or meta['error_message'] or any(meta[k] for k in forbidden):
        raise ValueError('Wrong control scope')
    source=base/'c200_source_compatibility_20260907/archived_source_probe_v4/DO_NOT_RESUME_FOR_PRODUCTION.mat'
    if sha256(source)!=meta['source_snapshot_sha256']:
        raise ValueError('Source full OP changed')
    reference_root=base/'c200_two_step_snapshot_20260908'
    reference=observed(reference_root)
    hashes={str(source.relative_to(repo)):sha256(source)}
    paths=[root/'full_op_roundtrip.json',reference_root/'restored_step_signals.mat',
           reference_root/'registered_states.mat',root/'control_inputs.mat',root/'matlab_diary.log']
    if len(meta['cases'])!=2 or {r['arm'] for r in meta['cases']}!={'untouched','identity_dataset_write'}:
        raise ValueError('Incomplete control arms')
    cases=[];inputs=[]
    for item in meta['cases']:
        arm=item['arm'];output_path=root/(arm+'_observations.mat')
        input_path=root/(arm+'_input_public_states.mat')
        if (not item['public_input_readback_exact'] or sha256(input_path)!=item['input_sha256']
                or sha256(output_path)!=item['observation_sha256']):
            raise ValueError('Control provenance changed')
        actual=rows(output_path);inputs.append(rows(input_path,True))
        compared=compare_window(reference,actual,[2000,2000.001,2000.002],[2000.001,2000.002],1)
        if len(compared)!=1474 or len(inputs[-1])!=73:
            raise ValueError('Incomplete observation coverage')
        cases.append(dict(arm=arm,comparisons=compared,
            failed_initial_groups=sum(not r['comparisons'][0]['pass_endpoint_match'] for r in compared),
            failed_one_step_groups=sum(not r['comparisons'][1]['pass_endpoint_match'] for r in compared),
            exact_initial_groups=sum(r['exact'][0] for r in compared),
            exact_one_step_groups=sum(r['exact'][1] for r in compared)))
        paths.extend((input_path,output_path))
    input_comparison=compare_window(inputs[0],inputs[1],[2000.001],[2000.001],0)
    if not all(all(r['exact']) for r in input_comparison):
        raise ValueError('Identity public input changed')
    for path in paths:hashes[str(path.relative_to(repo))]=sha256(path)
    return dict(schema='heatdrive_ecc_full_op_roundtrip_evidence_v1',execution_commit=meta['execution_commit'],
        identity_public_input_exact=True,public_input_group_count=73,observation_group_count=1474,
        unchanged_full_op_roundtrip_bitwise_pass=all(all(r['exact']) for c in cases for r in c['comparisons']),
        cases=cases,input_sha256=hashes,production_recovery_allowed=False,
        target_reconstruction_verified=False,structural_migration_verified=False,full_device_first_law_verified=False)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify',action='store_true')
    parser.add_argument('--seal',action='store_true')
    args=parser.parse_args()
    repo=Path(__file__).resolve().parents[1]
    path=repo/'outputs_storage_audit/full_op_roundtrip_20260908/independent_roundtrip_audit.json'
    result=compute(repo)
    if args.verify or args.seal:
        if result!=read(path):raise ValueError('Saved evidence changed')
    else:
        if path.exists():raise FileExistsError('Do not overwrite evidence')
        path.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    if args.seal or args.verify:
        subprocess.run([sys.executable,'-X','utf8',str(repo/'verification/Audit_HeatDriveECC_PublicSnapshotPackage.py')],
                       check=True,stdout=subprocess.DEVNULL)
        seal=path.parent/'supplement_manifest.json'
        workspace=repo.parent
        if args.seal:
            if seal.exists() or subprocess.check_output(['git','status','--porcelain'],cwd=workspace,text=True).strip():
                raise ValueError('Require clean source and fresh supplement manifest')
            commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=workspace,text=True).strip()
            previous=repo/'outputs_storage_audit/public_snapshot_release_20260908'
            base=read(previous/'release.json')['source_base_commit']
            patch=path.parent/'source_delta.patch'
            if patch.exists():raise FileExistsError('Do not overwrite source delta')
            subprocess.run(['git','diff','--binary',f'--output={patch}',base,commit],cwd=workspace,check=True)
            subprocess.run(['git','apply','--reverse','--check',str(patch)],cwd=workspace,check=True)
            files=list(path.parent.glob('*.mat'))+list(path.parent.glob('*.json'))+[patch,path.parent/'matlab_diary.log']
            files.extend(previous/n for n in ('release.json','result_manifest.csv'))
            files.append(workspace/'项目文档/研究笔记/2026-09-08_完整OP原值写回实测补充.md')
            payload=dict(source_commit=commit,source_base_commit=base,production_recovery_allowed=False,
                files=[dict(path=str(p.relative_to(workspace)),bytes=p.stat().st_size,sha256=sha256(p)) for p in sorted(files)])
            seal.write_text(json.dumps(payload,indent=2,allow_nan=False)+'\n',encoding='utf-8')
        manifest=read(seal)
        if manifest['production_recovery_allowed'] or len({r['path'] for r in manifest['files']})!=len(manifest['files']):
            raise ValueError('Invalid supplement scope or manifest')
        for item in manifest['files']:
            target=(workspace/item['path']).resolve()
            if (not target.is_relative_to(workspace) or target.stat().st_size!=item['bytes']
                    or sha256(target)!=item['sha256']):
                raise ValueError('Supplement evidence changed: '+str(target))
        print(json.dumps(dict(supplement_integrity_pass=True,required_files=len(manifest['files']))))
    print(json.dumps({k:v for k,v in result.items() if k not in ('cases','input_sha256')},indent=2))
    if not result['unchanged_full_op_roundtrip_bitwise_pass']:raise SystemExit(1)


if __name__=='__main__':main()
