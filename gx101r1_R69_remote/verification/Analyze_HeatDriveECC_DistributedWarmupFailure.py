"""Read failed warmup evidence without granting any endpoint or recovery authority."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Cycle import metrics
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def range_record(values):
    return dict(min=float(np.min(values)), max=float(np.max(values)), final=float(values.flat[-1]))


def analyze(failed_arm, legacy_arm):
    path=failed_arm/'failed_public_observations.mat'
    with h5py.File(path) as f, h5py.File(failed_arm/'configuration.mat') as cfg:
        if bool(f['record/valid_simulation'][0,0]):
            raise ValueError('Require a failed, nonrecoverable observation')
        signals={name:row['values'][:] for name,row in f['signals'].items()}
        time=f['signals/pressure_command_se_MPa/time_s'][:].ravel()
        if not np.allclose(time,np.arange(len(time))*.001,rtol=0,atol=1e-9):
            raise ValueError('Unexpected failed public signal clock')
        cycles=[]
        for cycle in range(int(np.floor(time[-1]/10))):
            mask=(time>=10*cycle-1e-10)&(time<=10*(cycle+1)+1e-10)
            _,solids,flows=metrics({k:v[:,mask] for k,v in signals.items()},cfg['options'],time[mask],origin=10*cycle)
            cycles.append(dict(cycle=cycle+1,flow_gates=flows,solid_balances=solids,
                               selected_flow_gates_pass=all(r['selected_flow_gate'] for r in flows)))
        idle=signals['stage4_target_flow_command'][0]==0
        switch=float(cfg['options/branch/valve_switch_pressure_MPa'][0,0])
        nominal=float(cfg['options/branch/m_dot_se_the_kg_per_s'][0,0])
        p2=float(cfg['options/branch/se_stage2_pressure_bias_MPa'][0,0])
        pressure_fraction=(signals['stage4_pressure_bias_command'][0,-1]-switch)/(p2-switch)
        target_fraction=float(signals['distributed_target_flow_kg_s'][0,-1]/nominal)
        last=dict(time_s=float(time[-1]),cycle=int(time[-1]//10)+1,phase_s=float(time[-1]%10),
            PI_target_fraction=target_fraction,original_pressure_ramp_fraction=float(pressure_fraction),
            relative_fraction_ratio=float(target_fraction/pressure_fraction),
            values={n:float(signals[n][0,-1]) for n in ('pressure_command_se_MPa',
                'stage4_p_output','stage4_route_integral','stage4_pressure_bias_command',
                'mass_flow_v1_cold_inlet_kgps','mass_flow_v4_hot_inlet_kgps',
                'probe_v4_hot_inlet_sma_side_T_K','probe_v4_hot_inlet_hot_buffer_side_T_K')})
        native_window=None
        for ref in f['native'][:].ravel():
            row=f[ref]; name=''.join(chr(int(v)) for v in row['state_name'][:].ravel())
            if name=='T_I':
                t=row['time_s'][:].ravel(); native_window=[float(t[0]),float(t[-1])]; break
        observed=dict(
            failed_public_samples=len(time),completed_cycles_before_failure=len(cycles),last_sample=last,
            failed_export_seconds=float(f['record/collection_seconds'][0,0]),native_logging_window_s=native_window,
            failed_idle_samples=int(idle.sum()),failed_idle_command=range_record(signals['pressure_command_se_MPa'][0,idle]),
            temperature_ranges={n:range_record(signals[n]) for n in ('distributed_fluid_temperature21_K',
                'SMA_Tx21_internal','SE_Tx21_internal','hot_buffer_temp_out',
                'cold_buffer_temp_out','probe_v4_hot_inlet_sma_side_T_K')},cycles=cycles)
    with h5py.File(legacy_arm/'observations.mat') as f:
        target=f['signals/stage4_target_flow_command/values'][0]
        idle=target==0
        observed['legacy_idle_command']=range_record(f['signals/pressure_command_se_MPa/values'][0,idle])
    return dict(schema='heatdrive_ecc_distributed_warmup_failure_v1',
        input_sha256=dict(failed_observations=sha256(path),failed_configuration=sha256(failed_arm/'configuration.mat'),
                          legacy_observations=sha256(legacy_arm/'observations.mat')),
        observations=observed,
        diagnosed_control_contract_regressions=['inactive switch prepressure removed',
            'PI target interpolation substituted for original pressure commutation ramp'],
        temperature_failure_is_physical_assertion=True,
        closed_leg_temperature_causality_proven=False,
        complete_twenty_cycles=False,whole_model_periodic_state_verified=False,
        temperature_limits_relaxed=False,production_recovery_allowed=False,
        continuation_or_endpoint_seed_allowed=False,table4_reproduction_claim=False)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--failed-arm',type=Path,required=True)
    p.add_argument('--legacy-arm',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args()
    if a.output.exists(): raise FileExistsError('Never overwrite failure evidence')
    result=analyze(a.failed_arm,a.legacy_arm)
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    observed=result['observations']
    print(json.dumps({k:v for k,v in observed.items() if k!='cycles'},indent=2))


if __name__=='__main__':
    main()
