"""Independently verify analytic reset fixtures before a coupled solver trial."""
import argparse
import json
from pathlib import Path
import numpy as np
from Audit_HeatDriveECC_ColdPassivePSObserver import read,sha256


def exact_solution(time,sampled):
    t=np.asarray(time,dtype=float)
    if t.ndim!=1 or not np.isfinite(t).all() or np.any(t<0):raise ValueError('Invalid fixture time')
    y=1+t+t*t
    if sampled:
        n=np.floor(t/.001+1e-12)
        y+=.001**2*n*(n-1)/2+n*.001*(t-n*.001)
    return y


def audit_case(c):
    t,y,f=[np.asarray(c[k],dtype=float) for k in ('time_s','inventory','logged_flux')]
    if t.ndim!=1 or len(t)<2 or y.shape!=t.shape or f.shape!=t.shape or not np.isfinite([t,y,f]).all():
        raise ValueError('Incomplete analytic fixture history')
    if t[0]!=0 or t[-1]!=.04 or np.any(np.diff(t)<=0):raise ValueError('Fixture horizon changed')
    if c['forcing'] not in ('continuous','sampled'):raise ValueError('Unknown forcing')
    sampled=c['forcing']=='sampled';exact=exact_solution(t,sampled)
    expected_flux=1+2*t+(.001*np.floor(t/.001+1e-12) if sampled else 0)
    if not np.allclose(f,expected_flux,rtol=0,atol=2e-15):raise ValueError('Actual fixture forcing differs')
    if not np.allclose(c['analytic_inventory'],exact,rtol=0,atol=5e-16):raise ValueError('Analytic reference differs')
    maximum=float(np.max(abs(y-exact)))
    recorded_maximum=float(np.max(abs(y-np.asarray(c['analytic_inventory']))))
    if recorded_maximum!=c['max_abs_analytic_error']:raise ValueError('Reported error differs from its saved reference')
    return dict(forcing=c['forcing'],reset_method=c['reset_method'],initial_step_setting=c['initial_step_setting'],
        samples=len(t),max_abs_analytic_error=maximum,matlab_reference_max_abs_error=recorded_maximum,
        independent_reference_roundoff_difference=float(np.max(abs(np.asarray(c['analytic_inventory'])-exact))),analytic_fixture_only=True)


def build(repo):
    root=repo/'outputs_storage_audit'
    paths=[root/(solver+'_analytic_reset_probe_20260910')/'ode23t_reset_probe.json' for solver in ('ode23t','ode23tb')]
    reports=[read(p) for p in paths];summaries=[]
    expected=[ [('continuous','Fast','auto'),('sampled','Fast','auto'),('sampled','Robust','auto'),('sampled','Fast','1e-6')],
               [('continuous','Fast','auto'),('sampled','Fast','auto')] ]
    for raw,configuration in zip(reports,expected):
        if raw['actual_coupled_model_tested'] or raw['production_recovery_allowed'] or raw['matlab_release']!='2025b':
            raise ValueError('Wrong fixture provenance or scope')
        cases=raw['case_results']
        if [(c['forcing'],c['reset_method'],c['initial_step_setting']) for c in cases]!=configuration:
            raise ValueError('Undeclared fixture settings')
        summaries.append([audit_case(c) for c in cases])
    if reports[1]['solver']!='ode23tb':raise ValueError('Wrong candidate solver')
    baseline=summaries[0][1]['max_abs_analytic_error'];candidate=summaries[1][1]['max_abs_analytic_error']
    if candidate>1e-12 or baseline<1e-7:raise ValueError('Declared analytic solver comparison not supported')
    for key in ('time_s','inventory','logged_flux'):
        if reports[0]['case_results'][1][key]!=reports[0]['case_results'][2][key]:raise ValueError('Fast/Robust fixture differs')
    startup=reports[0]['case_results'][3]
    if (startup['steps_after_candidate_reset_s'][0]!=1e-6
            or not np.allclose(startup['steps_after_candidate_reset_s'][1:],.00025,rtol=0,atol=1e-14)):
        raise ValueError('InitialStep/reset-step observation changed')
    return dict(evidence_audit_pass=True,case_summaries=summaries,
        initial_step_parameter_does_not_shrink_later_fixture_reset_steps=True,
        candidate_reduces_analytic_fixture_error=True,allows_isolated_coupled_ode23tb_trial=True,
        coupled_conservation_pass=False,production_recovery_allowed=False,table4_reproduction_claim=False,
        input_sha256={str(p.relative_to(repo)):sha256(p) for p in paths})


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output-root',type=Path,required=True);args=parser.parse_args()
    if args.output_root.exists():raise FileExistsError('Never overwrite evidence')
    r=build(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'analytic_reset_probe_audit.json').write_text(json.dumps(r,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps(r,indent=2))
