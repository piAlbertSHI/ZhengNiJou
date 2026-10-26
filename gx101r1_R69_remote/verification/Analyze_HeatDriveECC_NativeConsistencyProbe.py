"""Compare unchanged native CV physics under tighter nonlinear consistency.

This is a short fresh-cold numerical experiment, not OP recovery, phase-law
calibration, a periodicity gate or permission to use a failed continuation.
"""
import argparse
import json
from pathlib import Path

import numpy as np

from Analyze_HeatDriveECC_CoupledCVBalance import load_case,native_value,native_sum,path_steps,storage,sources,balance_window
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_NativeWindowLedger import validate_grid
from Review_HeatDriveECC_CoupledCVPacket import verify_sources,verify_arm
from Run_HeatDriveECC_ConservativeTransport import write_json


def require_equal(a,b,path,unknown=None):
    if isinstance(a,dict):
        if not isinstance(b,dict) or set(a)!=set(b):raise ValueError('Physical field coverage differs: '+path)
        for k in a:require_equal(a[k],b[k],path+'.'+k,unknown)
    elif isinstance(a,(list,np.ndarray)):
        x,y=np.asarray(a),np.asarray(b)
        if x.shape!=y.shape:raise ValueError('Physical array shape differs: '+path)
        for i in np.ndindex(x.shape):require_equal(x[i],y[i],path+str(i),unknown)
    elif isinstance(a,(float,np.floating)) and np.isnan(a):
        if not isinstance(b,(float,np.floating)) or not np.isnan(b):raise ValueError('Only one field is unidentified: '+path)
        if unknown is not None:unknown.append(path)
    elif a!=b:raise ValueError('Physical value differs: '+path)


def same_cycle_schedule(a,b,count_a,count_b):
    a,b=dict(a),dict(b)
    horizons={'reference_s':a.pop('total_time_s'),'experiment_s':b.pop('total_time_s')}
    if horizons['reference_s']!=count_a*a['tau_cycle_s'] or horizons['experiment_s']!=count_b*b['tau_cycle_s']:
        raise ValueError('Unexplained schedule horizon, not the declared generated cycle count')
    require_equal(a,b,'schedule')
    return horizons


def active_materials_finite(options):
    used=('rho_kg_per_m3','cp_J_per_kgK','E_m_Pa','epsilon_T','T_As_K','T_Ms_K',
          'C_A_Pa_per_K','C_M_Pa_per_K','Delta_h_J_per_kg')
    for part in ('SMA','SE'):
        if not all(np.isfinite(float(options['material'][part][k])) for k in used):
            raise ValueError('An active material parameter is not identified')


def require_numerical_change(contract):
    if contract['profile']!='local_tight' or contract['old_OP_loaded'] or contract['production_recovery_allowed']:
        raise ValueError('Not a fresh numerical-only diagnostic')
    allowed={'ConsistencyTolSource','ConsistencyAbsTol','ConsistencyRelTol','ResidualTolerance'}
    before,after=contract['before'],contract['after']
    if set(before)!=set(after):raise ValueError('Solver coverage changed')
    changed={k for k in before if before[k]!=after[k]}
    if not changed or not changed<=allowed:raise ValueError('Changed solver, step, or unrelated setting')
    if after['ConsistencyTolSource']!='LOCAL' or float(after['ConsistencyRelTol'])!=1e-9 or float(after['ConsistencyAbsTol'])!=1e-12 or float(after['ResidualTolerance'])!=1e-12:
        raise ValueError('Wrong declared tighter consistency')
    return sorted(changed)


def tank_defect(data,path,stop):
    n=round(stop/.001);time=data['time'][:n+1];validate_grid(time,0,stop,.001)
    v=lambda name,unit:native_value(data,path,name,unit)[:n+1]
    T=v('T_I','K');P=v('p_I','Pa');M=v('mass','kg');rho=v('rho_I','kg/m^3');V=v('volume','m^3');h=v('h_I','J/kg')
    cp=data['tables'][data['assignment'][path]]['cp'](np.column_stack((T,P)))
    power=(native_sum(data['native'],path,'Phi_','W')+native_value(data,path,'Q_H','W'))[:n+1]
    dt=np.diff(time);dT=np.diff(T);dM=np.diff(M)
    defect=dt*power[1:]-path_steps(M*cp,T)-path_steps(h,M)
    rates=defect/dt;active=abs(dT)>1e-8
    implied=np.divide(dt*power[1:]-h[1:]*dM,M[1:]*dT,out=np.full_like(dT,np.nan),where=active)
    return dict(samples=len(time),end_s=stop,mass_minus_rhoV_max_abs_kg=float(abs(M-rho*V).max()),
                coefficient_BE_net_defect_J=float(defect.sum()),cumulative_defect_max_abs_J=float(abs(np.cumsum(defect)).max()),
                instantaneous_equation_defect_RMS_W=float(np.sqrt(np.mean(rates*rates))),
                delta_T_max_abs_K=float(abs(dT).max()),
                implied_cp_to_lookup_cp_median=float(np.median(implied[active]/cp[1:][active])) if active.any() else None,
                implied_cp_is_diagnostic_not_a_parameter_fit=True)


