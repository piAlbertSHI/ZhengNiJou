"""Read bounded fixed-horizon warmup evidence; never grant full device validation."""
import argparse
import json
from pathlib import Path

import numpy as np
from scipy.io import loadmat

from Analyze_HeatDriveECC_CoupledCVBalance import (
    storage, sources, balance_window, mechanical_bridge, exchanger_metrics,
    engineering_pumps, energy_tables, resolve_domains, native_value, signal)
from Analyze_HeatDriveECC_EndpointInventoryProbe import cycle_diagnostics
from Analyze_HeatDriveECC_CoupledCVTrajectories import difference_stats
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from HeatDriveECC_TraceColumns import unpack
from Review_HeatDriveECC_CoupledCVPacket import on_grid
from Run_HeatDriveECC_ConservativeTransport import write_json


def matlab_metadata(value):
    """Normalize scipy's MATLAB metadata arrays, never observation values."""
    if isinstance(value,dict):return {k:matlab_metadata(v) for k,v in value.items()}
    if isinstance(value,np.ndarray):
        if value.size==0 and value.dtype.kind in 'US':return ''
        return matlab_metadata(value.tolist())
    if isinstance(value,(list,tuple)):return [matlab_metadata(v) for v in value]
    if isinstance(value,np.generic):return value.item()
    return value


def actual_native_window(rows, start, stop):
    clock=np.arange(round(start*1000),round(stop*1000)+1)*.001
    return {k:dict(r,time_s=clock,values=on_grid(r,clock)) for k,r in rows.items()}


def periodic_screens(d,v):
    t=d['all_native_temperature_C2_drift_K'];p=d['phase_C2_drift']
    return dict(temperature_endpoint=t['endpoint_max_abs']<=v['max_periodic_endpoint_drift_K'],
        temperature_max=t['same_phase_max_abs']<=v['max_periodic_same_phase_temperature_drift_K'],
        temperature_p99=t['same_phase_p99_abs']<=v['max_periodic_same_phase_temperature_p99_drift_K'],
        temperature_RMS=t['same_phase_RMS']<=v['max_periodic_same_phase_temperature_rms_drift_K'],
        phase_endpoint=p['endpoint_max_abs']<=v['max_periodic_phase_drift'],
        phase_p99=p['same_phase_p99_abs']<=v['max_periodic_same_phase_phase_p99_drift'],
        phase_RMS=p['same_phase_RMS']<=v['max_periodic_same_phase_phase_rms_drift'])


def plot(data,out,total_cycles):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    time=data['time'];T=[]
    for b in data['contract']['storage_blocks']:
        T.append(native_value(data,b['block_path'],'T' if b['mask_type']=='Thermal Mass' else 'T_I','K'))
    phase=signal(data,'ECC_constitutive21_output')[:,42:84]
    fig,axes=plt.subplots(2,1,figsize=(8,5.5),layout='constrained',sharex=True)
    for ax,x,label,limit in ((axes[0],np.column_stack(T),'Max same-phase temperature difference (K)',.05),
                              (axes[1],phase,'Max same-phase phase-fraction difference',None)):
        ax.plot(time[10000:]-time[10000],abs(x[10000:]-x[:10001]).max(1),color='#007A78',lw=1)
        if limit is not None:ax.axhline(limit,color='#666666',ls=':',lw=1,label='Maximum-temperature screen')
        ax.set(ylabel=label,xlim=(0,10));ax.spines[['top','right']].set_visible(False)
    axes[0].set_title(f'Cycles {total_cycles} minus {total_cycles-1}: retained actual physical coordinates')
    axes[0].legend(frameon=False,loc='upper left',bbox_to_anchor=(1.01,1.))
    axes[1].set_xlabel('Cycle phase time (s)')
    fig.savefig(out/'last_cycle_pair_differences.png',dpi=200);plt.close(fig)


