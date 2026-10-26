"""Read continuous C2 trajectories without promoting coverage to validation.

Native BE pipe/thermal-mass ledgers are separated from variable-inventory
coefficient/endpoint diagnostics. No recovered state or new gate is produced.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from scipy.io import loadmat

from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_NativeWindowLedger import evaluate_component
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_TLDomainInventory import density_table, resolve_domains
from HeatDriveECC_TraceColumns import load
from Review_HeatDriveECC_CoupledCVPacket import on_grid, verify_arm, verify_sources
from Run_HeatDriveECC_ConservativeTransport import write_json


def right_integral(time, values):
    return float(np.dot(np.diff(time), np.asarray(values)[1:]))


def be_residual(time, energy, power):
    return energy-energy[0]-np.r_[0.,np.cumsum(np.diff(time)*power[1:])]


def geometric_value(parameter,unit):
    if parameter['unit']!=unit:raise ValueError('Unreviewed geometric unit')
    value=float(parameter['value'])
    if not np.isfinite(value) or value<=0:raise ValueError('Invalid native geometry')
    return value


def difference_stats(values, shift):
    if len(values)!=2*shift+1:
        raise ValueError('Require a continuous, complete C2 record')
    d=values[shift:]-values[:shift+1]
    return {'endpoint_max_abs':float(abs(d[-1]).max()),
            'same_phase_max_abs':float(abs(d).max()),
            'same_phase_p99_abs':float(np.percentile(abs(d),99)),
            'same_phase_RMS':float(np.sqrt(np.mean(d*d)))}


def stage_coordinates(time,options):
    """Same endpoint ownership as HeatDriveECC_CycleStageFromTime.m."""
    schedule=options['schedule'];tau=schedule['tau_cycle_s'];count=options['cycle_count']
    cycle=np.minimum(np.maximum(np.floor(time/tau)+1,1),count).astype(int)
    local=time-(cycle-1)*tau
    local[time>=count*tau-10*np.spacing(max(count*tau,1.))]=tau
    starts=np.asarray(schedule['stage_start_s']).ravel();ends=np.asarray(schedule['stage_end_s']).ravel()
    stage=np.full(time.size,4);elapsed=np.zeros_like(time)
    for k in range(4):
        mask=(local>=starts[k])&(local<(ends[k]) if k<3 else local<=ends[k]+np.spacing(tau))
        stage[mask]=k+1;elapsed[mask]=local[mask]-starts[k]
    return cycle,stage,elapsed


def flow_metrics(values,target,mask,sign,instant_limit,rms_limit=None):
    x=np.asarray(values)[mask]
    if x.size==0:raise ValueError('Empty settled-flow window')
    error=abs(x)/target-1
    row={'samples':int(x.size),'signed_min_max_kg_s':[float(x.min()),float(x.max())],
         'max_abs_relative_error':float(abs(error).max()),'RMS_relative_error':float(np.sqrt(np.mean(error*error))),
         'instantaneous_limit':float(instant_limit),'direction_pass':bool(np.all(sign*x>0)),
         'instantaneous_target_pass':bool(np.max(abs(error))<=instant_limit)}
    if rms_limit is not None:
        row.update(RMS_limit=float(rms_limit),RMS_target_pass=bool(row['RMS_relative_error']<=rms_limit))
    return row


def arm_observations(root, case):
    folder=root/case['arm']
    contract=json.loads((folder/'CV_contract.json').read_text(encoding='utf-8'))
    tl=json.loads((folder/'CV_tl_topology.json').read_text(encoding='utf-8'))
    options=loadmat(folder/'CV_options.mat',simplify_cells=True)['options']
    if (options['simscape']['local_solver_choice']!='NE_BACKWARD_EULER_ADVANCER'
            or not options['simscape']['local_solver_enabled']
            or options['simscape']['local_solver_sample_time_s']!=.001):
        raise ValueError('The fixed 1 ms BE ledger is not applicable to this solver')
    native=load(folder/'native_CV_observations.mat')
    workspace=load(folder/'workspace_CV_observations.mat')
    sources=load(folder/'source_CV_observations.mat')
    model=contract['storage_paths'][0].split('/')[0]
    time=native[next(iter(native))]['time_s']
    assignment,_=resolve_domains(tl)
    parameters={r['block_path']:r['parameters'] for r in contract['settings_tables']}
    tables={p:energy_tables(v) for p,v in parameters.items()}

    def value(path,name,unit):
        row=native[path,name]
        if not np.array_equal(row['time_s'],time):raise ValueError('Native clock mismatch')
        return convert(row['values'][:,0],row['unit'],unit)

    def signal(name):
        return on_grid(workspace[model,name],time)

    rows=[];temperatures=[];pipe_energy=np.zeros_like(time)
    for block in contract['storage_blocks']:
        path=block['block_path'];kind=block['mask_type']
        temp=value(path,'T' if kind=='Thermal Mass' else 'T_I','K')
        temperatures.append(temp)
        row={'block_path':path,'mask_type':kind,'T_min_max_K':[float(temp.min()),float(temp.max())]}
        if kind!='Thermal Mass':
            pressure=value(path,'p_I','Pa')
            row['settings_path']=assignment[path]
            row['p_min_max_Pa']=[float(pressure.min()),float(pressure.max())]
        if kind in ('Pipe (TL)','Thermal Mass'):
            if kind=='Pipe (TL)':
                modes=block['model_modes'];p=block['mask_parameters']
                if modes['dynamic_compressibility']!='false':raise ValueError('Unreviewed pipe storage mode')
                rho=float(density_table(parameters[assignment[path]])([[float(convert(float(modes['T_nominal']),modes['T_nominal_unit'],'K')),
                    float(convert(float(modes['p_nominal']),modes['p_nominal_unit'],'Pa'))]])[0])
                volume=geometric_value(p['area'],'m^2')*geometric_value(p['length'],'m')
                mass=rho*volume;energy=mass*value(path,'u_I','J/kg')
                power=value(path,'Phi_A','W')+value(path,'Phi_B','W')+value(path,'Q_H','W')
                row['constant_native_mass_kg']=mass
                row['mass_port_sum_max_kg_s']=float(abs(value(path,'mdot_A','kg/s')+value(path,'mdot_B','kg/s')).max())
                pipe_energy+=energy-energy[0]
            else:
                p=block['mask_parameters'];mass=float(convert(p['mass']['value'],p['mass']['unit'],'kg'))
                cp=float(convert(p['sp_heat']['value'],p['sp_heat']['unit'],'J/(K*kg)'))
                energy=mass*cp*temp;power=value(path,'Q','W')
            row.update(BE_energy_residual_max_J=float(abs(be_residual(time,energy,power)).max()),
                       energy_change_J=float(energy[-1]-energy[0]),net_port_energy_BE_J=right_integral(time,power),
                       basis='actual right-endpoint 1 ms BE samples; fixed native accumulation')
        else:
            leaves=[{'name':n,'time_s':r['time_s'],'values':r['values'][:,0],'unit':r['unit']}
                    for (p,n),r in native.items() if p==path]
            diagnostic=evaluate_component(dict(block,leaf_variables=leaves),tables[assignment[path]])
            row['variable_inventory_diagnostic']=diagnostic
            row['basis']='coefficient-path trapezoid and endpoint diagnostics; not a BE conservation gate'
        rows.append(row)
    phase=signal('ECC_constitutive21_output')
    if phase.shape!=(20001,252):raise ValueError('Re-review constitutive output layout')
    phase=phase[:,42:84]
    temps=np.column_stack(temperatures)
    memories={r['workspace_variable']:signal(r['workspace_variable']) for r in contract['PI_memory_probes']}
    pumps=[]
    for short in ('sma','se_stage2','se_stage4'):
        probes=[p for p in contract['pump_pressure_contract']['probes']
                if p['workspace_variable']=='pump_pressure_'+short+'_port_a_MPa']
        if len(probes)!=1:raise ValueError('Ambiguous pump source')
        block=probes[0]['source_block']
        path=model+'/'+block
        a=signal('pump_pressure_'+short+'_port_a_MPa')[:,0]*1e6
        b=signal('pump_pressure_'+short+'_port_b_MPa')[:,0]*1e6
        q=sources[path,'q_A'];q=on_grid(q,time)[:,0]
        if q.size!=time.size or sources[path,'q_A']['unit']!='m^3/s':raise ValueError('Pump volume-flow unit changed')
        w=(b-a)*q
        pumps.append({'source':path,'pressure_rise_min_max_Pa':[float((b-a).min()),float((b-a).max())],
                      'signed_hydraulic_work_J':right_integral(time,w),
                      'positive_hydraulic_work_J':right_integral(time,np.maximum(w,0)),
                      'negative_hydraulic_work_J':right_integral(time,np.minimum(w,0)),
                      'engineering_work_not_electrical_input':True})
    drift=difference_stats(temps,10000);v=options['validation']
    drift['endpoint_screen_pass']=drift['endpoint_max_abs']<=v['max_periodic_endpoint_drift_K']
    drift['same_phase_screen_pass']=drift['same_phase_max_abs']<=v['max_periodic_same_phase_temperature_drift_K']
    cycle,stage,elapsed=stage_coordinates(time,options)
    durations=np.asarray(options['schedule']['stage_durations_s']).ravel()[stage-1]
    guard=options['branch']['stage_command_ramp_s']
    core=(cycle>=v['mechanism_gate_start_cycle'])&(elapsed>=guard)&(elapsed<=durations-guard)
    b=options['branch'];flow=[]
    target_sma=(b['m_dot_sma_shex_kg_per_s']+b['m_dot_sma_the_kg_per_s'])/2
    target_se=(b['m_dot_se_the_kg_per_s']+b['m_dot_se_chex_kg_per_s'])/2
    for number in (1,2):
        row={'cycle':number,'SMA':flow_metrics(signal('mass_flow_sma_stage13_kgps')[:,0],target_sma,
                core&(cycle==number)&(elapsed>=1.),-1,v['max_sma_settled_flow_relative_error'])}
        for s,name in ((2,'mass_flow_v1_cold_inlet_kgps'),(4,'mass_flow_v4_hot_inlet_kgps')):
            row['SE_stage'+str(s)]=flow_metrics(signal(name)[:,0],target_se,
                core&(cycle==number)&(stage==s)&(elapsed>=v['se_settled_guard_s']+max(options['simulation']['fixed_step_s'],np.finfo(float).eps)),
                1,v['max_se_settled_flow_relative_error'],v['max_se_settled_flow_rms_relative_error'])
        flow.append(row)
    return {'arm':case['arm'],'native_components':rows,'all_native_temperature_C2_drift_K':drift,
            'settled_flow_original_thresholds':flow,
            'phase_C2_drift':difference_stats(phase,10000),
            'phase_bounds_pass':bool(np.all((phase>=-1e-9)&(phase<=1+1e-9))),
            'route_memory_C2_drift':{k:difference_stats(x,10000) for k,x in memories.items()},
            'pumps':pumps,'complete_mechanism_periodic_first_law_or_Table4_qualified':False,
            'remaining_coverage':['topology-aware full mechanism gates','global external CV source ledger',
                                  'variable-inventory physical endpoint closure','Eq9/Eq10 windows and mass basis',
                                  'complete hidden-state periodicity']}, {
                'time':time,'mean_SMA':signal('SMA_Tx21_internal').mean(axis=1),
                'mean_SE':signal('SE_Tx21_internal').mean(axis=1),'pipe_energy':pipe_energy,
                'phase_SE':phase[:,21:].mean(axis=1)}


def analyze(root,output):
    e=json.loads((root/'coupled_CV_execution.json').read_text(encoding='utf-8'))
    if e['stop_time_s']!=20 or not e['collection_complete'] or e['checkpoint_loaded_or_saved']:
        raise ValueError('Require complete continuous fresh C2, not a concatenation or restore')
    verify_sources(e)
    coverage=[verify_arm(root,c,20) for c in e['completed_arms']]
    arms=[];curves={}
    for case in e['completed_arms']:
        result,curve=arm_observations(root,case);arms.append(result);curves[case['arm']]=curve
    output.mkdir(parents=True,exist_ok=False)
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig,axes=plt.subplots(2,2,figsize=(10,7),layout='constrained')
    for arm,c in curves.items():
        color='#666666' if arm=='dual' else '#007A78'
        for ax,key in zip(axes.ravel(),('mean_SMA','mean_SE','pipe_energy','phase_SE')):
            ax.plot(c['time'],c[key],label=arm,color=color,lw=1)
    for ax,title,unit in zip(axes.ravel(),('SMA solid mean','SE solid mean','All native pipe stored-energy change','SE mean martensite fraction'),('K','K','J','1')):
        ax.set(title=title,xlabel='Time (s)',ylabel=unit,xlim=(0,20));ax.axvline(10,color='#999999',ls=':',lw=.8)
        ax.spines[['top','right']].set_visible(False);ax.legend(frameon=False)
    fig.suptitle('Continuous cold C2: diagnostic, not periodic performance',fontsize=11)
    fig.savefig(output/'coupled_CV_C2.png',dpi=200);plt.close(fig)
    result={'schema':'heatdrive_ecc_coupled_C2_trajectory_review_v1','producer_commit':e['execution_commit'],
            'reader_sha256':sha256(Path(__file__)),'execution_sha256':sha256(root/'coupled_CV_execution.json'),
            'coverage':coverage,'arms':arms,'twenty_cycle_seed_or_recovery_allowed':False,
            'figure_sha256':sha256(output/'coupled_CV_C2.png')}
    write_json(output/'coupled_CV_C2_review.json',result)
    print(json.dumps({'output':str(output),'arms':len(arms),'qualified_for_performance':False}))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();analyze(args.root.resolve(),args.output.resolve())
