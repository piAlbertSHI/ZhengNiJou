"""Audit the qualified cold nonlinear 40ms experiment without promoting its state."""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import h5py
import numpy as np
from Audit_HeatDriveECC_NonlinearColdInitial import build as initial_audit, target_translation
from Audit_HeatDriveECC_NonlinearMassProbe import reverse_source
from Audit_HeatDriveECC_ColdPassivePSObserver import read, sha256, CHAMBERS, BUFFERS
from Audit_HeatDriveECC_ColdCoordinateSmoke import compare_initial, scalar_series
from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_HybridHeldResult import sampled_rows
from Audit_HeatDriveECC_HeldIntervalBalance import balance, check_held_contract


def check_callbacks(current, initial, held):
    check_held_contract(held)
    if (held['state_imported'] or held['qualification_sha256']!='8598BB08D314EA1B052C5B4CCE9A9DD7F0E30BE6842E668A038306F58E298C13'
            or sha256(Path(held['qualification_path']))!=held['qualification_sha256']):
        raise ValueError('Held command qualification changed')
    captured={k:v for k,v in held.items() if k not in ('qualification_path','qualification_sha256','state_imported')}
    if len(current)!=3 or len(initial)!=3:
        raise ValueError('Missing runtime phases')
    for actual, prior in zip(current, initial):
        expected=deepcopy(prior)
        expected['pressure_converter']['StopTime']='0.04'
        expected['pressure_converter']['derivative_source']=held['derivative_source']
        expected['held_interval_contract']=captured
        if actual!=expected:
            raise ValueError('Runtime change beyond declared cold held window')


def coordinate_identity(time, saved, actual, nominal):
    t=np.asarray(saved['time_s'],dtype=float).ravel()
    data=np.asarray(saved['data'],dtype=float).ravel()
    actual=np.asarray(actual,dtype=float).ravel()
    if (saved['label']!='CSTATE' or not np.array_equal(t,time) or data.shape!=actual.shape
            or not np.isfinite(data).all() or not np.isfinite(nominal) or nominal<=0
            or not np.allclose(data*nominal,actual,rtol=1e-12,atol=1e-300)):
        raise ValueError('Saved normalized state does not match physical coordinate')
    return float(np.max(np.abs(data*nominal-actual)))


