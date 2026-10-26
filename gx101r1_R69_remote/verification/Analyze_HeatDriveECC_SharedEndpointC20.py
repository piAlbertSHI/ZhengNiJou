"""Read C20's retained cycles 19/20 without inventing early or hidden-state gates."""
import argparse
import json
from pathlib import Path

import numpy as np

from Analyze_HeatDriveECC_CoupledCVBalance import load_case,storage,sources,balance_window,mechanical_bridge,exchanger_metrics,engineering_pumps,signal
from Analyze_HeatDriveECC_EndpointInventoryProbe import cycle_diagnostics
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from HeatDriveECC_TraceColumns import load
from Review_HeatDriveECC_CoupledCVPacket import verify_sources,verify_arm
from Run_HeatDriveECC_ConservativeTransport import write_json


def figures(data,coarse,output):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    model=data['model'];fig,axes=plt.subplots(2,1,figsize=(8,6),layout='constrained',sharex=True)
    for part,color in (('SMA','#666666'),('SE','#007A78')):
        r=coarse[model,'coarse_'+part+'_Tx21_internal']
        axes[0].plot(r['time_s'],r['values'].mean(1),color=color,label=part,lw=1)
    c=coarse[model,'coarse_ECC_constitutive21_output']
    for part,sl,color in (('SMA',slice(42,63),'#666666'),('SE',slice(63,84),'#007A78')):
        axes[1].plot(c['time_s'],c['values'][:,sl].mean(1),color=color,label=part,lw=1)
    axes[0].set(ylabel='Solid mean temperature (K)',title='(a) Actual coarse cold-start observations')
    axes[1].set(ylabel='Mean martensite fraction',xlabel='Absolute time (s)',title='(b) Recorded phase history',ylim=(-.02,1.02))
    for ax in axes:
        ax.set_xlim(0,200);ax.axvline(180,color='#999999',ls=':',lw=.8);ax.legend(frameon=False)
        ax.spines[['top','right']].set_visible(False)
    fig.suptitle('Shared endpoint inventory: cold 20-cycle diagnostic',fontsize=11)
    fig.savefig(output/'cold_C20_history.png',dpi=200);plt.close(fig)
    # These are actual same-phase differences, not rescaled mean curves.
    T=[]
    for b in data['contract']['storage_blocks']:
        name='T' if b['mask_type']=='Thermal Mass' else 'T_I'
        from Analyze_HeatDriveECC_CoupledCVBalance import native_value
        T.append(native_value(data,b['block_path'],name,'K'))
    T=np.column_stack(T);phase=signal(data,'ECC_constitutive21_output')[:,42:84]
    clock=data['time'][10000:]-190
    fig,axes=plt.subplots(2,1,figsize=(8,5.5),layout='constrained',sharex=True)
    for ax,x,ylabel in ((axes[0],T,'Maximum absolute temperature difference (K)'),
                        (axes[1],phase,'Maximum absolute phase-fraction difference')):
        ax.plot(clock,abs(x[10000:]-x[:10001]).max(1),color='#007A78',lw=1)
        ax.set(ylabel=ylabel,xlim=(0,10));ax.spines[['top','right']].set_visible(False)
    axes[1].set_xlabel('Cycle phase time (s)')
    axes[0].set_title('Cycles 20 minus 19: all retained physical coordinates')
    fig.savefig(output/'last_cycle_pair_differences.png',dpi=200);plt.close(fig)


