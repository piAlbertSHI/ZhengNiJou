"""Reconstruct a sampled Clock from its directly observed acquisition times."""
import argparse
import json
from pathlib import Path
import numpy as np
from Audit_HeatDriveECC_ColdPassivePSObserver import read,sha256


def reconstruct(time,acquisition):
    t=np.asarray(time,dtype=float);h=np.asarray(acquisition,dtype=float)
    if (t.ndim!=1 or h.ndim!=1 or len(h)!=41 or not np.isfinite(t).all() or not np.isfinite(h).all()
            or np.any(np.diff(t)<=0) or np.any(np.diff(h)<=0) or t[0]!=0 or h[0]!=0 or t[-1]!=.04 or h[-1]!=.04):
        raise ValueError('Incomplete measured Clock acquisition history')
    idx=np.searchsorted(h,t,side='right')-1
    areas=np.r_[0,np.cumsum(h[:-1]*np.diff(h))]
    return 1+2*t+h[idx],1+t+t*t+areas[idx]+h[idx]*(t-h[idx])


def audit_case(c):
    t=np.array(c['time_s']);h=np.array(c['held_value']);nominal=np.arange(41)*.001
    if (c['solver']!='ode23t' or c['reset_method']!='Fast' or c['sample_time']!='.001'
            or not np.array_equal(c['flux_time_s'],t) or not np.array_equal(c['held_time_s'],nominal)):
        raise ValueError('Fixture or source sample schedule differs')
    expected,exact=reconstruct(t,h);f=np.array(c['flux']);y=np.array(c['inventory'])
    if f.shape!=t.shape or y.shape!=t.shape or not np.isfinite([f,y]).all():raise ValueError('Invalid continuous observations')
    if not np.allclose(f,expected,rtol=0,atol=2e-15):raise ValueError('Observed forcing differs from sampled Clock')
    _,nominal_exact=reconstruct(t,nominal)
    nominal_error=float(max(abs(exact-nominal_exact)))
    if nominal_error>5e-16:raise ValueError('Acquisition timing materially changes the analytic reference')
    return dict(max_step_s=c['max_step_s'],samples=len(t),observed_sample_hits=len(h),
        maximum_flux_reconstruction_error=float(max(abs(f-expected))),
        max_abs_analytic_error=float(max(abs(y-exact))),
        max_nominal_reference_difference=nominal_error,
        max_acquisition_vs_nominal_time_difference_s=float(max(abs(h-nominal))),
        event_side_inferred_from_direct_sampled_clock=True)


def build(repo):
    root=repo/'outputs_storage_audit';path=root/'reset_event_sides_20260910/reset_event_sides.json';r=read(path)
    if r['actual_coupled_model_tested'] or r['production_recovery_allowed'] or r['matlab_release']!='2025b':
        raise ValueError('Wrong fixture scope')
    if [c['max_step_s'] for c in r['cases']]!=[.00002,.00001]:raise ValueError('Undeclared step comparison')
    results=[audit_case(c) for c in r['cases']]
    ratio=results[0]['max_abs_analytic_error']/results[1]['max_abs_analytic_error']
    if not 3.5<ratio<4.5:raise ValueError('No measured second-order step trend')
    old=root/'ode23t_20us_analytic_reset_probe_20260910/ode23t_reset_probe.json';prior=read(old)['case_results'][0]
    c=r['cases'][0]
    for new_key,old_key in [('time_s','time_s'),('inventory','inventory'),('flux','logged_flux')]:
        if c[new_key]!=prior[old_key]:raise ValueError('Instrumentation changed the old 20us trajectory')
    source=repo/'verification/Probe_HeatDriveECC_ResetEventSides.m'
    return dict(event_side_evidence_pass=True,case_results=results,coarse_to_fine_error_ratio=ratio,
        instrumented_20us_trajectory_identical_to_archived=True,
        old_floor_plus_epsilon_forcing_audit_pass=False,old_failure_evidence_preserved=True,
        isolated_coupled_20us_trial_eligible=True,coupled_conservation_pass=False,
        production_recovery_allowed=False,table4_reproduction_claim=False,
        interpretation='Actual sampled Clock values identify acquisition times; nominal discrete output labels are not used for event-side lookup.',
        input_sha256={str(p.relative_to(repo)):sha256(p) for p in (path,old,source)})


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output-root',type=Path,required=True);args=parser.parse_args()
    if args.output_root.exists():raise FileExistsError('Never overwrite evidence')
    r=build(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'reset_event_sides_audit.json').write_text(json.dumps(r,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps(r,indent=2))
