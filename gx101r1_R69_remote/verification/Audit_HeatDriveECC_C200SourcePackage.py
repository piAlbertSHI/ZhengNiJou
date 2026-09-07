"""Verify C200 archival recovery evidence without authorizing new-model recovery."""
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


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--create',action='store_true')
    args=parser.parse_args()
    repo=Path(__file__).resolve().parents[1]
    workspace=repo.parent
    audit=repo/'outputs_storage_audit'
    evidence=audit/'c200_source_compatibility_20260907'
    root=audit/'c200_source_restore_release_20260907'
    capture=read(evidence/'c200_state_capture_v1.json')
    endpoint_paths=[evidence/n for n in ('c200_endpoint_audit_v1.json','c200_observed_endpoint_audit_v1.json')]
    for p in endpoint_paths:
        r=read(p)
        if (not r['strict_archival_restore_pass'] or not r['all_observed_endpoint_match'] or r['compared_channel_count']!=382
                or r['native_trace_count']!=1240 or r['native_storage_component_count']!=119
                or r['new_model_recovery_allowed'] or r['whole_model_first_law_verified']):
            raise ValueError('Endpoint scope changed')
    if (not capture['all_observation_comparisons_pass'] or capture['maximum_observation_difference']!=0
            or capture['registered_state_groups']!=73 or capture['registered_scalar_channels']!=1376
            or capture['packed_solver_channels']!=995 or capture['packed_solver_semantic_mapping_verified']
            or capture['new_model_recovery_allowed'] or capture['whole_model_first_law_verified']):
        raise ValueError('State capture scope changed')
    if args.create:
        dirty=subprocess.check_output(['git','status','--porcelain'],cwd=workspace,text=True)
        if dirty.strip() or root.exists():
            raise ValueError('Require clean source and a new release directory')
        commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=workspace,text=True).strip()
        base=read(audit/'tl_inventory_release_20260906/release.json')
        source_zip=audit/'tl_inventory_release_20260906/source_snapshot.zip'
        if sha256(source_zip)!=base['source_archive_sha256']:
            raise ValueError('Base source changed')
        root.mkdir()
        patch=root/'source_delta.patch'
        subprocess.run(['git','diff','--binary',f'--output={patch}',base['source_commit'],commit],cwd=workspace,check=True)
        subprocess.run(['git','apply','--reverse','--check',str(patch)],cwd=workspace,check=True)
        with (root/'python_tests.log').open('w',encoding='utf-8') as log:
            subprocess.run([sys.executable,'-m','unittest','discover','-s',str(repo/'verification'),'-p','test_*.py','-v'],
                           stdout=log,stderr=subprocess.STDOUT,check=True)
        tasks=[('C200RestoredSignals',endpoint_paths[0],[]),
               ('C200RestoredSignals',endpoint_paths[1],['--probe','archived_source_probe_v4']),
               ('C200StateCapture',evidence/'c200_state_capture_v1.json',[])]
        for i,(script,reference,extra) in enumerate(tasks):
            target=root/f'recomputed_{i+1}.json'
            subprocess.run([sys.executable,'-X','utf8',str(repo/'verification'/f'Audit_HeatDriveECC_{script}.py'),
                            '--repo',str(repo),'--output',str(target),*extra],check=True,stdout=subprocess.DEVNULL)
            if sha256(target)!=sha256(reference):
                raise ValueError('Independent recomputation changed')
        protected=[repo/'verification/c200_mainline_freeze_contract.json']
        authority=read(protected[0])
        for kind in ('result','checkpoint'):
            p=repo/authority[kind+'_relative_path']
            if sha256(p)!=authority[kind+'_sha256']:
                raise ValueError('Frozen C200 changed')
            protected.append(p)
        files=[p for p in workspace.rglob('*') if p.is_file()]
        snapshot=dict(measured_at=datetime.now().astimezone().isoformat(),workspace_bytes=sum(p.stat().st_size for p in files),
                      file_count=len(files),retained_new_evidence_bytes=sum(p.stat().st_size for p in evidence.rglob('*') if p.is_file()),
                      copied_production_raw_bytes=0,deleted_superseded_diagnostic_bytes=read(evidence/'retirement_receipt.json')['deleted_bytes'],
                      git_objects=subprocess.check_output(['git','count-objects','-vH'],cwd=workspace,text=True))
        (root/'workspace_storage_snapshot.json').write_text(json.dumps(snapshot,indent=2)+'\n',encoding='utf-8')
        paths=set(p for p in evidence.rglob('*') if p.is_file()) | set(root.iterdir()) | set(protected) | {source_zip,
            audit/'thermal_wall_release_20260907/release.json',audit/'thermal_wall_release_20260907/result_manifest.csv'}
        rows=[dict(relative_path=str(p.relative_to(workspace)),bytes=p.stat().st_size,sha256=sha256(p)) for p in sorted(paths)]
        with (root/'result_manifest.csv').open('w',encoding='utf-8',newline='') as f:
            writer=csv.DictWriter(f,fieldnames=['relative_path','bytes','sha256'])
            writer.writeheader()
            writer.writerows(rows)
        release=dict(schema='heatdrive_ecc_c200_source_restore_release_v1',source_commit=commit,source_base_commit=base['source_commit'],
                     required_file_count=len(rows),tests_exit_code=0,strict_archival_recovery_verified=True,
                     new_model_recovery_allowed=False,whole_model_first_law_verified=False,table4_reproduction_claim=False,
                     extension_of_cycle_command_horizon_verified=False,parent_release_full_reaudit=False)
        (root/'release.json').write_text(json.dumps(release,indent=2)+'\n',encoding='utf-8')
    release=read(root/'release.json')
    with (root/'result_manifest.csv').open(encoding='utf-8',newline='') as f:
        rows=list(csv.DictReader(f))
    if (len(rows)!=release['required_file_count'] or len({r['relative_path'] for r in rows})!=len(rows)
            or not release['strict_archival_recovery_verified'] or release['tests_exit_code']!=0
            or release['new_model_recovery_allowed'] or release['whole_model_first_law_verified']
            or release['extension_of_cycle_command_horizon_verified'] or release['table4_reproduction_claim']):
        raise ValueError('Release scope changed')
    for row in rows:
        p=(workspace/row['relative_path']).resolve()
        if not p.is_relative_to(workspace) or p.stat().st_size!=int(row['bytes']) or sha256(p)!=row['sha256']:
            raise ValueError('Changed evidence: '+str(p))
    print(json.dumps(dict(package_integrity_pass=True,required_files=len(rows),source_commit=release['source_commit'],
                         strict_archival_recovery_verified=True,new_model_recovery_allowed=False,
                         whole_model_first_law_verified=False),indent=2))


if __name__=='__main__':
    main()
