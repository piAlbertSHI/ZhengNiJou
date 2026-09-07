"""Independent one-cycle diagnostics; never infer ten-cycle or Table 4 approval."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Segments import audit as segment_audit
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def load_signals(root):
    combined={}
    for index in range(1,4):
        folder=root/f'nominal_s{index:02d}'
        audited=segment_audit(folder,root/f'nominal_s{index-1:02d}' if index>1 else None)
        if not audited['data_audit_pass']:
            raise ValueError('Segment data audit failed')
        with h5py.File(folder/f'segment_{index:02d}.mat') as f:
            for name,row in f['signals'].items():
                first_step,last_step={1:(0,4000),2:(4000,8000),3:(8000,10000)}[index]
                if not np.array_equal(row['time_s'][:].reshape(-1),2000+np.arange(first_step,last_step+1)*.001):
                    raise ValueError('Actual signal time differs from the integration grid')
                values=row['values'][:]
                combined.setdefault(name,[]).append(values if index==1 else values[:,1:])
    return {name:np.concatenate(parts,axis=1) for name,parts in combined.items()}


def phase_axes(time):
    phase=np.asarray(time)-2000
    stage=np.minimum(np.searchsorted([3.5,5,8.5,10],phase,side='right')+1,4)
    elapsed=phase-np.array([0,3.5,5,8.5])[stage-1]
    return stage,elapsed


def metrics(signals, options, time):
    scalar=lambda path:float(options[path][0,0])
    stage,elapsed=phase_axes(time)
    mean=lambda value:float(np.trapezoid(value,time)/10)
    q=signals['mass_flow_v4_hot_inlet_kgps'][0]
    hot=signals['hot_hx_inlet_fluid_temp_out'][0]
    cold=signals['cold_hx_inlet_fluid_temp_out'][0]
    inlet=signals['cold_hx_outlet_fluid_temp_out'][0]
    power=abs(q)*(stage==4)*scalar('system/cp_fluid_J_per_kgK')*(cold-inlet)
    performance=dict(window_start_s=2000,window_stop_s=2010,window_cycles=1,
                     SE_mass_g=1000*scalar('equilibrium/m_r_kg'),cp_fluid_J_kgK=scalar('system/cp_fluid_J_per_kgK'),
                     outlet_lift_mean_K=mean(hot-cold),cooling_power_W=mean(power),
                     SCP_W_g=mean(power)/(1000*scalar('equilibrium/m_r_kg')),
                     CHEX_heat_sensor_mean_W=mean(signals['Qdot_cold_sink_mass_to_hx_pipe_W'][0]),
                     ten_cycle_Qian_window_verified=False)
    constitutive=signals['ECC_constitutive21_output']
    solids={}
    for name,offset in [('SMA',42),('SE',63)]:
        phase=constitutive[offset:offset+21]
        temp=signals[name+'_Tx21_internal'].mean(axis=0)
        mass=scalar('equilibrium/m_a_kg' if name=='SMA' else 'equilibrium/m_r_kg')
        capacity=mass*scalar('material/'+name+'/cp_J_per_kgK')
        q_const=signals['ECC_Q_'+name+'_constitutive_W'].sum(axis=0)
        routes=['hold','cooldown'] if name=='SMA' else ['hold']
        q_pipe=sum(signals[f'{name.lower()}_{route}_node{n:02d}_heatflow_W'][0] for route in routes for n in range(1,22))
        stored=capacity*(temp[-1]-temp[0])
        exchanged=float(np.trapezoid(q_pipe,time))
        constitutive_J=float(np.trapezoid(q_const,time))
        residual=float(stored-exchanged-constitutive_J)
        relative=abs(residual)/max(abs(stored),abs(exchanged),abs(constitutive_J),1)
        phase_mean=phase.mean(axis=0)
        solids[name]=dict(capacity_J_K=capacity,delta_sensible_U_J=float(stored),pipe_input_J=exchanged,
                          constitutive_input_J=constitutive_J,residual_J=residual,residual_fraction=relative,
                          limit=scalar('validation/max_energy_residual_fraction'),
                          selected_solid_energy_gate=relative<=scalar('validation/max_energy_residual_fraction'),
                          mean_phase_min=float(phase_mean.min()),mean_phase_max=float(phase_mean.max()),
                          mean_phase_swing=float(np.ptp(phase_mean)),all_node_phase_min=float(phase.min()),all_node_phase_max=float(phase.max()))
    flows=[]
    ramp=scalar('branch/stage_command_ramp_s')
    durations=np.array([3.5,1.5,3.5,1.5])
    core=(elapsed>=ramp)&(elapsed<=durations[stage-1]-ramp)
    for phase in range(1,5):
        mask=core&(stage==phase)&(elapsed>=1)
        target=(scalar('branch/m_dot_sma_shex_kg_per_s')+scalar('branch/m_dot_sma_the_kg_per_s'))/2
        flow=signals['mass_flow_sma_stage13_kgps'][0,mask]
        if flow.size==0:
            raise ValueError('Empty SMA settled window')
        error=abs(flow)/target-1
        flows.append(dict(component='SMA',stage=phase,target_kg_s=target,samples=len(flow),
                          mean_signed_kg_s=float(flow.mean()),max_abs_relative_error=float(abs(error).max()),
                          selected_flow_gate=bool(np.max(abs(error))<=scalar('validation/max_sma_settled_flow_relative_error'))))
    for phase,name in [(2,'mass_flow_v1_cold_inlet_kgps'),(4,'mass_flow_v4_hot_inlet_kgps')]:
        mask=core&(stage==phase)&(elapsed>=scalar('validation/se_settled_guard_s')+.001)
        target=(scalar('branch/m_dot_se_the_kg_per_s')+scalar('branch/m_dot_se_chex_kg_per_s'))/2
        flow=signals[name][0,mask]
        if flow.size==0:
            raise ValueError('Empty SE settled window')
        error=abs(flow)/target-1
        rms=float(np.sqrt(np.mean(error**2)))
        flows.append(dict(component='SE',stage=phase,target_kg_s=target,samples=len(flow),
                          mean_signed_kg_s=float(flow.mean()),max_abs_relative_error=float(abs(error).max()),
                          rms_relative_error=rms,selected_flow_gate=bool(np.max(abs(error))<=scalar('validation/max_se_settled_flow_relative_error')
                          and rms<=scalar('validation/max_se_settled_flow_rms_relative_error'))))
    return performance,solids,flows


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite cycle diagnostics')
    root=args.repo/'outputs_storage_audit/c201_bounded_20260907'
    signals=load_signals(root)
    time=2000+np.arange(10001)*.001
    with h5py.File(root/'nominal_s01/diagnostic_options.mat') as f:
        performance,solids,flows=metrics(signals,f['options'],time)
    authority=json.loads((args.repo/'verification/c200_mainline_freeze_contract.json').read_text(encoding='utf-8-sig'))
    source=args.repo/authority['result_relative_path']
    if sha256(source)!=authority['result_sha256']:
        raise ValueError('Frozen C200 changed')
    paired={}
    with h5py.File(source) as f:
        t=f['physical/time_s'][0,-10001:]
        if not np.allclose(t+10,time,rtol=0,atol=1e-9):
            raise ValueError('C200/C201 sample phases do not align')
        for component,offset in [('SMA',42),('SE',63)]:
            temp=f['physical'][component+'_T_21_K'][:,-10001:]
            delta=signals[component+'_Tx21_internal']-temp
            phase=f['physical']['xM_'+component+'_21'][:,-10001:]
            dphase=signals['ECC_constitutive21_output'][offset:offset+21]-phase
            paired[component]=dict(temperature_max_K=float(abs(delta).max()),temperature_p99_K=float(np.quantile(abs(delta),.99)),
                                   temperature_rms_K=float(np.sqrt(np.mean(delta**2))),endpoint_max_K=float(abs(delta[:,-1]).max()),
                                   phase_max=float(abs(dphase).max()),phase_p99=float(np.quantile(abs(dphase),.99)),
                                   phase_rms=float(np.sqrt(np.mean(dphase**2))),endpoint_phase_max=float(abs(dphase[:,-1]).max()))
    result=dict(schema='heatdrive_ecc_c201_one_cycle_diagnostic_v1',complete_cycle_observation=True,samples=10001,
                performance=performance,solid_balances=solids,settled_flows=flows,paired_C200_C201=paired,
                all_mechanism_gates_evaluated=False,ten_new_steady_cycles_verified=False,
                whole_model_first_law_verified=False,production_recovery_allowed=False,table4_reproduction_claim=False,
                input_sha256={f'segment_{i}':sha256(root/f'nominal_s{i:02d}'/f'segment_{i:02d}.mat') for i in range(1,4)})
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps(result,indent=2))


if __name__=='__main__':
    main()
