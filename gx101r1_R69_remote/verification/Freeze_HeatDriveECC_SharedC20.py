"""Freeze C20, prove observation subsets, and list only bounded intermediates."""
import json
from pathlib import Path
import shutil
import subprocess
import sys

import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from HeatDriveECC_TraceColumns import load
from Run_HeatDriveECC_ConservativeTransport import write_json


def file_record(p):
    return dict(path=str(p),bytes=p.stat().st_size,sha256=sha256(p))


def main():
    repo=Path(__file__).resolve().parents[1];audit=repo/'outputs_storage_audit'
    out=audit/'shared_endpoint_inventory_C20_20261026_r2';receipt=out/'closeout_verification.json'
    if receipt.exists():raise ValueError('Never overwrite a completed freeze')
    read=lambda p:json.loads(p.read_text(encoding='utf-8'))
    root=Path('C:/tmp/se21_shared_endpoint_inventory_C20_r1_20261026')
    trial=Path('C:/tmp/se21_shared_endpoint_tail_equivalence_C2_r1_20261026')
    original=Path('C:/tmp/se21_shared_endpoint_inventory_C2_r1_20261026')
    prior=read(audit/'shared_endpoint_inventory_C2_20261026_r2/closeout_verification.json')
    protected=[]
    for r in prior['frozen_baseline_dependencies_reverified']:
        if sha256(Path(r['path']))!=r['sha256']:raise ValueError('Frozen baseline changed')
        protected.append(r)
    p=repo/'heatdrive_ecc_coupled_se21.slx'
    if sha256(p)!=prior['protected_model_sha256']:raise ValueError('Protected model changed')
    modules=['test_CV_tail_observation',*prior['test_modules']]
    run=subprocess.run([sys.executable,'-X','utf8','-m','unittest',*modules],cwd=repo/'verification',
                       stdout=subprocess.PIPE,stderr=subprocess.STDOUT,check=False)
    (out/'targeted_tests.log').write_bytes(run.stdout)
    if run.returncode:raise ValueError('Targeted regression failed')
    proofs=[];candidates=[];keep=[]
    for name in ('native_CV_observations.mat','workspace_CV_observations.mat','source_CV_observations.mat'):
        a=original/'shared'/name;b=trial/'shared'/name;x=load(a);y=load(b)
        if set(x)!=set(y):raise ValueError('Not the same observed physical trial ownership')
        for key,row in y.items():
            old=x[key];mask=(old['time_s']>=row['time_s'][0])&(old['time_s']<=row['time_s'][-1])
            if (old['unit']!=row['unit'] or not np.array_equal(old['time_s'][mask].view(np.uint64),row['time_s'].view(np.uint64))
                    or not np.array_equal(old['values'][mask].view(np.uint64),row['values'].view(np.uint64))):
                raise ValueError('A retained raw event/value is not covered: '+str(key))
        proofs.append(dict(retained=file_record(a),candidate=file_record(b),trace_count=len(y),
            all_original_time_bits_and_value_bits_exactly_covered=True,whole_MAT_file_byte_identity_claimed=False))
        keep.append(file_record(a));candidates.append(dict(path=str(b),workspace_root=str(trial),kind='file',
            bytes=b.stat().st_size,files=[file_record(b)],full_content_subset_proved=True))
    for r in (root,trial):
        keep.extend(file_record(p) for p in sorted((r/'shared').glob('*.mat')) if not (r==trial and p.name in
            ('native_CV_observations.mat','workspace_CV_observations.mat','source_CV_observations.mat')))
        for suffix in ('cache','codegen','shared/seed'):
            p=r/suffix
            if not p.is_dir():continue
            descendants=list(p.rglob('*'))
            if p.is_symlink() or any(v.is_symlink() for v in descendants):raise ValueError('Unexpected linked candidate')
            files=[file_record(v) for v in descendants if v.is_file()]
            candidates.append(dict(path=str(p),workspace_root=str(r),kind='directory',files=files,
                bytes=sum(v['bytes'] for v in files),purpose='regenerable cache/codegen or unpacked constructor model'))
    write_json(out/'observation_subset_retirement_proof.json',dict(schema='heatdrive_ecc_observation_subset_retirement_v1',
        comparisons=proofs,physical_variant_or_diagnostic_arm_not_deleted=True,
        retained_full_C2_required_for_reconstructing_retired_values=True))
    write_json(out/'generated_intermediate_candidates.json',dict(candidates=candidates,
        expected_raw_before_after=keep,protected_model_sha256=prior['protected_model_sha256'],
        frozen_C200=[r for r in protected if r['path'].endswith(('physical_simscape_result.mat','final_operating_point.mat'))]))
    meta=out/'execution_metadata';meta.mkdir(exist_ok=False)
    for r,tag in ((root,'C20'),(trial,'logging_C2')):
        d=meta/tag;d.mkdir()
        for p in [r/'coupled_CV_execution.json',*[r/'shared'/n for n in
            ('completed_initial_probe.json','CV_contract.json','endpoint_inventory_construction.json',
             'cold_preflight.json','solver_time.json','solver_time.jsonl')],Path(str(r)+'.log')]:
            shutil.copyfile(p,d/p.name)
    snapshot=[]
    for r in (root,trial):
        files=[p for p in r.rglob('*') if p.is_file()]
        snapshot.append(dict(path=str(r),files=len(files),bytes=sum(p.stat().st_size for p in files)))
    write_json(receipt,dict(schema='heatdrive_ecc_shared_C20_closeout_v1',
        reader_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),
        review_sha256=sha256(out/'shared_endpoint_C20_review.json'),
        subset_retirement_proof_sha256=sha256(out/'observation_subset_retirement_proof.json'),
        actual_C20_raw=[file_record(p) for p in sorted((root/'shared').glob('*.mat'))],
        bounded_storage_before_retirement=snapshot,retirement_candidate_bytes=sum(r['bytes'] for r in candidates),
        frozen_baseline_dependencies_reverified=protected,protected_model_sha256=prior['protected_model_sha256'],
        regression_modules=modules,regression_return_code=run.returncode,regression_log_sha256=sha256(out/'targeted_tests.log'),
        real_sessions=[dict(session=54313,exit_code=0,scope='passive cold C2 logging comparison'),
                       dict(session=97974,exit_code=0,scope='1303 actually recorded trace comparisons'),
                       dict(session=7552,exit_code=0,scope='one continuous fresh cold 200 s / 20 cycles')],
        terminal_OP_saved=False,current_result_is_not_a_resume_state=True,outer_solve_admitted=False,
        periodic_steady_state=False,all_mechanism_gates_evaluated=False,Table4_reproduced=False,goal_complete=False))
    print(json.dumps(dict(output=str(out),tests_exit=run.returncode,subset_traces=sum(r['trace_count'] for r in proofs),
                         retirement_candidate_bytes=sum(r['bytes'] for r in candidates))))


if __name__=='__main__':main()
