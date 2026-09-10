"""Preserve accepted initialization and rejected finite-window balance evidence."""
import argparse
import csv
import json
from copy import deepcopy
from pathlib import Path
import h5py
import numpy as np
from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_ColdPassivePSObserver import (read,sha256,coordinates,summarize_coordinates,
    decode_tags,component_inventory_preserved,CHAMBERS,BUFFERS)
from Audit_HeatDriveECC_HeldIntervalBalance import balance,check_held_contract,STOP_S


def sampled_rows(f, dataset, count):
    rows=named_rows(f,f[dataset]);grid=None
    if len(rows)!=count:raise ValueError('Incomplete '+dataset)
    for row in rows.values():
        t=row['time_s'][:].ravel();v=row['values'][:].ravel()
        if (len(t)<2 or t[0]!=0 or t[-1]!=STOP_S or np.any(np.diff(t)<=0) or
                v.shape!=t.shape or not np.isfinite([t,v]).all()):
            raise ValueError('Missing finite full-window scalar history')
        if grid is None:grid=t
        elif not np.array_equal(t,grid):raise ValueError('Unaligned exported histories')
    return rows,grid


CASES={
    'baseline':('specific_inventory_hybrid_held_interval_20260910_v2','f01ab7c28f8e85b561f5610301e7f1fdc5183141',.001),
    'halfstep':('specific_inventory_hybrid_held_halfstep_20260910','24c574043c600bb32bea685dfcc79d835f5f8ca0',.0005),
    'quarterstep':('specific_inventory_hybrid_held_quarterstep_20260910','5d014f3697ba9c356be7f3e867141881707d3017',.00025),
    'moderate_control':('specific_inventory_hybrid_held_moderate_control_20260910','829fad4d05b21d5a18a6d41d15824376819d6ce8',.00025),
    'ode23t':('specific_inventory_hybrid_held_ode23t_after_restart_20260910','71c386522bc14dd69bf1255bc939ba511d2c71d6',.00025),
    'robust_reset':('specific_inventory_hybrid_held_robust_reset_20260910','1ebc48519970e0c272097c77f3ae755500a128b9',.00025),
}
CONTROL_CASES={'moderate_control','ode23t','robust_reset'}
ONE_STEP_CASES={'ode23t','robust_reset'}


def expected_solver(baseline,case):
    if case not in CASES:raise ValueError('Undeclared step experiment')
    result=dict(baseline)
    if case!='baseline':result['MaxStep']=format(CASES[case][2],'.17g')
    if case in ONE_STEP_CASES:result['Solver']='ode23t'
    return result


def expected_tolerances(baseline,case):
    if case not in CASES:raise ValueError('Undeclared tolerance experiment')
    return dict(RelTol='1e-6',AbsTol='1e-8') if case in CONTROL_CASES else dict(baseline)


def check_discrete_constitutive_blocks(callback,reset_method='Fast'):
    if reset_method not in ('Fast','Robust'):raise ValueError('Undeclared reset method')
    names=('SMA_TempDelay','SE_TempDelay','StateDelay')
    initials=('sma_constitutive_T21_initial','se_constitutive_T21_initial','constitutive_state21_initial')
    expected=[dict(path='heatdrive_ecc_coupled_se21/ECC_Constitutive21_'+name,block_type='UnitDelay',
        sample_time_expression='constitutive_sample_time_s',sample_time_s=.001,initial_condition_expression=initial)
        for name,initial in zip(names,initials)]
    if callback['constitutive_discrete_blocks']!=expected:raise ValueError('Constitutive memory or sampling changed')
    if callback['solver_iteration_options']!=dict(SolverResetMethod=reset_method,MaxOrder=5):
        raise ValueError('Unexpected additional solver-option change')


def check_robust_callbacks(current,previous):
    if len(current)!=3 or len(previous)!=3:raise ValueError('Incomplete reset trial callbacks')
    for new,old in zip(current,previous):
        expected=deepcopy(old);expected['AutoScaleAbsTol']='on'
        expected['solver_iteration_options']['SolverResetMethod']='Robust'
        if new!=expected:raise ValueError('Reset trial changed another runtime setting')


