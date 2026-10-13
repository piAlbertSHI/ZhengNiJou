"""Separate measured SE commutation transfer from fully inactive-seat transfer."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_CoupledEnergyInventory import MASS_TOL_KG, ROOT
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from HeatDriveECC_ObservationWindow import window_indices


def partition(time,mass,flow,ramp_s,period=10):
    time,mass,flow=map(lambda a:np.asarray(a,dtype=float),(time,mass,flow))
    if (time.ndim!=1 or mass.shape!=time.shape or flow.shape!=time.shape
            or not np.isfinite([time,mass,flow]).all() or np.any(mass<=0)
            or not np.allclose(np.diff(time),.001,atol=1e-9,rtol=0)
            or period!=10 or not 0<ramp_s<1.5
            or abs(ramp_s/.001-round(ramp_s/.001))>1e-8):
        raise ValueError('Invalid measured inventory window or actual commutation duration')
    cycles=round((time[-1]-time[0])/period)
    if cycles<1 or abs(time[-1]-time[0]-cycles*period)>1e-9:
        raise ValueError('Require complete ten-second cycles')
    rows=[]
    for cycle in range(cycles):
        base=cycle*10000
        for stage,(a,b) in enumerate(zip((0,3500,5000,8500),(3500,5000,8500,10000)),1):
            begin,end=base+a,base+b;mid=begin+round(ramp_s/.001)
            parts=[]
            for label,i,j in (('post_boundary_commutation',begin,mid),('after_commutation',mid,end)):
                transferred=float(np.sum(flow[i+1:j+1]*np.diff(time[i:j+1])))
                delta=float(mass[j]-mass[i])
                parts.append(dict(region=label,start_s=float(time[i]),stop_s=float(time[j]),
                    transported_mass_BE_kg=transferred,endpoint_mass_change_kg=delta,
                    mass_residual_kg=transferred-delta,local_mass_pass=abs(transferred-delta)<=MASS_TOL_KG))
            delta=float(mass[end]-mass[begin])
            if abs(sum(part['endpoint_mass_change_kg'] for part in parts)-delta)>MASS_TOL_KG:
                raise ValueError('Partition dropped or duplicated an interval')
            rows.append(dict(global_cycle=round(time[base+10000]/10),stage=stage,
                phase_role='inactive_nominal_stage' if stage in (1,3) else 'active_nominal_stage',
                endpoint_mass_change_kg=delta,parts=parts))
    return rows


def reference_comparison(time,alpha,ff_target,pi_target,integral_gate,nominal):
    arrays=[np.asarray(a,dtype=float).ravel() for a in (time,alpha,ff_target,pi_target,integral_gate)]
    time,alpha,ff_target,pi_target,integral_gate=arrays
    if (any(a.shape!=time.shape for a in arrays) or not np.isfinite(arrays).all()
            or np.any(alpha<-1e-12) or np.any(alpha>1+1e-12) or nominal<=0):
        raise ValueError('Incomplete common clock/reference samples')
    if np.max(abs(ff_target-nominal*alpha))>1e-12:
        raise ValueError('Feedforward flow is not its actual declared envelope')
    changing=(alpha>1e-10)&(alpha<1-1e-10)
    mismatch=pi_target-ff_target
    dt=np.diff(time)
    return dict(samples=time.size,commutation_fraction_samples=int(changing.sum()),
        max_abs_PI_minus_FF_reference_kgps=float(abs(mismatch).max()),
        signed_reference_difference_BE_kg=float(np.sum(mismatch[1:]*dt)),
        absolute_reference_difference_BE_kg=float(np.sum(abs(mismatch[1:])*dt)),
        PI_full_while_FF_ramped_samples=int(np.sum(changing & np.isclose(pi_target,nominal,rtol=0,atol=1e-10))),
        route_integral_output_MPa_at_partial_envelope_max_abs=float(np.max(abs(integral_gate[changing]))) if changing.any() else None,
        pressure_envelope_and_PI_reference_identical=bool(np.max(abs(mismatch))<=1e-12),
        quantities_are_command_conflict_diagnostics_not_new_scientific_tolerances=True)


def analyze(ledger_path):
    ledger=json.loads(ledger_path.read_text(encoding='utf-8'))
    root=Path(ledger['source_root'])
    raw,config=root/'native/observations.mat',root/'native/configuration.mat'
    if sha256(raw)!=ledger['input_sha256']['observations'] or sha256(config)!=ledger['input_sha256']['configuration']:
        raise ValueError('Changed source evidence')
    start,stop=ledger['absolute_window_s']
    with h5py.File(raw) as f,h5py.File(config) as cfg:
        ramp=float(cfg['options/branch/stage_command_ramp_s'][0,0])
        nominal=float(cfg['options/branch/m_dot_se_the_kg_per_s'][0,0])
        time=start+np.arange(round((stop-start)/.001)+1)*.001
        rows=named_rows(f,f['native'])
        buffers={}
        for name in ('ColdFluidBuffer','HotFluidBuffer'):
            data=[]
            for state,unit in (('stored_mass','kg'),('mdot_A','kg/s')):
                row=rows[ROOT+name,state]
                selected=window_indices(row['time_s'][:],start,stop)
                selected_time=row['time_s'][:].ravel()[selected]
                if not np.allclose(selected_time,time,rtol=0,atol=1e-9):
                    raise ValueError('Native mass/flow clocks differ')
                data.append(scalar_series(row,unit)[selected])
            buffers[name]=partition(time,*data,ramp)
        signals=[]
        for name in ('distributed_pressure_envelope','distributed_target_flow_kg_s',
                     'stage4_target_flow_command','stage4_integrator_output_gate'):
            signal=f['signals/'+name];selected=window_indices(signal['time_s'][:],start,stop)
            if not np.allclose(signal['time_s'][:].ravel()[selected],time,rtol=0,atol=1e-9):
                raise ValueError('Controller and native clocks differ')
            signals.append(signal['values'][:].ravel()[selected])
        references=reference_comparison(time,*signals,nominal)
    summaries=[]
    for name,stages in buffers.items():
        for cycle in sorted({row['global_cycle'] for row in stages}):
            current=[row for row in stages if row['global_cycle']==cycle]
            inactive=[row for row in current if row['stage'] in (1,3)]
            summaries.append(dict(buffer=name,global_cycle=cycle,
                cycle_mass_change_kg=sum(row['endpoint_mass_change_kg'] for row in current),
                inactive_stage_mass_change_kg=sum(row['endpoint_mass_change_kg'] for row in inactive),
                inactive_stage_commutation_mass_kg=sum(row['parts'][0]['endpoint_mass_change_kg'] for row in inactive),
                fully_inactive_remainder_mass_kg=sum(row['parts'][1]['endpoint_mass_change_kg'] for row in inactive)))
    return dict(schema='heatdrive_ecc_se_commutation_inventory_v1',source_ledger_sha256=sha256(ledger_path),
        source_raw_sha256=sha256(raw),absolute_window_s=[start,stop],actual_ramp_duration_s=ramp,
        nominal_mass_flow_kgps=nominal,buffers=buffers,summaries=summaries,
        reference_comparison=references,all_partition_mass_equations_pass=all(part['local_mass_pass']
            for stages in buffers.values() for row in stages for part in row['parts']),
        source_state_edited=False,simulation_executed=False,production_recovery_allowed=False,
        outer_solve_eligible=False,table4_reproduction_claim=False,
        interpretation='Nominal Stage1/3 transfer is not automatically seat leakage. Partition by actual '
        'configured commutation duration and compare the measured controller references first.')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-ledger',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():raise FileExistsError('Never overwrite a commutation audit')
    result=analyze(args.source_ledger.resolve())
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({key:result[key] for key in ('actual_ramp_duration_s','summaries','reference_comparison','all_partition_mass_equations_pass')}))
