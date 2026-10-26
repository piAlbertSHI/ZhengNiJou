"""Freeze verified bounded OP dependencies and exact observation retirement proofs."""
import json
from pathlib import Path
import shutil
import subprocess
import sys

import numpy as np
from scipy.io import loadmat

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from HeatDriveECC_TraceColumns import unpack
from Run_HeatDriveECC_ConservativeTransport import write_json


def file_row(path):
    p=Path(path);return dict(path=str(p),bytes=p.stat().st_size,sha256=sha256(p))


def exact_packet(a,b):
    count=0
    for group in ('native','workspace','source','state'):
        x=unpack(a[group+'_packet']);y=unpack(b[group+'_packet'])
        if set(x)!=set(y):raise ValueError('Different physical/state ownership')
        for key,row in y.items():
            old=x[key];mask=(old['time_s']>=row['time_s'][0])&(old['time_s']<=row['time_s'][-1])
            if (old['unit']!=row['unit'] or not np.array_equal(old['time_s'][mask].view(np.uint64),row['time_s'].view(np.uint64))
                    or not np.array_equal(old['values'][mask].view(np.uint64),row['values'].view(np.uint64))):
                raise ValueError('Original retained clocks or values are different: '+str(key))
            count+=1
    return count


def main():
    repo=Path(__file__).resolve().parents[1];audit=repo/'outputs_storage_audit'
    out=audit/'shared_endpoint_OP_bounded_cycle_20261026_r2';receipt=out/'closeout_verification.json'
    if receipt.exists():raise ValueError('Never overwrite a completed freeze')
    read=lambda p:json.loads(Path(p).read_text(encoding='utf-8'))
    old=Path('C:/tmp/se21_shared_endpoint_OP_cycle_r1_20261026')
    old_new=Path('C:/tmp/se21_shared_endpoint_OP_new_process_r1_20261026')
    failed=Path('C:/tmp/se21_shared_endpoint_OP_bounded_step_r1_20261026')
    current=Path('C:/tmp/se21_shared_endpoint_OP_bounded_cycle_r1_20261026')
    new=Path('C:/tmp/se21_shared_endpoint_OP_bounded_new_process_r1_20261026')
    review=read(out/'shared_endpoint_OP_review.json')
    if not (review['same_model_actual_all_value_bits_exact'] and review['new_process_actual_all_value_bits_exact']
            and review['new_process_full_cycle_covered']):raise ValueError('Transport equivalence is not proved')
    source=read(current/'shared/state_interface_roundtrip.json')
    if not source['bounded_observation_from_cold_start']:raise ValueError('Not the new bounded epoch')
    old_source=read(old/'shared/state_interface_roundtrip.json');protected=[]
    for record in (source,old_source):
        for key in ('saved_runtime_model','operating_point','interface_contract'):
            p=record[key+'_path']
            if sha256(Path(p))!=record[key+'_sha256']:raise ValueError('State contract changed')
            protected.append(file_row(p))
        p=record['base_workspace']['path']
        if sha256(Path(p))!=record['base_workspace']['sha256']:raise ValueError('Base variable archive changed')
        protected.append(file_row(p))
    for r in source['loaded_project_sources']:
        if sha256(Path(r['path']))!=r['sha256']:raise ValueError('Current bounded source epoch changed')
    prior=read(audit/'shared_endpoint_inventory_C20_20261026_r2/closeout_verification.json')
    modules=[*prior['regression_modules'],'test_shared_endpoint_OP']
    run=subprocess.run([sys.executable,'-X','utf8','-m','unittest',*modules],cwd=repo/'verification',
                       stdout=subprocess.PIPE,stderr=subprocess.STDOUT,check=False)
    (out/'targeted_tests.log').write_bytes(run.stdout)
    if run.returncode:raise ValueError('Regression failed')
    authority=read(repo/'verification/c200_mainline_freeze_contract.json')
    for role in ('result','checkpoint'):
        p=repo/authority[role+'_relative_path']
        if sha256(p)!=authority[role+'_sha256']:raise ValueError('C200 changed')
        protected.append(file_row(p))
    canonical=repo/'heatdrive_ecc_coupled_se21.slx'
    if sha256(canonical)!=prior['protected_model_sha256']:raise ValueError('Protected canonical SLX changed')
    protected.append(file_row(canonical))
    refs={n:current/'shared'/f'{n}_observations.mat' for n in ('continuous_reference','same_model_restored')}
    loaded={n:loadmat(p,simplify_cells=True) for n,p in refs.items()};proofs=[];candidates=[]
    for path,reference in ((old/'shared/continuous_reference_observations.mat','continuous_reference'),
        (old/'shared/same_model_restored_observations.mat','same_model_restored'),
        (old_new/'new_process_restored_observations.mat','same_model_restored'),
        (new/'new_process_restored_observations.mat','same_model_restored')):
        n=exact_packet(loaded[reference],loadmat(path,simplify_cells=True))
        proofs.append(dict(retained=file_row(refs[reference]),candidate=file_row(path),trace_count=n,
            all_original_time_and_value_bits_covered=True,whole_MAT_byte_identity_claimed=False))
        root=next(r for r in (old,old_new,new) if path.is_relative_to(r))
        candidates.append(dict(path=str(path),workspace_root=str(root),kind='file',files=[file_row(path)],
            bytes=path.stat().st_size,full_content_subset_proved=True))
    protected.extend(file_row(p) for p in refs.values())
    roots=(old,old_new,failed,current,new);storage=[]
    for root in roots:
        all_files=[p for p in root.rglob('*') if p.is_file()]
        storage.append(dict(path=str(root),bytes=sum(p.stat().st_size for p in all_files),files=len(all_files)))
        for name in ('cache','codegen'):
            path=root/name
            if not path.is_dir():continue
            items=list(path.rglob('*'))
            if path.is_symlink() or any(p.is_symlink() for p in items):raise ValueError('Linked generated directory')
            files=[file_row(p) for p in items if p.is_file()]
            candidates.append(dict(path=str(path),workspace_root=str(root),kind='directory',files=files,
                bytes=sum(r['bytes'] for r in files)))
    write_json(out/'exact_observation_retirement_proof.json',dict(comparisons=proofs,
        distinct_continuous_and_restored_event_clocks_both_retained=True,
        OP_models_base_archives_and_component_libraries_are_not_candidates=True))
    write_json(out/'retirement_candidates.json',dict(candidates=candidates,protected=protected,
        special_protection='shared/seed contains the ACTUAL persisted runtime model; never treat it as a disposable unpacked seed'))
    meta=out/'execution_metadata';meta.mkdir(exist_ok=False)
    for root,tag in ((old,'unbounded_source'),(old_new,'unbounded_new_process'),(failed,'rejected_logging_change'),
                     (current,'bounded_source'),(new,'bounded_new_process')):
        dest=meta/tag;dest.mkdir()
        for path in (root/'state_interface_execution.json',root/'shared/state_interface_roundtrip.json',
            root/'new_process_restore.json',root/'FAILED_DO_NOT_RESUME.json',
            root/'shared/endpoint_inventory_construction.json',Path(str(root)+'.log')):
            if path.is_file():shutil.copyfile(path,dest/path.name)
    keep=[file_row(source[k+'_path']) for k in ('saved_runtime_model','operating_point','interface_contract')]
    keep.append(file_row(source['base_workspace']['path']))
    write_json(out/'CURRENT_DIAGNOSTIC_RUNTIME_KEEP.json',dict(schema='heatdrive_ecc_bounded_diagnostic_runtime_keep_v1',
        source_root=str(current/'shared'),snapshot_s=source['snapshot_s'],fixed_command_horizon_s=1000,
        required_files=keep,component_build_root=str(current/'shared/endpoint_component_build'),
        required_loaded_project_sources=source['loaded_project_sources'],source_OP_sha256=source['operating_point_sha256'],
        strict_checksum_policy='error/error',full_cycle_same_and_new_process_bit_equivalence_pass=True,
        only_unchanged_contract_diagnostic_warmup_may_use_this_OP=True,
        production_recovery_or_outer_solve_or_Table4_allowed=False,
        C200_unique_mainline_reference_not_replaced=True,never_reconstruct_state_from_observations=True))
    write_json(receipt,dict(schema='heatdrive_ecc_shared_OP_proof_closeout_v1',
        freeze_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),
        formal_review_sha256=sha256(out/'shared_endpoint_OP_review.json'),
        exact_retirement_proof_sha256=sha256(out/'exact_observation_retirement_proof.json'),
        bounded_source_OP_sha256=source['operating_point_sha256'],raw_state_or_OP_edited=False,
        bounded_source_count=len(source['loaded_project_sources']),regression_modules=modules,regression_return_code=run.returncode,
        regression_log_sha256=sha256(out/'targeted_tests.log'),bounded_storage_before_retirement=storage,
        candidate_bytes=sum(r['bytes'] for r in candidates),
        failed_bounded_change_exit_code=1,failed_change_did_not_relax_checksums=True,
        full_goal_complete=False,periodic_steady_state=False,all_mechanism_gates_evaluated=False,
        production_recovery_allowed=False,Table4_reproduced=False))
    print(json.dumps(dict(output=str(out),regression_exit=run.returncode,candidate_bytes=sum(r['bytes'] for r in candidates))))


if __name__=='__main__':main()
