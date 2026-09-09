"""Audit actual PI dependencies and separate smooth intervals from reset events."""
import argparse
import csv
import json
import math
from pathlib import Path
from Audit_HeatDriveECC_ColdChamberRejection import read
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def schedule(command):
    t,v=command['time_s'],command['values'];mode=command['interpolate']
    if (mode not in ('on','off') or len(t)!=len(v) or len(t)<2 or t[0]!=0 or t[-1]!=10
            or not all(math.isfinite(x) for x in t+v) or any(b<=a for a,b in zip(t,t[1:]))):
        raise ValueError('Invalid complete-cycle command')
    intervals=[];events=[]
    for i in range(len(t)-1):
        slope=(v[i+1]-v[i])/(t[i+1]-t[i]) if mode=='on' else 0.
        intervals.append(dict(start_s=t[i],end_s=t[i+1],left_value=v[i],right_limit=v[i+1] if mode=='on' else v[i],slope=slope))
        if mode=='off' and v[i+1]!=v[i]:
            events.append(dict(time_s=t[i+1],before=v[i],after=v[i+1],jump=v[i+1]-v[i],classical_derivative_at_jump_defined=False))
    return intervals,events


def controller(record):
    b={r['path'].split('/',1)[1]:r for r in record['blocks']}
    if len(b)!=len(record['blocks']):raise ValueError('Duplicate controller block')
    wiring={
        'SMAPressurePI_ErrorSum':['SMAFlowTargetFromWorkspace','FlowSensor_SMA_stage13_loop_PS'],
        'SMAPressurePI_ErrorNormalizer':['SMAPressurePI_ErrorSum'],
        'SMAPressurePI_ErrorLag':['SMAPressurePI_ErrorNormalizer'],
        'SMAPressurePI_Kp':['SMAPressurePI_ErrorLag'],'SMAPressurePI_Ki':['SMAPressurePI_ErrorLag'],
        'SMAPressurePEnableProduct':['SMAPressurePI_Kp','SMAPressureFeedbackEnableFromWorkspace'],
        'SMAPressurePI_Integrator':['SMAPressurePI_Ki','SMAPressureFeedbackResetFromWorkspace'],
        'SMAPressurePI_BiasSum':['SMAPressurePEnableProduct','SMAPressurePI_Integrator','SMAPressureBiasFromWorkspace'],
        'SMAPressurePI_Saturation':['SMAPressurePI_BiasSum'],'SMAPressurePI_SimulinkPS':['SMAPressurePI_Saturation']}
    for name,expected in wiring.items():
        actual=b[name]['inputs']
        if ([r['source_block'].split('/',1)[1] for r in actual]!=expected or
                [r['index'] for r in actual]!=list(range(1,len(expected)+1)) or any(r['source_port']!=1 for r in actual)):
            raise ValueError('Actual pressure-controller wiring differs')
    lag=b['SMAPressurePI_ErrorLag'];integ=b['SMAPressurePI_Integrator'];conv=b['SMAPressurePI_SimulinkPS']
    if (lag['type']!='TransferFcn' or lag['resolved']!={'Numerator':1,'Denominator':[.002,1]}
            or b['SMAPressurePI_ErrorNormalizer']['resolved']['Gain']!=1
            or b['SMAPressurePI_ErrorSum']['settings']['Inputs']!='++'
            or b['SMAPressurePI_BiasSum']['settings']['Inputs']!='+++'
            or b['SMAPressurePEnableProduct']['settings']['Inputs']!='**'
            or integ['type']!='Integrator' or integ['settings']['ExternalReset']!='level'
            or integ['settings']['InitialConditionSource']!='internal' or integ['resolved']['InitialCondition']!=0
            or integ['settings']['LimitOutput']!='on'
            or b['FlowSensor_SMA_stage13_loop_PS']['settings']['Unit']!='kg/s'
            or conv['settings']['Unit']!='MPa' or conv['settings']['FilteringAndDerivatives']!='provide'
            or conv['settings']['UdotUserProvided']!='0'):
        raise ValueError('Lag, normalization, limits, reset or conversion differs')
    return [.002,b['SMAPressurePI_Kp']['resolved']['Gain'],b['SMAPressurePI_Ki']['resolved']['Gain'],
        integ['resolved']['LowerSaturationLimit'],integ['resolved']['UpperSaturationLimit'],
        b['SMAPressurePI_Saturation']['resolved']['LowerLimit'],b['SMAPressurePI_Saturation']['resolved']['UpperLimit']]