def analyze(root,out,total_cycles,window_start,window_stop):
    read=lambda p:json.loads(p.read_text(encoding='utf-8'))
    rp=root/'new_process_restore.json';r=read(rp)
    expected_profile='warmup_C40' if total_cycles==40 else f'warmup_C{total_cycles}_from_C40'
    if (not r['execution_complete'] or r['production_recovery_allowed'] or r['source_OP_edited']
            or r['observation_profile']!=expected_profile or r['actual_tout_first_s']>=window_start
            or r['actual_tout_last_s']!=window_stop or r['fixed_command_horizon_s']!=1000):
        raise ValueError('Not the proven-epoch fixed-horizon C40 warmup')
    for role in ('context','observation','terminal_OP'):
        if sha256(Path(r[role+'_path']))!=r[role+'_sha256']:raise ValueError('Warmup dependency changed: '+role)
    parent_root=Path(r['source_root'])
    if (parent_root/'state_interface_roundtrip.json').is_file():
        parent=read(parent_root/'state_interface_roundtrip.json')
        runtime_root=parent_root
    else:
        parent_record=read(parent_root/'new_process_restore.json')
        runtime_root=Path(parent_record['source_root'])
        parent=read(runtime_root/'state_interface_roundtrip.json')
    dependencies=[(parent[k+'_path'],parent[k+'_sha256'])
                  for k in ('saved_runtime_model','operating_point','interface_contract')]
    dependencies.append((parent['base_workspace']['path'],parent['base_workspace']['sha256']))
    dependencies.extend((x['path'],x['sha256']) for x in parent['loaded_project_sources'])
    construction=read(runtime_root/'endpoint_inventory_construction.json')
    for x in construction['source_components']:
        dependencies.extend(((x['path'],x['sha256']),(x['library_path'],x['library_sha256'])))
    for path,digest in dependencies:
        if sha256(Path(path))!=digest:raise ValueError('Frozen runtime dependency changed: '+path)
    context=matlab_metadata(loadmat(r['context_path'],simplify_cells=True));contract=context['contract'];options=context['options']
    if (options['simscape']['local_solver_choice']!='NE_BACKWARD_EULER_ADVANCER'
            or options['simscape']['local_solver_sample_time_s']!=.001 or options['cycle_count']!=100):
        raise ValueError('Changed local solver or command horizon')
    raw=loadmat(r['observation_path'],simplify_cells=True)
    native=actual_native_window(unpack(raw['native_packet']),window_start,window_stop)
    time=next(iter(native.values()))['time_s'];tl=contract['tl_topology'];thermal=contract['thermal_topology']
    for packet_name in ('workspace_packet','source_packet','state_packet'):
        packet=unpack(raw[packet_name])
        if not packet or min(float(x['time_s'][0]) for x in packet.values())>window_start or max(float(x['time_s'][-1]) for x in packet.values())<window_stop:
            raise ValueError(f'Retained packet does not cover the actual {window_start}--{window_stop} s audit window: '+packet_name)
    parameters={x['block_path']:x['parameters'] for x in contract['settings_tables']}
    assignment,_=resolve_domains(tl)
    data=dict(contract=contract,options=options,tl=tl,thermal=thermal,parameters=parameters,
        tables={k:energy_tables(p) for k,p in parameters.items()},assignment=assignment,
        native=native,workspace=unpack(raw['workspace_packet']),sources=unpack(raw['source_packet']),
        boundary=context['boundary'],model=contract['storage_paths'][0].split('/')[0],time=time)
    components=storage(data);boundary=sources(data);diagnostics=cycle_diagnostics(data,400)
    screens=periodic_screens(diagnostics,options['validation']);windows=[]
    for start,stop in ((window_start,window_start+10),(window_start+10,window_stop),(window_start,window_stop)):
        row=balance_window(data,components,boundary,start,stop);bridge=mechanical_bridge(data,boundary,start,stop)
        row['two_bed_mechanical_latent_bridge']=bridge
        row['external_minus_corrected_endpoint_J']=(row['source_net_input_J']-bridge['native_constitutive_heat_BE_J']
            -row['endpoint_energy_change_J']+bridge['solid_mL_delta_phase_J'])
        row['engineering_pumps']=engineering_pumps(data,start,stop)
        row['Eq9_Eq10_diagnostics']=exchanger_metrics(data,start,stop);windows.append(row)
    flow=all(all(x[k]['direction_pass'] and x[k]['instantaneous_target_pass'] and x[k].get('RMS_target_pass',True)
                 for k in ('SMA','SE_stage2','SE_stage4')) for x in diagnostics['settled_flow_original_thresholds'])
    state_rows=[]
    for key,value in unpack(raw['state_packet']).items():
        state_rows.append(dict(path=key[0],name=key[1],unit=value['unit'],
                               drift=difference_stats(on_grid(value,time),10000)))
    out.mkdir(parents=True,exist_ok=False);plot(data,out,total_cycles)
    result=dict(schema='heatdrive_ecc_shared_endpoint_warmup_review_v1',execution_sha256=sha256(rp),
        reader_sha256=sha256(Path(__file__)),retained_native_window_s=[window_start,window_stop],completed_total_cycles=total_cycles,
        frozen_runtime_dependency_hash_count=len(dependencies),
        physical_continuation_window_s=[.2,window_stop],fixed_command_horizon_s=1000,
        simulation_wall_seconds=r['simulation_wall_seconds'],terminal_OP_path=r['terminal_OP_path'],
        terminal_OP_sha256=r['terminal_OP_sha256'],retained_cycle_diagnostics=diagnostics,
        original_periodic_screens=screens,all_listed_periodic_screens_pass=all(screens.values()),
        retained_flow_subset_pass=flow,windows=windows,logged_public_state_group_drift=state_rows,
        source_OP_untouched=True,all_mechanism_gates_evaluated=False,
        complete_hidden_state_periodicity_verified=False,periodic_steady_state=False,
        terminal_OP_is_reviewed_production_seed=False,outer_solve_or_Table4_allowed=False,
        ten_steady_cycle_performance_window_available=False,Table4_reproduction_claim=False,
        plot_sha256=sha256(out/'last_cycle_pair_differences.png'))
    write_json(out/'shared_endpoint_warmup_review.json',result)
    print(json.dumps(dict(output=str(out),completed_total_cycles=total_cycles,retained_flow_subset_pass=flow,
        original_periodic_screens=screens,temperature_drift_K=diagnostics['all_native_temperature_C2_drift_K'],
        last_cycle_endpoint_energy_residual_J=windows[1]['external_minus_corrected_endpoint_J'],
        production_or_Table4_allowed=False)))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for n in ('root','output'):p.add_argument('--'+n,type=Path,required=True)
    p.add_argument('--total-cycles',type=int,default=40)
    p.add_argument('--window-start',type=float,default=380)
    p.add_argument('--window-stop',type=float,default=400)
    a=p.parse_args();analyze(a.root.resolve(),a.output.resolve(),a.total_cycles,a.window_start,a.window_stop)
