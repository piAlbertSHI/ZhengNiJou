"""Resolve actual changes, not redundant knots, in the frozen command archive."""
import argparse
import json
from pathlib import Path
import numpy as np
from Audit_HeatDriveECC_ColdPassivePSObserver import read,sha256


def command_intervals(command):
    t=np.asarray(command['time_s'],dtype=float);v=np.asarray(command['values'],dtype=float)
    mode=command['interpolate']
    if (mode not in ('on','off') or t.ndim!=1 or len(t)<2 or v.shape!=t.shape
            or not np.isfinite([t,v]).all() or t[0]!=0 or np.any(np.diff(t)<=0)):
        raise ValueError('Require a complete increasing finite command')
    changed=np.flatnonzero(np.diff(v)!=0)
    transitions=[]
    for i in changed:
        if mode=='on':
            transitions.append(dict(kind='linear_segment',start_s=float(t[i]),end_s=float(t[i+1]),
                left_value=float(v[i]),right_value=float(v[i+1]),slope=float((v[i+1]-v[i])/(t[i+1]-t[i]))))
        else:
            transitions.append(dict(kind='jump',time_s=float(t[i+1]),left_value=float(v[i]),right_value=float(v[i+1])))
    boundary=None if not len(changed) else float(t[changed[0] if mode=='on' else changed[0]+1])
    return dict(block=command['block'],interpolation=mode,initial_value=float(v[0]),
        second_data_knot_s=float(t[1]),constant_prefix_end_exclusive_s=boundary,
        sample_count=len(t),transition_count=len(transitions),transitions=transitions)


def build(repo):
    source=repo/'outputs_storage_audit/sma_derivative_contract_20260909_v3/sma_derivative_contract.json'
    if sha256(source)!='EE5C16D580693FCA925D24D0DB2A8E021BAC65E36F0A77A8E12AE795070ACEE2':
        raise ValueError('Frozen full command archive changed')
    reference=read(source);commands=reference['commands'];rows=[command_intervals(c) for c in commands]
    by_name={r['block'].rsplit('/',1)[1]:r for r in rows}
    bias=by_name['SMAPressureBiasFromWorkspace'];enable=by_name['SMAPressureFeedbackEnableFromWorkspace']
    reset=by_name['SMAPressureFeedbackResetFromWorkspace'];flow=by_name['SMAFlowTargetFromWorkspace']
    if (bias['interpolation']!='on' or flow['interpolation']!='on' or enable['interpolation']!='off'
            or reset['interpolation']!='off' or enable['initial_value']!=0 or reset['initial_value']!=1
            or bias['initial_value']!=-1e-6):raise ValueError('Controller command modes differ')
    ramp=bias['transitions'][0]
    if (not np.isclose(ramp['start_s'],.1,rtol=0,atol=1e-15)
            or ramp['end_s']!=enable['transitions'][0]['time_s'] or ramp['end_s']!=reset['transitions'][0]['time_s']
            or ramp['start_s']!=flow['transitions'][0]['start_s']):raise ValueError('Unexpected first ramp/event ordering')
    kernel=repo/'verification/Evaluate_HeatDriveECC_SMADerivative.m'
    if sha256(kernel)!='113A46F15A8B653867A5E1950DF934EA32D166DF6481EA25D519F8E8E33D161C':
        raise ValueError('Previously tested derivative kernel changed')
    fine=repo/'outputs_storage_audit/nonlinear_cold_held_20us_audit_20260910/nonlinear_cold_held_audit.json'
    if sha256(fine)!='30199AFE974AF13D6EA30CF7D10B6BB8E43F985518E096E9592413C8CA5D51AB':
        raise ValueError('Current held qualification changed')
    actual=read(fine)
    if not actual['local_balance_gate'] or actual['observed_interval_s']!=[0,.04]:raise ValueError('Held qualification scope changed')
    return dict(archive_interval_analysis_pass=True,command_intervals=rows,
        pressure_regimes=[dict(interval_s=[0,ramp['start_s']],right_endpoint_excluded=True,
            pressure_expression='bias=-1e-6 MPa while enable=0 and reset=1',derivative_MPa_s=0),
            dict(interval_s=[ramp['start_s'],ramp['end_s']],right_endpoint_excluded=True,
            pressure_expression='linear bias; integral held zero; bias remains within pressure limits',derivative_MPa_s=ramp['slope']),
            dict(event_time_s=ramp['end_s'],pressure_expression='clip(kp*lag + integral + bias)',
            derivative_requirement='Between events: enable*kp*dlag + dintegral + dbias, with saturation direction logic.',
            event_jump_requirement='At enable 0->1 the raw pressure jump includes kp*lag; cannot replace the event by a zero derivative.')],
        redundant_second_knot_is_not_command_change=True,live_model_full_commands_recaptured=False,
        current_model_verified_horizon_s=.04,allows_automatic_horizon_extension=False,
        complete_dynamic_derivative_verified=False,production_recovery_allowed=False,table4_reproduction_claim=False,
        next_required_evidence='Capture all actual rebuilt command samples and compare with this archive before extending a physical run.',
        input_sha256={str(p.relative_to(repo)):sha256(p) for p in (source,kernel,fine)})


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output-root',required=True,type=Path);args=parser.parse_args()
    if args.output_root.exists():raise FileExistsError('Never overwrite evidence')
    r=build(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'command_interval_audit.json').write_text(json.dumps(r,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in r.items() if k!='command_intervals'},indent=2))
