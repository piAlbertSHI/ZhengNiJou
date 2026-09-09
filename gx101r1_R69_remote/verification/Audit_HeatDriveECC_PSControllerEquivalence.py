"""Independently inspect public paired arrays, event coverage and solver cost."""
import argparse
import json
from pathlib import Path
import h5py
import numpy as np
from Audit_HeatDriveECC_ColdChamberRejection import read
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def metrics(t,v):
    if (t.ndim!=1 or v.shape!=(len(t),6) or len(t)<2 or t[0]!=0 or t[-1]!=10
            or not np.isfinite(t).all() or not np.isfinite(v).all() or np.any(np.diff(t)<=0)):
        raise ValueError('Invalid paired time/state coverage')
    errors=np.max(abs(v[:,:3]-v[:,3:]),axis=0)
    limits=[1e-7]*3
    bounds=[(-.35,.02),None,(-.14733718599999998,.1)]
    coverage=[]
    for i,bound in enumerate(bounds):
        if bound is None:continue
        for side,value in zip(('lower','upper'),bound):
            counts=[int(np.sum(abs(v[:,j]-value)<=1e-7)) for j in (i,i+3)]
            coverage.append(dict(column=i,boundary=side,value=value,matching_samples=counts))
    events=[]
    for event in (.15,5.,5.15):
        before=np.flatnonzero(t<event-1e-10);after=np.flatnonzero(t>event+1e-10)
        if not len(before) or not len(after):raise ValueError('Unbracketed reset event')
        a,b=before[-1],after[0]
        if max(event-t[a],t[b]-event)>.0011:raise ValueError('Insufficient event sampling')
        events.append(dict(event_time_s=event,before_s=float(t[a]),after_s=float(t[b]),
            reference_pressure_bracket_delta_MPa=float(v[b,0]-v[a,0]),
            candidate_pressure_bracket_delta_MPa=float(v[b,3]-v[a,3]),
            integral_after_MPa=[float(v[b,j]) for j in (2,5)],exact_instantaneous_jump=False))
    held=(t>5.+1e-9)&(t<5.15-1e-9)
    if not held.any():raise ValueError('Reset-held interval missing')
    held_error=float(np.max(abs(v[held][:,[2,5]])))
    dt=np.diff(t)
    return dict(sample_count=len(t),maximum_absolute_errors=errors.tolist(),comparison_limits=limits,
        equivalence_pass=bool(np.all(errors<=limits)),actual_limit_coverage=coverage,
        all_limits_exercised=all(min(r['matching_samples'])>0 for r in coverage),events=events,
        reset_held_max_abs_integral_MPa=held_error,reset_hold_pass=held_error<=1e-7,
        step_count_below_1e_6_s=int(np.sum(dt<1e-6)),minimum_step_s=float(dt.min()),
        step_quantiles_s=np.quantile(dt,[0,.01,.1,.5,.9,1]).tolist(),
        sample_counts_by_second=np.histogram(t,bins=np.arange(11))[0].tolist())


def audit(repo):
    cases=[('baseline','ps_controller_equivalence_20260909_v2','35ab1dc15bfdc3266ef12e7c56ec1b77f601bc01',False),
           ('reset_input_gated','ps_controller_equivalence_reset_gated_20260909','114c87d7e73b48c1f1ef1306d7b3e450a3c8c793',True)]
    source=repo/'verification/simscape_sma_controller/+ecc_sma_controller/pressure_controller.ssc'
    source_hash=sha256(source);files=[source];results=[];baseline=None;identical=False
    for label,folder,commit,gated in cases:
        root=repo/'outputs_storage_audit'/folder;path=root/'controller_equivalence.json';r=read(path)
        raw=root/'paired_observations.mat';public=root/'paired_public_traces.mat'
        if (r['execution_commit']!=commit or not r['collection_pass'] or r['coupled_model_tested'] or r['production_recovery_allowed']
                or r.get('reference_input_gated_during_reset',False)!=gated or r['component_sha256']!=source_hash
                or sha256(raw)!=r['observations_sha256']):raise ValueError('Controller trial provenance changed')
        with h5py.File(public) as f:
            t=f['time_s'][...].ravel();v=f['values'][...].T
            origin=''.join(chr(int(x)) for x in f['source_sha256'][...].ravel())
            if origin!=r['observations_sha256']:raise ValueError('Portable export source changed')
        result=metrics(t,v)
        if result['maximum_absolute_errors']!=r['maximum_absolute_errors']:raise ValueError('Reported error differs from arrays')
        result.update(case=label,execution_commit=commit,reference_input_gated_during_reset=gated)
        if baseline is None:baseline=(t,v)
        else:identical=bool(np.array_equal(t,baseline[0]) and np.array_equal(v,baseline[1]))
        results.append(result);files += [path,raw,public,root/'matlab_diary.log']
    freeze=repo/'verification/c200_mainline_freeze_contract.json';f=read(freeze);files.append(freeze)
    for key in ('result','checkpoint'):
        p=repo/f[key+'_relative_path']
        if sha256(p)!=f[key+'_sha256']:raise ValueError('C200 changed')
        files.append(p)
    return dict(schema='heatdrive_ecc_ps_controller_equivalence_audit_v1',evidence_audit_pass=True,cases=results,
        isolated_equivalence_pass=all(r['equivalence_pass'] and r['all_limits_exercised'] and r['reset_hold_pass'] for r in results),
        reset_input_gating_produced_identical_time_and_values=identical,
        reset_input_gating_is_verified_performance_fix=False,coupled_model_tested=False,production_recovery_allowed=False,
        controller_state_mapping_into_c200_verified=False,full_device_first_law_verified=False,
        input_sha256={str(p.relative_to(repo)):sha256(p) for p in files})


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output-root',type=Path,required=True);args=p.parse_args()
    if args.output_root.exists():raise FileExistsError('Never overwrite evidence')
    result=audit(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'controller_pair_audit.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k!='input_sha256'},indent=2))
    raise SystemExit(0 if result['isolated_equivalence_pass'] else 1)
