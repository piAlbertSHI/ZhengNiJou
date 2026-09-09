"""Preserve accepted initialization and rejected finite-window balance evidence."""
import argparse
import csv
import json
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


def audit(repo):
    root=repo/'outputs_storage_audit/specific_inventory_hybrid_held_interval_20260910_v2'
    path=root/'compiled_states_inspection.json';raw=root/'observations.mat';r=read(path)
    basepath=repo/'outputs_storage_audit/specific_inventory_hybrid_lag_actuation_initial_20260910/compiled_states_inspection.json';base=read(basepath)
    if sha256(basepath)!='336F1F98136D664830BEC1528101EB2DF678E3F967F08E37AB80D00160FB8A3D':raise ValueError('Initial baseline changed')
    if (r['inspector_commit']!='f01ab7c28f8e85b561f5610301e7f1fdc5183141' or not r['inspection_pass']
            or r['stage']!='complete' or not r['held_interval_requested'] or not r['external_lag_requested']
            or not r['simulation_run'] or r['initialization_only'] or r['diagnostic_stop_time_s']!=STOP_S
            or sha256(raw)!=r['observations_sha256'] or any(r[k] for k in
                ('c200_state_imported','failed_terminal_state_imported','production_recovery_allowed','checkpoint_saved'))):
        raise ValueError('Wrong held-interval experiment')
    for key in ('global_tolerances_after','global_solver_configuration','consistency_settings_after',
                'runtime_solver_options_after','passive_ps_observer_contract','ps_initial_actuation_contract',
                'source_native_sha256','inventory_formulation'):
        if r[key]!=base[key]:raise ValueError('Changed initial assembly or physics: '+key)
    check_held_contract(r['held_interval_contract'])
    cb=r['runtime_callbacks']
    if [(c['stage'],c['simulation_status']) for c in cb]!=[('InitFcn','initializing'),('StartFcn','initializing'),('StopFcn','terminating')]:
        raise ValueError('Incomplete runtime callbacks')
    for c in cb:
        check_held_contract(c['held_interval_contract'])
        for key in ('targets','solver_settings','global_solver_configuration','RelTol','AbsTol','runtime_solver_options',
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
    for key in ('result','checkpoint'):
        p=repo/freeze[key+'_relative_path']
        if sha256(p)!=freeze[key+'_sha256']:raise ValueError('C200 changed')
        files.append(p)
    passed=sum(x['mass_closure_pass'] and x['energy_closure_pass'] for x in results)
    return dict(evidence_audit_pass=True,initial_coordinate_audit=initial,compiled_inventory_gate=inventory,
                compiled_algebraic_loops=0,observed_interval_s=[0,STOP_S],exported_sample_count=len(t),
                native_storage_count=119,native_leaf_count=1258,source_count=49,source_leaf_count=162,
                storage_components_with_local_balance_audited=6,passing_local_balances=passed,
                local_balances=results,local_balance_gate=passed==6,quadrature_convergence_verified=False,
                full_device_first_law_verified=False,active_feedback_transient_verified=False,
                production_recovery_allowed=False,table4_reproduction_claim=False,
                input_sha256={str(p.relative_to(repo)):sha256(p) for p in files}),comparisons


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output-root',type=Path,required=True);args=p.parse_args()
    if args.output_root.exists():raise FileExistsError('Never overwrite evidence')
    result,rows=audit(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'held_interval_audit.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    with (args.output_root/'initial_coordinates.csv').open('x',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
    print(json.dumps({k:v for k,v in result.items() if k not in ('input_sha256','local_balances')},indent=2))