def audit(repo,case='baseline'):
    folder,producer,step=CASES[case]
    root=repo/'outputs_storage_audit'/folder
    path=root/'compiled_states_inspection.json';raw=root/'observations.mat';r=read(path)
    basepath=repo/'outputs_storage_audit/specific_inventory_hybrid_lag_actuation_initial_20260910/compiled_states_inspection.json';base=read(basepath)
    if sha256(basepath)!='336F1F98136D664830BEC1528101EB2DF678E3F967F08E37AB80D00160FB8A3D':raise ValueError('Initial baseline changed')
    if (r['inspector_commit']!=producer or not r['inspection_pass']
            or r['stage']!='complete' or not r['held_interval_requested'] or not r['external_lag_requested']
            or not r['simulation_run'] or r['initialization_only'] or r['diagnostic_stop_time_s']!=STOP_S
            or sha256(raw)!=r['observations_sha256'] or any(r[k] for k in
                ('c200_state_imported','failed_terminal_state_imported','production_recovery_allowed','checkpoint_saved'))):
        raise ValueError('Wrong held-interval experiment')
    expected=expected_solver(base['global_solver_configuration'],case)
    tolerances=expected_tolerances(base['global_tolerances_after'],case)
    if r['global_tolerances_after']!=tolerances:raise ValueError('Global error controls differ')
    if case in CONTROL_CASES:
        policy=dict(MinStepSizeMsg='error',MaxConsecutiveMinStep='1',MinStep='auto')
        if (not r['held_error_control_trial'] or r['held_error_control_level']!='moderate'
                or r['solver_failure_policy_after']!=policy
                or r['held_tight_control_rejection_sha256']!='0788BA8C9DC025CA20F61894581DE40E3CEF283EE75214AF6C4E2FCD4CAA5B50'):
            raise ValueError('Undeclared moderate-control provenance or failure policy')
    if r['global_solver_configuration']!=expected or (case!='baseline' and r['held_max_step_override_s']!=step):
        raise ValueError('Declared global maximum step differs')
    for key in ('consistency_settings_after',
                'runtime_solver_options_after','passive_ps_observer_contract','ps_initial_actuation_contract',
                'source_native_sha256','inventory_formulation'):
        if r[key]!=base[key]:raise ValueError('Changed initial assembly or physics: '+key)
    check_held_contract(r['held_interval_contract'])
    cb=r['runtime_callbacks']
    if [(c['stage'],c['simulation_status']) for c in cb]!=[('InitFcn','initializing'),('StartFcn','initializing'),('StopFcn','terminating')]:
        raise ValueError('Incomplete runtime callbacks')
    for c in cb:
        check_held_contract(c['held_interval_contract'])
        if c['global_solver_configuration']!=expected:raise ValueError('Actual callback maximum step differs')
        if {k:c[k] for k in tolerances}!=tolerances:raise ValueError('Actual callback tolerances differ')
        if case in CONTROL_CASES and c['solver_failure_policy']!=policy:raise ValueError('Actual failure action differs')
        if case in ONE_STEP_CASES:check_discrete_constitutive_blocks(c,'Robust' if case=='robust_reset' else 'Fast')
        if case!='baseline':
            sampling=dict(OutputOption='RefineOutputTimes',OutputTimes='[]',Refine='1',Decimation='1',SimscapeLogDecimation=1,SimscapeLogLimitData='off')
            if c['output_sampling_settings']!=sampling or r['output_sampling_settings']!=sampling:
                raise ValueError('Output sample settings differ')
        for key in ('targets','solver_settings','runtime_solver_options',
                    'LoadInitialState','has_private_data','external_controller_lag','passive_observer_solver','passive_observer_flow_input'):
            if c[key]!=base['runtime_callbacks'][0][key]:raise ValueError('Runtime setting changed: '+key)
        converter=c['pressure_converter']
        if (float(converter['StopTime'])!=STOP_S or converter['derivative_source']!=r['held_interval_contract']['derivative_source']
                or converter['value_source']!=base['runtime_callbacks'][0]['pressure_converter']['value_source']
                or converter['Unit']!='MPa' or converter['FilteringAndDerivatives']!='provide' or converter['UdotUserProvided']!='1'):
            raise ValueError('Actual held pressure interface differs')
    targetpath=repo/'outputs_storage_audit/conservative_buffer_coupled_cycle_20260909/conservative/public_inventory_targets.json'
    reference=read(targetpath);targets=reference['targets'];native=targetpath.parent.parent/'native/observations.mat'
    if len(targets)!=204 or sha256(native)!=reference['source_sha256']:raise ValueError('Cold reference changed')
    comparisons=coordinates(r['initial_coordinates'],targets);initial=summarize_coordinates(comparisons)
    tagged=[dict(block_name=t['block_name'],variable_name=t['variable_name'],**decode_tags(t)) for t in r['node_metadata']]
    inventory=component_inventory_preserved(tagged,CHAMBERS|BUFFERS)
    if not initial['strict_initial_coordinate_gate'] or not inventory or r['algebraic_structure']['loop_count']!=0:
        raise ValueError('Initial or structural prerequisite failed')
    results=[]
    with h5py.File(raw) as f:
        rows,t=sampled_rows(f,'native',1258);sources,ts=sampled_rows(f,'source_traces',162)
        if len({p for p,n in rows})!=119 or len({p for p,n in sources})!=49 or not np.array_equal(t,ts):
            raise ValueError('Incomplete storage/source boundary export')
        for name in sorted(CHAMBERS|BUFFERS):
            p='heatdrive_ecc_coupled_se21/'+name
            get=lambda n,u:scalar_series(rows[p,n],u)
            mf=get('mdot_A','kg/s');q=get('Phi_A','W')+get('Q_H','W')
            if name in CHAMBERS:mf=mf+get('mdot_B','kg/s');q=q+get('Phi_B','W')
            results.append(dict(block_path=p,**balance(t,get('stored_mass','kg'),get('stored_energy','J'),mf,q)))
        for name,value in [('cold_observer_pressure',-1e-6),('cold_observer_integral',0)]:
            s=f['signals/'+name];time=s['time_s'][:].ravel();values=s['values'][:].ravel()
            if not np.array_equal(time,t) or not np.isfinite(values).all() or np.max(abs(values-value))>1e-12:
                raise ValueError('Actual held pressure or integral changed')
    freeze_path=repo/'verification/c200_mainline_freeze_contract.json';freeze=read(freeze_path)
    files=[path,raw,basepath,targetpath,native,freeze_path,root/'compiled_state_dataset.mat',root/'matlab_diary.log']
    if case in CONTROL_CASES:
        prepath=root/'pre_simulation_inspection.json';pre=read(prepath)
        if pre['simulation_run'] or pre['global_tolerances_after']!=tolerances or pre['solver_failure_policy_after']!=policy:
            raise ValueError('Moderate-control pre-simulation configuration differs')
        rejected=repo/'outputs_storage_audit/hybrid_held_error_control_audit_20260910/held_error_control_audit.json'
        if sha256(rejected)!=r['held_tight_control_rejection_sha256']:raise ValueError('Tight-control evidence changed')
        files.extend([prepath,rejected])
        if case in ONE_STEP_CASES:
            ndf=repo/'outputs_storage_audit/hybrid_held_moderate_control_audit_20260910/held_interval_audit.json'
            if (r['held_solver_method']!='ode23t' or r['held_ndf_rejection_sha256']!=sha256(ndf)
                    or sha256(ndf)!='48ECCCA5D663B1F423CA838D5A84F7EECD9A74D59B4564079B4F941FC8E7A2F9'
                    or pre['global_solver_configuration']!=expected):
                raise ValueError('NDF comparison or actual solver declaration differs')
            files.append(ndf)
        if case=='robust_reset':
            diagnosis=repo/'outputs_storage_audit/hybrid_held_profiler_reset_association_audit_20260910/profiler_diagnostics_audit.json'
            prior_path=repo/'outputs_storage_audit/specific_inventory_hybrid_held_ode23t_after_restart_20260910/compiled_states_inspection.json'
            if (sha256(diagnosis)!='A7C46FF8CD4D6C611DFD1D8F30B2BA3EA6613FB0492D02F199A1E7DCC2C58732'
                    or r['reset_diagnostic_evidence_sha256']!=sha256(diagnosis)
                    or sha256(prior_path)!='32E1A6091A04A3150CBF6E23C101C65429E0D4B98181321A3EFA5ED29CFF352F'
                    or not r['held_robust_reset_requested'] or r['held_profiler_requested'] or r['held_split_tolerances']
                    or pre['solver_iteration_options']!=dict(SolverResetMethod='Robust',MaxOrder=5)
                    or r['solver_iteration_options']!=pre['solver_iteration_options']):
                raise ValueError('Undeclared reset trial or changed evidence')
            check_robust_callbacks(cb,read(prior_path)['runtime_callbacks'])
            files.extend([diagnosis,prior_path])
    for key in ('result','checkpoint'):
        p=repo/freeze[key+'_relative_path']
        if sha256(p)!=freeze[key+'_sha256']:raise ValueError('C200 changed')
        files.append(p)
    passed=sum(x['mass_closure_pass'] and x['energy_closure_pass'] for x in results)
    return dict(evidence_audit_pass=True,numerical_case=case,global_max_step_s=step,
                global_tolerances=tolerances,solver_failure_policy=r.get('solver_failure_policy_after'),
                output_sampling_settings=r.get('output_sampling_settings'),simulation_wall_seconds=r.get('simulation_wall_seconds'),
                solver_iteration_options=r.get('solver_iteration_options'),
                initial_coordinate_audit=initial,compiled_inventory_gate=inventory,
                compiled_algebraic_loops=0,observed_interval_s=[0,STOP_S],exported_sample_count=len(t),
                native_storage_count=119,native_leaf_count=1258,source_count=49,source_leaf_count=162,
                storage_components_with_local_balance_audited=6,passing_local_balances=passed,
                local_balances=results,local_balance_gate=passed==6,quadrature_convergence_verified=False,
                full_device_first_law_verified=False,active_feedback_transient_verified=False,
                production_recovery_allowed=False,table4_reproduction_claim=False,
                input_sha256={str(p.relative_to(repo)):sha256(p) for p in files}),comparisons


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output-root',type=Path,required=True)
    p.add_argument('--case',choices=CASES,default='baseline');args=p.parse_args()
    if args.output_root.exists():raise FileExistsError('Never overwrite evidence')
    result,rows=audit(Path(__file__).resolve().parents[1],args.case);args.output_root.mkdir(parents=True)
    (args.output_root/'held_interval_audit.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    with (args.output_root/'initial_coordinates.csv').open('x',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
    print(json.dumps({k:v for k,v in result.items() if k not in ('input_sha256','local_balances')},indent=2))