def audit(repo):
    proof=initial_audit(repo)
    if not proof['bounded_held_trial_eligible']:
        raise ValueError('Cold initial prerequisite failed independent re-audit')
    root=repo/'outputs_storage_audit'
    folder=root/'nonlinear_inventory_cold_held_20260910'
    path=folder/'compiled_states_inspection.json';r=read(path)
    initial_path=root/'nonlinear_inventory_cold_initial_20260910/compiled_states_inspection.json'
    initial=read(initial_path)
    if sha256(initial_path)!='D10DC35770D3B635DC975F17C4F529FB2CCCBBD187286E60C408F751BA6B55F9':
        raise ValueError('Cold initial record changed')
    if (r['inspector_commit']!='b316e6c1a8096d0309bdc43e95a0df015afd4da1' or not r['inspection_pass']
            or r['stage']!='complete' or r['simulation_error_message'] or r['diagnostic_stop_time_s']!=.04
            or r['initialization_only'] or not r['held_interval_requested'] or not r['nonlinear_inventory_requested']
            or not r['simulation_run'] or any(r[k] for k in ('production_recovery_allowed','checkpoint_saved',
                'c200_state_imported','failed_terminal_state_imported'))):
        raise ValueError('Wrong cold held experiment scope')
    strict=root/'nonlinear_cold_initial_strict_audit_20260910/nonlinear_cold_initial_audit.json'
    if sha256(strict)!=r['nonlinear_initial_qualification_sha256'] or sha256(strict)!='B78B380C37F30077A9189F8EFBBB3E9CB4B85C2413B1C07D21C9D15B591F2E66':
        raise ValueError('Strict initial qualification changed')
    contract=r['nonlinear_inventory_contract'];prior=initial['nonlinear_inventory_contract']
    if {k:v for k,v in contract.items() if k!='variants'}!={k:v for k,v in prior.items() if k!='variants'}:
        raise ValueError('Physical targets, scales, parameters or typed nets changed')
    target_translation(contract['physical_targets'],contract['runtime_targets'],contract['components'])
    if len(contract['variants'])!=2:raise ValueError('Missing component variant')
    for new,old in zip(contract['variants'],prior['variants']):
        ignored={'generated_source','library_path','library_sha256'}
        if {k:v for k,v in new.items() if k not in ignored}!={k:v for k,v in old.items() if k not in ignored}:
            raise ValueError('Generated source transformation differs')
        for field,hash_field in [('source','source_sha256'),('generated_source','generated_sha256'),('library_path','library_sha256')]:
            if sha256(Path(new[field]))!=new[hash_field]:raise ValueError('Source/library hash differs')
        reverse_source(Path(new['generated_source']).read_text(),Path(new['source']).read_text(),new['kind'],True)
    for k in ('global_solver_configuration','global_tolerances_after','consistency_settings_after',
              'runtime_solver_options_after','output_sampling_settings','solver_failure_policy_after',
              'solver_iteration_options','source_native_sha256','inventory_formulation'):
        if r[k]!=initial[k]:raise ValueError('Changed diagnostic configuration: '+k)
    check_callbacks(r['runtime_callbacks'],initial['runtime_callbacks'],r['held_interval_contract'])
    if r['cached_phase_targets']!=initial['cached_phase_targets'] or r['cached_extraction_added_callbacks']:
        raise ValueError('Cached initial targets changed')
    if r['algebraic_structure']['loop_count']!=0:raise ValueError('New algebraic loop')
    raw=folder/'observations.mat'
    if sha256(raw)!=r['observations_sha256']:raise ValueError('Observation hash differs')
    comparisons=[];identities=[];results=[];coordinate_reconstruction=[]
    with h5py.File(raw) as f,h5py.File(initial_path.parent/'observations.mat') as init:
        rows,t=sampled_rows(f,'native',1276);sources,ts=sampled_rows(f,'source_traces',162)
        if (set(rows)!=set(named_rows(init,init['native'])) or set(sources)!=set(named_rows(init,init['source_traces']))
                or not np.array_equal(t,ts) or len({p for p,n in rows})!=119 or len({p for p,n in sources})!=49):
            raise ValueError('Native or boundary coverage changed')
        reported={v['path']:v for v in r['initial_coordinates']}
        if len(reported)!=204:raise ValueError('Incomplete initial report')
        for target in contract['physical_targets']:
            actual=float(scalar_series(rows[target['block_path'],target['state_name']],target['unit'])[0])
            rr=reported[target['path']]
            if (rr['actual']!=actual or rr['expected']!=target['value'] or rr['priority']!=target['priority']
                    or rr['unit']!=target['unit'] or rr['source_time_s']!=0):raise ValueError('MAT/JSON initial mismatch')
            comparisons.append(dict(path=target['path'],**compare_initial(actual,target['value'])))
        saved=r['nonlinear_coordinate_states']
        if len(saved)!=12:raise ValueError('Missing coordinate histories')
        for c in contract['components']:
            p=c['block_path'];name=p.rsplit('/',1)[1]
            get=lambda n,u:scalar_series(rows[p,n],u)
            mass=get('stored_mass','kg');energy=get('stored_energy','J')
            for var,unit,nominal in [('mass_coordinate','1',c['mass_coordinate_nominal']),('energy_delta','J',c['energy_nominal_J'])]:
                matches=[s for s in saved if s['name']==p.replace('/','.')+'.'+var]
                if len(matches)!=1:raise ValueError('Duplicate or absent saved coordinate')
                error=coordinate_identity(t,matches[0],get(var,unit),nominal)
                identities.append(dict(block_path=p,name=var,nominal=nominal,max_abs_identity_error=error))
            reconstructed=c['mass_reference_kg']+c['mass_scale_kg']*np.sinh(get('mass_coordinate','1'))
            reconstructed_e=c['energy_reference_J']+get('energy_delta','J')
            if (np.any(abs(mass-reconstructed)>2*np.spacing(abs(mass)))
                    or np.any(abs(energy-reconstructed_e)>2*np.spacing(abs(energy)))):
                raise ValueError('Physical inventory not reconstructed within two float64 ulps')
            coordinate_reconstruction.append(dict(block_path=p,mass_error_kg=float(max(abs(mass-reconstructed))),
                energy_error_J=float(max(abs(energy-reconstructed_e)))))
            mf=get('mdot_A','kg/s');q=get('Phi_A','W')+get('Q_H','W')
            if name in CHAMBERS:mf=mf+get('mdot_B','kg/s');q=q+get('Phi_B','W')
            results.append(dict(block_path=p,**balance(t,mass,energy,mf,q)))
        for name,value in [('cold_observer_pressure',-1e-6),('cold_observer_integral',0)]:
            s=f['signals/'+name];values=s['values'][()].ravel()
            if (not np.array_equal(s['time_s'][()].ravel(),t) or not np.isfinite(values).all()
                    or max(abs(values-value))>1e-12):raise ValueError('Held observer signal changed')
    initial_pass=all(x['within_strict_comparison'] for x in comparisons)
    if not initial_pass:raise ValueError('Physical initial target failure')
    passed=sum(x['mass_closure_pass'] and x['energy_closure_pass'] for x in results)
    files=[dict(path=str(p.relative_to(repo)),bytes=p.stat().st_size,sha256=sha256(p))
           for p in sorted(folder.rglob('*')) if p.is_file()]
    return dict(evidence_audit_pass=True,strict_initial_coordinate_gate=initial_pass,strict_matching_count=len(comparisons),
        initial_comparisons=comparisons,coordinate_identity=identities,coordinate_reconstruction=coordinate_reconstruction,
        initial_qualification_sha256=sha256(strict),producer=r['inspector_commit'],simulation_exit_code=0,
        simulation_call_wall_seconds=r['simulation_wall_seconds'],compiled_algebraic_loops=0,
        observed_interval_s=[0,.04],exported_sample_count=len(t),native_leaf_count=1276,boundary_leaf_count=162,
        audited_storage_components=6,passing_mass_balances=sum(x['mass_closure_pass'] for x in results),
        passing_energy_balances=sum(x['energy_closure_pass'] for x in results),passing_joint_balances=passed,
        local_balances=results,local_balance_gate=passed==6,quadrature_convergence_verified=False,
        full_device_first_law_verified=False,periodic_state_audited=False,full_solver_error_weights_verified=False,
        production_recovery_allowed=False,table4_reproduction_claim=False,files=files,
        evidence_file_count=len(files),evidence_bytes=sum(x['bytes'] for x in files),deleted_files=0,
        large_raw_or_checkpoint_duplicated=False)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-root',required=True,type=Path);args=parser.parse_args()
    if args.output_root.exists():raise FileExistsError('Never overwrite evidence')
    result=audit(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'nonlinear_cold_held_audit.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('initial_comparisons','coordinate_identity','files')},indent=2))
