"""Seal a real runtime warmup endpoint; authorize retirement only outside its current window."""
import argparse
import json
from pathlib import Path
import shutil
import h5py
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Close_HeatDriveECC_SplitObservation import read,validate_gate
from Analyze_HeatDriveECC_RecordedTenCycles import runtime_window
from Analyze_HeatDriveECC_CoolingBoundaryReconciliation import integrals,stage_ids
from HeatDriveECC_ObservationWindow import window_indices


def packet_cycles(packet):
    manifest=read(packet/'packet_manifest.json');begin,end=manifest['window_s'];rows=[]
    with h5py.File(packet/'native/observations.mat') as f,h5py.File(packet/'native/configuration.mat') as cfg:
        o=cfg['options'];t=f['signals/SMA_Tx21_internal/time_s'][:].ravel()
        full=window_indices(t,begin,end);time=t[full]
        signal=lambda name:f['signals/'+name+'/values'][:,full].sum(axis=0)
        cp=float(o['system/cp_fluid_J_per_kgK'][0,0]);mass=float(o['equilibrium/m_r_kg'][0,0])
        stage=stage_ids(time,float(o['cycle_count'][0,0]),o['schedule/stage_start_s'][:].ravel(),o['schedule/stage_end_s'][:].ravel())
        q=abs(signal('mass_flow_v4_hot_inlet_kgps'))*(stage==4)*cp*(
            signal('cold_hx_inlet_fluid_temp_out')-signal('cold_hx_outlet_fluid_temp_out'))
        lift=signal('hot_hx_inlet_fluid_temp_out')-signal('cold_hx_inlet_fluid_temp_out')
        sensor=signal('Qdot_cold_sink_mass_to_hx_pipe_W');hot=np.maximum(signal('shex_source_heat_flow_W'),0)
        for start in range(int(begin),int(end),10):
            indices=window_indices(time,start,start+10)
            mean=lambda values:integrals(time[indices],values[indices])['trapz_J']/10
            cooling,source=mean(q),mean(hot)
            rows.append(dict(cycle=start//10+1,window_s=[start,start+10],temperature_lift_eq9_K=mean(lift),
                cooling_power_eq10_W=cooling,SCP_W_per_g=cooling/(1000*mass),CHEX_sensor_mean_W=mean(sensor),
                positive_SHEX_heat_mean_W=source,heat_driven_COP=cooling/source if source>0 else None,
                source_packet_manifest_sha256=sha256(packet/'packet_manifest.json')))
    return rows