def analyze(root,proof_path,output):
    read=lambda p:json.loads(p.read_text(encoding='utf-8'))
    e=read(root/'coupled_CV_execution.json')
    if not e['collection_complete'] or e['stop_time_s']!=200 or e['checkpoint_loaded_or_saved'] or e['capture_profile']!='coupled_cv_tail_v1':
        raise ValueError('Not one complete continuous cold C20')
    if len(e['completed_arms'])!=1 or e['completed_arms'][0]['arm']!='shared':raise ValueError('Wrong C20 physical topology')
    verify_sources(e);case=e['completed_arms'][0];coverage=verify_arm(root,case,200)
    data=load_case(root,case);window=data['contract']['observation_window'];proof=read(proof_path)
    if window['start_s']!=180 or window['stop_s']!=200 or sha256(proof_path)!=window['executed_logging_proof_sha256'] or not proof['passive_logging_equivalence_pass']:
        raise ValueError('C20 observation changed since its executed equivalence proof')
    construction_path=root/'shared/endpoint_inventory_construction.json'
    if sha256(construction_path)!=data['contract']['initialization_construction_sha256']:raise ValueError('Cold construction metadata changed')
    construction=read(construction_path)
    if construction['private_state_or_checkpoint_loaded'] or construction['initial_flux_compensation_applied']:
        raise ValueError('C20 did not use the declared fresh public cold construction')
    components=storage(data);boundary=sources(data);diagnostics=cycle_diagnostics(data,200)
    windows=[]
    for start,stop in ((180,190),(190,200),(180,200)):
        row=balance_window(data,components,boundary,start,stop);bridge=mechanical_bridge(data,boundary,start,stop)
        row['two_bed_mechanical_latent_bridge']=bridge
        row['true_external_boundary_heat_J']=row['source_net_input_J']-bridge['native_constitutive_heat_BE_J']
        row['endpoint_sensible_fluid_extended_buffer_plus_solid_chemical_change_J']=row['endpoint_energy_change_J']-bridge['solid_mL_delta_phase_J']
        row['external_minus_corrected_endpoint_J']=row['true_external_boundary_heat_J']-row['endpoint_sensible_fluid_extended_buffer_plus_solid_chemical_change_J']
        row['engineering_pumps']=engineering_pumps(data,start,stop)
        row['Eq9_Eq10_diagnostics']=exchanger_metrics(data,start,stop)
        windows.append(row)
    coarse=load(root/'shared/coarse_CV_observations.mat');initial=[]
    for n in ('01','11','21'):
        key='coarse_sma_hold_pipe_node'+n+'_fluid_temp_out';r=coarse[data['model'],key]
        initial.append(dict(signal=key,actual_time_s=float(r['time_s'][0]),temperature_K=float(r['values'][0,0]),
                            difference_from_declared_K=float(r['values'][0,0]-data['options']['system']['T0_K'])))
    flow_pass=all(all(r[k]['direction_pass'] and r[k]['instantaneous_target_pass'] and r[k].get('RMS_target_pass',True)
                      for k in ('SMA','SE_stage2','SE_stage4')) for r in diagnostics['settled_flow_original_thresholds'])
    output.mkdir(parents=True,exist_ok=False);figures(data,coarse,output)
    result=dict(schema='heatdrive_ecc_shared_endpoint_C20_review_v1',producer_commit=e['execution_commit'],
        execution_sha256=sha256(root/'coupled_CV_execution.json'),reader_sha256=sha256(Path(__file__)),coverage=coverage,
        completed_cycles=20,continuous_cold_simulation_window_s=[0,200],full_native_window_s=[180,200],
        coarse_initial_selected_SMA_pipe_samples=initial,all_21_initial_fluid_temperatures_observed=False,
        retained_cycle_diagnostics=diagnostics,retained_flow_subset_pass=flow_pass,windows=windows,
        full_early_cycle_mechanism_coverage_claimed=False,all_mechanism_gates_evaluated=False,
        complete_hidden_state_periodicity_verified=False,ten_steady_cycle_performance_window_available=False,
        production_recovery_allowed=False,outer_solve_or_paired_Table4_allowed=False,Table4_reproduction_claim=False,
        plot_sha256={n:sha256(output/n) for n in ('cold_C20_history.png','last_cycle_pair_differences.png')})
    write_json(output/'shared_endpoint_C20_review.json',result)
    print(json.dumps(dict(output=str(output),completed_cycles=20,retained_flow_subset_pass=flow_pass,
        retained_temperature_drift_K=diagnostics['all_native_temperature_C2_drift_K'],
        last_cycle_endpoint_energy_residual_J=windows[1]['external_minus_corrected_endpoint_J'],performance_qualified=False)))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('root','proof','output'):p.add_argument('--'+name,type=Path,required=True)
    a=p.parse_args();analyze(a.root.resolve(),a.proof.resolve(),a.output.resolve())