def audit(repo):
    path=repo/'outputs_storage_audit/sma_derivative_contract_20260909_v3/sma_derivative_contract.json';r=read(path)
    if (r['producer_commit']!='6d55b4e8bea82bb0024afa204c96592d38c8f2ec' or not r['collection_pass']
            or any(r[k] for k in ('simulation_run','state_imported','model_saved','production_recovery_allowed'))):
        raise ValueError('Wrong read-only controller evidence')
    params=controller(r)
    if params!=[.002,-.6,-10,-.14733718599999998,.1,-.35,.02]:raise ValueError('Controller parameters changed')
    expected=['SMA_pressure_bias_command','SMA_mdot_target_command','SMA_pressure_feedback_enable_command','SMA_pressure_feedback_reset_command']
    if [c['variable'] for c in r['commands']]!=expected or [c['interpolate'] for c in r['commands']]!=['on','on','off','off']:
        raise ValueError('Wrong command set or interpolation')
    intervals=[];summaries=[]
    for c in r['commands']:
        parts,events=schedule(c)
        intervals += [dict(variable=c['variable'],**row) for row in parts]
        summaries.append(dict(variable=c['variable'],sample_count=len(c['time_s']),events=events,
            nonzero_slope_intervals=sum(row['slope']!=0 for row in parts),max_abs_slope=max(abs(row['slope']) for row in parts)))
    enable,reset=r['commands'][2:]
    if any(c['time_s']!=enable['time_s'] for c in r['commands']) or any(a+b!=1 or a not in (0,1) or b not in (0,1) for a,b in zip(enable['values'],reset['values'])):
        raise ValueError('Inconsistent enable/reset schedule')
    kernel_path=repo/'outputs_storage_audit/sma_derivative_kernel_20260909/kernel_tests.json';k=read(kernel_path)
    if (k['execution_commit']!='3a101b80d7978ef4dfcf4d17ec3b535f8710909e'
            or not k['kernel_test_pass'] or k['actual_parameters']!=params or len(k['cases'])!=13 or
            any(k[key] for key in ('coupled_model_tested','jump_handling_verified','production_recovery_allowed'))
            or k['smooth_trajectory_max_derivative_error_MPa_s']>=1e-8
            or any(abs(row['expected_dp_MPa_s']-row['dp_MPa_s'])>=1e-12 for row in k['cases'])):
        raise ValueError('Kernel evidence failed')
    config=repo/'outputs_storage_audit/conservative_buffer_coupled_cycle_20260909/conservative/configuration.mat'
    canonical=repo/'heatdrive_ecc_coupled_se21.slx'
    if sha256(config)!=r['configuration_sha256'] or sha256(canonical)!=r['canonical_sha256']:raise ValueError('Source changed')
    frozen_path=repo/'verification/c200_mainline_freeze_contract.json';f=read(frozen_path)
    files=[path,kernel_path,config,canonical,frozen_path]
    files += [repo/'verification'/name for name in ('Evaluate_HeatDriveECC_SMADerivative.m',
        'Test_HeatDriveECC_SMADerivative.m','Audit_HeatDriveECC_SMADerivativeContract.py')]
    for key in ('result','checkpoint'):
        p=repo/f[key+'_relative_path']
        if sha256(p)!=f[key+'_sha256']:raise ValueError('C200 changed')
        files.append(p)
    return dict(schema='heatdrive_ecc_sma_derivative_contract_audit_v1',evidence_audit_pass=True,
        parameters=params,commands=summaries,existing_lag_retained=True,new_filter_required_for_smooth_derivative=False,
        smooth_derivative_formula='dlag=(normalized_error-lag)/tau; dI=bounded_or_reset(Ki*lag); dp=clipped_direction(enable*Kp*dlag+dI+dbias)',
        event_pressure_jump_formula='unclipped_jump=Kp*(enable_after-enable_before)*lag + integral_after-integral_before; bias is continuous',
        ordinary_derivative_does_not_include_event_jump=True,full_pressure_derivative_determined_by_schedule_alone=False,
        kernel_tests_pass=True,coupled_model_tested=False,jump_handling_verified=False,production_recovery_allowed=False,
        input_sha256={str(p.relative_to(repo)):sha256(p) for p in files}),intervals


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output-root',type=Path,required=True);args=p.parse_args()
    if args.output_root.exists():raise FileExistsError('Never overwrite evidence')
    result,rows=audit(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'sma_derivative_audit.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    with (args.output_root/'command_intervals.csv').open('w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
    print(json.dumps({k:v for k,v in result.items() if k!='input_sha256'},indent=2))