def close(collection,measured,thermal,output):
    repo=Path(__file__).resolve().parents[1];output=output.resolve();collection=collection.resolve()
    if output.exists() or output.parent!=repo/'outputs_storage_audit':raise ValueError('Use a fresh local archive')
    if (collection/'COMPLETED_RAW_PREFIX_RETIRED.json').exists():
        raise ValueError('Use the existing sealed endpoint; retired completed jobs cannot be resealed from missing raw')
    result=read(collection/'collection_result.json');start,stop,selected,_=runtime_window(result)
    observations=read(measured);statistics=read(thermal)
    if (observations['window_s']!=[start,stop] or observations['sample_count']!=100001 or
            not observations['runtime_family'] or statistics['measured_window_sha256']!=sha256(measured) or
            not statistics['original_production_statistics_used'] or statistics['physical_tolerances_changed'] or
            observations['collection_result_sha256']!=sha256(collection/'collection_result.json')):
        raise ValueError('The original current-window statistics must describe this actual collection')
    endpoint=Path(result['last_verified_packet_root']);chain=[];dependencies=[];targets=[];cycle_metrics=[]
    origin=read(collection/'initial_recording_contract.json');parent=origin['operating_point_sha256']
    prepared=read(collection/'initial_prepared_recipe.json')
    source_repo=Path(prepared['diagnostic_observation_options']['recording_contract_path']).resolve().parents[1]
    origin_q=source_repo/origin['qualification_relative']
    if sha256(origin_q)!=origin['qualification_sha256']:raise ValueError('Origin qualification changed')
    dependencies.extend((origin_q,Path(prepared['output_root'])/'native/runtime_warmup_recipe_comparison.json'))
    if result.get('stop_on_public_periodicity',False):
        origin_window=Path(result['origin_measured_window_path'])
        q=read(origin_q)
        if not any(Path(row['path'])==origin_window and row['sha256']==result['origin_measured_window_sha256']
                   for row in q['files']):
            raise ValueError('The rolling origin must be bound by the source qualification')
        dependencies.append(origin_window)
        check=result['latest_periodicity']
        for key in ('measured_window','thermal_statistics'):
            file=Path(check[key+'_path'])
            if sha256(file)!=check[key+'_sha256']:raise ValueError('Changed live stopping evidence')
            dependencies.append(file)
        live=read(Path(check['thermal_statistics_path']))
        if (statistics['statistics']!=live['statistics'] or
                statistics['statistics_source_sha256']!=live['statistics_source_sha256'] or
                statistics['statistics']['periodic_steady_state']!=check['periodic_steady_state']):
            raise ValueError('Independent final thermal evaluation disagrees with the live stopping decision')
        for row in selected:
            packet=Path(row['packet_root'])
            if packet.is_relative_to(collection):continue
            manifest=read(packet/'packet_manifest.json')
            for item in manifest['input_files']:
                file=(packet/item['path']).resolve()
                if not file.is_relative_to(packet.resolve()) or sha256(file)!=item['sha256']:
                    raise ValueError('Changed inherited current-window evidence')
                dependencies.append(file)
            dependencies.extend(packet/name for name in ('packet_manifest.json','packet_gate.json','boundary_comparison.json'))
    if sha256(Path(origin['operating_point_path']))!=parent:raise ValueError('Origin state changed')
    for row in result['completed_packets']:
        packet=Path(row['packet_root']);m=read(packet/'packet_manifest.json');g=read(packet/'packet_gate.json')
        b=read(packet/'boundary_comparison.json');validate_gate(g)
        if (m['parent_complete_OP_sha256']!=parent or m['complete_OP_sha256']!=row['operating_point_sha256'] or
                m['packet_role']!='runtime_boundary_transient' or m['prescribed_Tc_K']!=276.95 or
                g['input_sha256']['manifest']!=sha256(packet/'packet_manifest.json') or
                not b['pass'] or not b['retained_memories_bitwise_equal'] or b['retained_memory_count']!=4 or
                b['candidate_observation_sha256']!=sha256(packet/'native/observations.mat') or
                b['candidate_state_sha256']!=sha256(packet/'observed_states.mat')):
            raise ValueError('Broken measured packet lineage')
        if sha256(packet/'comparison_only_complete_op.mat')!=m['complete_OP_sha256']:raise ValueError('Changed OP')
        parent=m['complete_OP_sha256']
        chain.append(dict(packet_root=str(packet),window_s=m['window_s'],operating_point_sha256=parent,
            all_boundary_coordinates_bitwise_equal=all(b[key]['bitwise_values_equal'] for key in ('states','native','sources','public')),
            energy_residual_J=g['modeled_energy_balance']['external_heat_minus_total_storage_J']))
        for item in m['input_files']:
            file=(packet/item['path']).resolve()
            if not file.is_relative_to(collection) or sha256(file)!=item['sha256']:raise ValueError('Changed packet input')
            if row['stop_time_s']>start:dependencies.append(file)
        dependencies.extend(packet/name for name in ('packet_manifest.json','packet_gate.json','boundary_comparison.json'))
        if row['stop_time_s']<=start:
            for name in ('native/observations.mat','observed_states.mat','mechanism_view.mat'):
                file=packet/name
                if file.is_file():targets.append(dict(path=str(file),bytes=file.stat().st_size,sha256=sha256(file),
                    classification='obsolete_raw_prefix_outside_current_ten_cycles'))
        cycle_metrics.extend(packet_cycles(packet))
    output.mkdir();copies=[]
    metrics_path=output/('all_additional_cycle_metrics.json' if result.get('stop_on_public_periodicity',False)
                        else 'all_twenty_cycle_metrics.json')
    metrics_path.write_text(json.dumps(dict(schema='heatdrive_ecc_runtime_warmup_cycle_metrics_v1',
        window_s=result['collection_window_s'],cycle_count=len(cycle_metrics),cycles=cycle_metrics,
        quadrature='trapz_both_endpoints',old_prefix_raw_may_be_retired_after_sealing=True,
        steady_endpoint_claim=False),indent=2,allow_nan=False)+'\n',encoding='utf-8')
    dependencies.append(metrics_path)
    names={'packet_manifest.json','packet_gate.json','boundary_comparison.json','mechanism.json',
           'simulation_start.json','collection_result.json','collection_progress.json',
           'initial_recording_contract.json','initial_prepared_recipe.json',
           'original_thermal_statistics.json','measured_window.json'}
    for file in collection.rglob('*'):
        if not file.is_file() or file.name not in names:continue
        if file.stat().st_size>1024**2:raise ValueError('Unexpected full-array JSON')
        target=output/'collection'/file.relative_to(collection);target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(file,target)
        digest=sha256(file)
        if sha256(target)!=digest:raise ValueError('Archive bytes changed')
        copies.append(dict(source_path=str(file),archive_relative=str(target.relative_to(output)),bytes=file.stat().st_size,sha256=digest))
    dependencies.extend((measured,thermal,collection/'collection_result.json',collection/'initial_recording_contract.json',
                         collection/'initial_prepared_recipe.json',endpoint/'comparison_only_complete_op.mat'))
    if any(Path(row['path']).resolve() in {path.resolve() for path in dependencies} for row in targets):
        raise ValueError('Never retire qualified current-window dependencies')
    plan=dict(schema='heatdrive_ecc_completed_warmup_raw_prefix_retirement_v1',collection_root=str(collection),
        collection_result_sha256=sha256(collection/'collection_result.json'),retained_native_window_s=[start,stop],
        retained_all_complete_OPs=True,retained_all_compact_mechanism_evidence=True,
        current_endpoint_path=str(endpoint/'comparison_only_complete_op.mat'),current_endpoint_sha256=parent,
        files=targets,retire_bytes=sum(row['bytes'] for row in targets),
        retired_prefix_may_be_used_as_recovery_source=False,complete_job_inplace_resume_after_retirement_allowed=False)
    plan_path=output/'raw_prefix_retirement_plan.json';plan_path.write_text(json.dumps(plan,indent=2)+'\n',encoding='utf-8')
    dependencies.append(plan_path)
    qualification=dict(schema='heatdrive_ecc_runtime_boundary_warmup_endpoint_v1',source_producer=result['producer'],
        source_packet_root=str(endpoint),snapshot_time_s=stop,total_cycles=stop/10,temperature_K=276.95,
        operating_point_path=str(endpoint/'comparison_only_complete_op.mat'),operating_point_sha256=parent,
        temperature_configurability='runtime',checksum_policy='error/error',native_history_cap_cycles=2,
        state_history_cap_cycles=11,command_horizon_cycles=200,actual_native_observation_window_s=[start,stop],
        transient_continuation_allowed=True,all_original_packet_gates_pass=True,all_recorded_boundaries_pass=True,
        all_recorded_boundaries_bitwise_equal=all(row['all_boundary_coordinates_bitwise_equal'] for row in chain),
        original_public_thermal_periodic_pass=statistics['statistics']['periodic_steady_state'],
        original_thermal_statistics=statistics['statistics'],source_state_edited=False,old_model_OP_imported=False,
        complete_internal_state_periodicity_verified=False,production_recovery_allowed=False,
        steady_parameter_study_allowed=False,outer_solve_eligible=False,table4_reproduction_claim=False,
        packet_chain=chain,retained_raw_window_s=[start,stop],obsolete_prefix_raw_retirement_plan_sha256=sha256(plan_path),
        next_action='Continue same-runtime-family packets from this complete OP; a failed periodic predicate is not a mechanism failure. No cold restart, state reset, old-family import or interpolation of unsteady candidates.',
        files=[dict(path=str(path.resolve()),sha256=sha256(path)) for path in dict.fromkeys(dependencies)])
    qpath=output/'endpoint_qualification.json';qpath.write_text(json.dumps(qualification,indent=2)+'\n',encoding='utf-8')
    receipt=dict(compact_copies=copies,compact_bytes=sum(row['bytes'] for row in copies),raw_copied_bytes=0,
        raw_prefix_retirement_plan=str(plan_path),planned_raw_prefix_retirement_bytes=plan['retire_bytes'],
        retired_raw_bytes_at_sealing=0,current_raw_window_s=[start,stop])
    (output/'storage_receipt.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    pointer=repo/'verification/current_runtime_boundary_warmup.json'
    if pointer.exists() and sha256(pointer)!=result['origin_snapshot_sha256']:
        raise ValueError('The current warmup pointer is not this run\'s frozen origin; do not overwrite another endpoint')
    temporary=pointer.with_suffix('.json.writing')
    if temporary.exists():raise FileExistsError('Diagnose an interrupted endpoint update before replacing it')
    temporary.write_text(json.dumps(dict(schema=qualification['schema'],snapshot_time_s=stop,total_cycles=stop/10,
        qualification_relative=str(qpath.relative_to(repo)),qualification_sha256=sha256(qpath),
        operating_point_path=qualification['operating_point_path'],operating_point_sha256=parent,
        production_recovery_allowed=False,outer_solve_eligible=False,steady_parameter_study_allowed=False),indent=2)+'\n',encoding='utf-8')
    temporary.replace(pointer)
    return dict(snapshot_s=stop,periodic_pass=qualification['original_public_thermal_periodic_pass'],
        compact_bytes=receipt['compact_bytes'],planned_obsolete_prefix_raw_bytes=plan['retire_bytes'],
        endpoint_OP_sha256=parent)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('collection','measured','thermal','output'):parser.add_argument('--'+name,required=True,type=Path)
    print(json.dumps(close(**vars(parser.parse_args())),indent=2))
