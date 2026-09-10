"""Audit command value/slope consistency separately from integration accuracy."""
import argparse
import json
from pathlib import Path
import numpy as np
from Audit_HeatDriveECC_ColdPassivePSObserver import read,sha256


def metrics(r):
    c=r['contract'];t=np.asarray(r['time_s']);b=np.asarray(r['bias_MPa']);d=np.asarray(r['slope_MPa_s']);i=np.asarray(r['integral_MPa'])
    if (t.ndim!=1 or len(t)<2 or any(x.shape!=t.shape for x in (b,d,i)) or not np.isfinite([t,b,d,i]).all()
            or t[0]!=0 or t[-1]!=.14 or np.any(np.diff(t)<=0)
            or not np.array_equal(t,r['slope_time_s']) or not np.array_equal(t,r['integral_time_s'])):
        raise ValueError('Incomplete ramp histories')
    if (c['stop_time_s']!=.14 or not c['integral_held_zero'] or not c['feedback_disabled']
            or c['new_filter_added'] or c['full_feedback_derivative_verified'] or c['production_recovery_allowed']
            or not .14<c['feedback_event_s'] or c['reset_release_s']!=c['feedback_event_s']):
        raise ValueError('Outside pre-feedback qualification scope')
    expected=np.interp(t,c['time_s'],c['bias_MPa'])
    derivative=np.where(t<c['ramp_start_s'],0,c['ramp_slope_MPa_s'])
    if (not np.allclose(b,expected,rtol=0,atol=1e-12) or not np.allclose(d,derivative,rtol=0,atol=1e-12)
            or min(b)<=c['pressure_min_MPa'] or max(b)>=c['pressure_max_MPa']):
        raise ValueError('Wrong value, derivative, or saturation regime')
    return dict(source_value_and_slope_pass=True,samples=len(t),max_bias_error_MPa=float(max(abs(b-expected))),
        max_derivative_error_MPa_s=float(max(abs(d-derivative))),
        auxiliary_integral_error_MPa=float(max(abs(i-expected))),
        auxiliary_integration_precision_qualified=False,coupled_model_tested=False,
        production_recovery_allowed=False,full_feedback_event_verified=False)


def build(repo):
    root=repo/'outputs_storage_audit';p=root/'pre_feedback_ramp_probe_hold_20260910/pre_feedback_ramp_probe.json';r=read(p)
    source=root/'nonlinear_inventory_cold_held_10us_20260910/compiled_states_inspection.json'
    if (r['producer']!='6b707195e496b204e7774f294c2aa7fe0fb74e30' or r['coupled_model_tested']
            or r['production_recovery_allowed'] or sha256(source)!=r['command_source_sha256']
            or sha256(source)!='2D1A1BFBA84027D1CA88ECE5DADFA46D37E9609F287C05D3985F09FF00514CA3'):
        raise ValueError('Wrong source or probe provenance')
    result=metrics(r)
    actual=read(source)['actual_command_schedule'];bias=next(c for c in actual if c['block'].endswith('/SMAPressureBiasFromWorkspace'))
    c=r['contract'];n=len(c['time_s'])
    if c['time_s']!=bias['time_s'][:n] or c['bias_MPa']!=bias['values'][:n]:raise ValueError('Bias samples altered')
    slopes=np.diff(c['bias_MPa'])/np.diff(c['time_s'])
    if not np.array_equal(c['derivative_MPa_s'],np.r_[slopes,0]):raise ValueError('Slope command altered')
    files=[p,source,repo/'verification/Build_HeatDriveECC_PreFeedbackRamp.m',repo/'verification/Probe_HeatDriveECC_PreFeedbackRamp.m']
    result.update(contract=c,input_sha256={str(f.relative_to(repo)):sha256(f) for f in files},
        process_outcomes=[dict(session_id=20712,exit_code=1,phase='From Workspace configuration',
            diagnosis='Noninterpolated source cannot use default extrapolation; no coupled model was run.'),
            dict(session_id=68422,exit_code=0,phase='Explicit hold-tail probe completed')])
    return result


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output-root',required=True,type=Path);args=parser.parse_args()
    if args.output_root.exists():raise FileExistsError('Never overwrite evidence')
    r=build(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'pre_feedback_ramp_audit.json').write_text(json.dumps(r,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in r.items() if k not in ('contract','input_sha256')},indent=2))