def analyze(reference,experiment,output):
    read=lambda root:json.loads((root/'coupled_CV_execution.json').read_text(encoding='utf-8'))
    old,new=read(reference),read(experiment);duration=new['stop_time_s']
    if not (duration in (.01,.2) and old['stop_time_s']==20 and new['collection_complete'] and old['collection_complete']):
        raise ValueError('Require complete cold prefix and complete reference C2')
    if new['checkpoint_loaded_or_saved'] or old['checkpoint_loaded_or_saved']:raise ValueError('No OP comparisons in this probe')
    verify_sources(old);verify_sources(new)
    c_old=next(c for c in old['completed_arms'] if c['arm']=='shared')
    if len(new['completed_arms'])!=1 or new['completed_arms'][0]['arm']!='shared':raise ValueError('Require one fresh shared-bed arm')
    c_new=new['completed_arms'][0]
    cov_old=verify_arm(reference,c_old,20);cov_new=verify_arm(experiment,c_new,duration)
    a=load_case(reference,c_old);b=load_case(experiment,c_new)
    require_equal(a['contract']['storage_blocks'],b['contract']['storage_blocks'],'native_inventory')
    require_equal(a['contract']['settings_tables'],b['contract']['settings_tables'],'fluid_properties')
    unidentified=[]
    for group in ('system','fluid','geometry','material','equilibrium','solid','constitutive'):
        require_equal(a['options'][group],b['options'][group],group,unidentified)
    active_materials_finite(a['options']);active_materials_finite(b['options'])
    horizons=same_cycle_schedule(a['options']['schedule'],b['options']['schedule'],a['options']['cycle_count'],b['options']['cycle_count'])
    controller_fields=[]
    for k,value in a['options']['branch'].items():
        if 'pressure' in k and isinstance(value,(str,int,float,bool,np.number)):
            require_equal(value,b['options']['branch'][k],'branch.'+k);controller_fields.append(k)
    changed=require_numerical_change(b['contract']['numerical_solver_contract'])
    command_checks={}
    from Review_HeatDriveECC_CoupledCVPacket import on_grid
    clock=b['time']
    for name in ('diagnostic_original_hold_G','diagnostic_original_cooldown_G','diagnostic_shared_max_G'):
        require_equal(on_grid(a['workspace'][a['model'],name],clock),on_grid(b['workspace'][b['model'],name],clock),name)
        command_checks[name]=True
    initial={}
    for key,row in a['native'].items():
        if key[1] not in {'T_I','p_I','u_I','rho_I','mass','volume','T'}:continue
        other=b['native'][key]
        if row['unit']!=other['unit']:raise ValueError('Native unit changed')
        initial[row['unit']]=max(initial.get(row['unit'],0.),float(abs(row['values'][0]-other['values'][0]).max()))
    tanks=[]
    for block in a['contract']['storage_blocks']:
        if block['mask_type']!='Tank (TL)':continue
        path=block['block_path'];tanks.append(dict(block_path=path,reference=tank_defect(a,path,duration),tight=tank_defect(b,path,duration)))
    output.mkdir(parents=True,exist_ok=False)
    result=dict(schema='heatdrive_ecc_native_consistency_comparison_v1',reference_root=str(reference),experiment_root=str(experiment),
                reference_execution_sha256=sha256(reference/'coupled_CV_execution.json'),
                experiment_execution_sha256=sha256(experiment/'coupled_CV_execution.json'),reader_sha256=sha256(Path(__file__)),
                reference_coverage=cov_old,experiment_coverage=cov_new,numerical_contract=b['contract']['numerical_solver_contract'],
                unchanged_physical_inventory_and_parameter_contract=True,unchanged_pressure_controller_fields=sorted(controller_fields),
                matching_unidentified_metadata_not_material_validation=unidentified,
                generated_schedule_horizons=horizons,original_thermal_command_prefix_exactly_equal=command_checks,
                changed_numerical_parameters=changed,initial_measured_state_difference_max_by_native_unit=initial,
                complete_hidden_initial_state_equality_claimed=False,tanks=tanks,
                reference_balance=balance_window(a,storage(a),sources(a),0,duration),
                tight_balance=balance_window(b,storage(b),sources(b),0,duration),
                full_mechanism_periodic_Table4_or_production_recovery_qualified=False)
    write_json(output/'native_consistency_comparison.json',result)
    print(json.dumps({'output':str(output),'tanks':len(tanks),'physical_parameters_unchanged':True,'performance_qualified':False}))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('reference','experiment','output'):p.add_argument('--'+name,type=Path,required=True)
    args=p.parse_args();analyze(args.reference.resolve(),args.experiment.resolve(),args.output.resolve())
