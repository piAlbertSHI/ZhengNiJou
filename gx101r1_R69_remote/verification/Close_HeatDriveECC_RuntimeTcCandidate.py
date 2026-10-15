"""Seal a measured fixed-Tc trial without promoting it to C200 or an outer root."""
import argparse
import json
from pathlib import Path
import shutil
import math

from Analyze_HeatDriveECC_RecordedTenCycles import runtime_window
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Close_HeatDriveECC_RuntimeWarmup import packet_cycles
from Close_HeatDriveECC_SplitObservation import read, validate_gate


def close(collection, measured, thermal, output):
    repo=Path(__file__).resolve().parents[1];collection=collection.resolve();output=output.resolve()
    if output.exists() or output.parent!=repo/'outputs_storage_audit':raise ValueError('Use a fresh compact archive')
    if (collection/'COMPLETED_RAW_PREFIX_RETIRED.json').exists():raise ValueError('Use the existing sealed endpoint; do not reseal retired raw')
    result=read(collection/'collection_result.json')
    continuing=result['schema']=='heatdrive_ecc_runtime_Tc_continuation_collection_v1'
    if not continuing and result['schema']!='heatdrive_ecc_runtime_Tc_candidate_collection_v1':raise ValueError('Not a declared Tc trial')
    start,stop,selected,previous=runtime_window(result);d=read(measured);s=read(thermal)
    trial=result['boundary_trial'];Tc=trial['candidate_Tc_K']
    stepping=trial['schema']=='heatdrive_ecc_runtime_Tc_intervention_v2' and not continuing
    if (d['window_s']!=[start,stop] or d['sample_count']!=100001 or not d['fixed_Tc_candidate'] or
            d['candidate_Tc_K']!=Tc or d['collection_result_sha256']!=sha256(collection/'collection_result.json') or
            s['measured_window_sha256']!=sha256(measured) or s['physical_tolerances_changed'] or
            not s['original_production_statistics_used']):raise ValueError('Changed measured candidate evaluation')
    latest=result['latest_periodicity'];live=read(Path(latest['thermal_statistics_path']))
    if (s['statistics']!=live['statistics'] or s['statistics_source_sha256']!=live['statistics_source_sha256'] or
            sha256(Path(latest['thermal_statistics_path']))!=latest['thermal_statistics_sha256']):
        raise ValueError('Independent final statistics disagree with the stopping decision')
    p=read(collection/'initial_recording_contract.json');recipe=read(collection/'initial_prepared_recipe.json')
    if continuing or stepping:
        qpath=Path(recipe['diagnostic_observation_options']['candidate_qualification_path']);q=read(qpath)
        source_hash=result['continuation']['source_qualification_sha256'] if continuing else trial['source_qualification_sha256']
        if (sha256(qpath)!=source_hash or
                (continuing and (q['temperature_K']!=Tc or q['boundary_trial']!=trial)) or
                (stepping and (q['temperature_K']!=trial['source_Tc_K'] or
                    q['operating_point_sha256']!=trial['source_complete_OP_sha256'] or
                    not q['bounded_outer_metric_sampling_allowed'])) or
                not q['all_original_packet_mechanism_flow_phase_energy_gates_pass']):
            raise ValueError('Changed or failed same-Tc source')
    else:
        source_repo=Path(recipe['diagnostic_observation_options']['recording_contract_path']).resolve().parents[1]
        qpath=source_repo/p['qualification_relative'];q=read(qpath)
        if sha256(qpath)!=p['qualification_sha256'] or not q['original_public_thermal_periodic_pass']:
            raise ValueError('Changed or unqualified original baseline')
    dependencies=[qpath,Path(recipe['output_root'])/'native/runtime_Tc_recipe_comparison.json',
        collection/'initial_recording_contract.json',collection/'initial_prepared_recipe.json',
        collection/'collection_result.json',measured,thermal,
        Path(latest['thermal_statistics_path']),Path(latest['measured_window_path'])]
    if sha256(Path(latest['measured_window_path']))!=latest['measured_window_sha256']:
        raise ValueError('Changed live measured index')
    target_report=None
    if continuing:
        source_window=Path(result['origin_measured_window_path']);target=result['latest_target_stability']
        target_path=Path(target['path'])
        if (sha256(source_window)!=result['origin_measured_window_sha256'] or sha256(target_path)!=target['sha256'] or
                not any(Path(f['path'])==source_window and f['sha256']==result['origin_measured_window_sha256'] for f in q['files'])):
            raise ValueError('Changed source window or current target precision')
        target_report=read(target_path)
        if target_report['window_s']!=[start,stop]:raise ValueError('Target precision refers to another window')
        dependencies.extend([source_window,target_path])
        for row in selected:
            packet=Path(row['packet_root'])
            if packet.is_relative_to(collection):continue
            m=read(packet/'packet_manifest.json')
            for item in m['input_files']:
                file=(packet/item['path']).resolve()
                if not file.is_relative_to(packet.resolve()) or sha256(file)!=item['sha256']:raise ValueError('Changed inherited raw')
                dependencies.append(file)
            dependencies.extend(packet/n for n in ('packet_manifest.json','packet_gate.json','boundary_comparison.json'))
    if stepping:
        target=result['latest_target_stability'];target_path=Path(target['path'])
        if sha256(target_path)!=target['sha256']:raise ValueError('Changed bounded-search target precision')
        target_report=read(target_path)
        if target_report['window_s']!=[start,stop]:raise ValueError('Wrong bounded-search target window')
        dependencies.append(target_path)
    parent=p['operating_point_sha256'];chain=[];cycles=[];retirement=[]
    if sha256(Path(p['operating_point_path']))!=parent:raise ValueError('Changed baseline state')
    dependencies.append(Path(p['operating_point_path']))
    for k,row in enumerate(result['completed_packets']):
        packet=Path(row['packet_root']);m=read(packet/'packet_manifest.json');g=read(packet/'packet_gate.json')
        b=read(packet/'boundary_comparison.json');validate_gate(g)
        role='runtime_boundary_Tc_continuation' if continuing else 'runtime_boundary_Tc_candidate'
        if (m['packet_role']!=role or m['prescribed_Tc_K']!=Tc or
                m['boundary_trial']!=trial or m['parent_complete_OP_sha256']!=parent or
                row['operating_point_sha256']!=m['complete_OP_sha256'] or not b['pass'] or
                not b['retained_memories_bitwise_equal'] or b['retained_memory_count']!=4 or
                g['input_sha256']['manifest']!=sha256(packet/'packet_manifest.json') or
                b['candidate_observation_sha256']!=sha256(packet/'native/observations.mat') or
                b['candidate_state_sha256']!=sha256(packet/'observed_states.mat')):
            raise ValueError('Broken candidate packet or retained-memory lineage')
        if continuing and m['continuation']!=result['continuation']:raise ValueError('Changed continuation contract')
        if k==0 and not continuing:
            if (b['boundary_intervention']!=trial or not b['actual_fixed_boundary_applied'] or
                    not b['all_other_discrete_states_bitwise_equal']):raise ValueError('Undeclared boundary event')
        elif not all(b[key]['bitwise_values_equal'] for key in ('states','native','sources','public')):
            raise ValueError('Same-Tc continuation changed its measured boundary')
        for item in m['input_files']:
            file=(packet/item['path']).resolve()
            if not file.is_relative_to(collection) or sha256(file)!=item['sha256']:raise ValueError('Changed trial raw')
            obsolete=continuing and row['stop_time_s']<=start and item['path'] in ('native/observations.mat','observed_states.mat')
            if obsolete:retirement.append(dict(path=str(file),bytes=file.stat().st_size,sha256=sha256(file),classification='obsolete_same_Tc_prefix'))
            else:dependencies.append(file)
        op=packet/'comparison_only_complete_op.mat'
        if sha256(op)!=m['complete_OP_sha256']:raise ValueError('Changed complete candidate state')
        dependencies.extend([op,packet/'packet_manifest.json',packet/'packet_gate.json',packet/'boundary_comparison.json'])
        parent=m['complete_OP_sha256'];cycles.extend(packet_cycles(packet))
        chain.append(dict(window_s=m['window_s'],packet_root=str(packet),operating_point_sha256=parent,
            energy_residual_J=g['modeled_energy_balance']['external_heat_minus_total_storage_J'],
            declared_boundary_intervention=k==0 and not continuing,all_four_memories_bitwise_preserved=True))
    output.mkdir();copies=[]
    names={'packet_manifest.json','packet_gate.json','boundary_comparison.json','mechanism.json','simulation_start.json',
        'collection_result.json','collection_progress.json','initial_recording_contract.json','initial_prepared_recipe.json',
        'original_thermal_statistics.json','measured_window.json','target_window_stability.json'}
    for f in collection.rglob('*'):
        if not f.is_file() or f.name not in names:continue
        if f.stat().st_size>1024**2:raise ValueError('Do not archive full-array JSON')
        target=output/'collection'/f.relative_to(collection);target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(f,target)
        if sha256(target)!=sha256(f):raise ValueError('Changed archive copy')
        copies.append(dict(path=str(f),sha256=sha256(f),bytes=f.stat().st_size))
    metrics=output/'additional_cycle_metrics.json'
    metrics.write_text(json.dumps(dict(cycle_count=len(cycles),cycles=cycles,
        performance_quadrature='trapz_both_endpoints',transition_excluded_from_reported_ten_cycle_performance=True),indent=2)+'\n',encoding='utf-8')
    dependencies.append(metrics)
    current=d['cycles'];spread={key:max(r[key] for r in current)-min(r[key] for r in current)
        for key in ('temperature_lift_eq9_K','SCP_W_per_g','cooling_power_eq10_W')}
    if continuing or stepping:
        if not all(math.isclose(spread[key],target_report[field],rel_tol=1e-12,abs_tol=1e-12)
            for key,field in (('temperature_lift_eq9_K','lift_span_K'),('SCP_W_per_g','SCP_span_W_per_g'))):
            raise ValueError('Independent window metrics disagree with the finite-window stopping calculation')
    if continuing:
        plan=dict(schema='heatdrive_ecc_completed_runtime_raw_prefix_retirement_v1',collection_root=str(collection),
            collection_result_sha256=sha256(collection/'collection_result.json'),retained_native_window_s=[start,stop],
            retained_all_complete_OPs=True,retained_all_compact_mechanism_evidence=True,
            current_endpoint_path=str(Path(result['last_verified_packet_root'])/'comparison_only_complete_op.mat'),
            current_endpoint_sha256=parent,files=retirement,retire_bytes=sum(r['bytes'] for r in retirement),
            retired_prefix_may_be_used_as_recovery_source=False,complete_job_inplace_resume_after_retirement_allowed=False)
        plan_path=output/'raw_prefix_retirement_plan.json';plan_path.write_text(json.dumps(plan,indent=2)+'\n',encoding='utf-8')
        dependencies.append(plan_path)
        if any(Path(r['path']) in set(dependencies) for r in retirement):raise ValueError('Never retire a current dependency')
    qualification=dict(schema='heatdrive_ecc_runtime_Tc_candidate_endpoint_v1',temperature_K=Tc,
        source_producer=result['producer'],boundary_trial=trial,snapshot_time_s=stop,total_cycles=stop/10,
        source_packet_root=result['last_verified_packet_root'],
        operating_point_path=str(Path(result['last_verified_packet_root'])/'comparison_only_complete_op.mat'),
        operating_point_sha256=parent,current_window_s=[start,stop],transition_excluded=True,
        all_original_packet_mechanism_flow_phase_energy_gates_pass=True,all_four_memories_bitwise_preserved=True,
        original_public_thermal_periodic_pass=s['statistics']['periodic_steady_state'],original_thermal_statistics=s['statistics'],
        performance=d['performance'],finite_window_performance_spread=spread,finite_window_spread_is_not_asymptotic_error_bound=True,
        packet_chain=chain,source_state_edited=False,old_model_OP_imported=False,
        source_heat_impulse_independently_closed=False,complete_internal_state_periodicity_verified=False,
        production_recovery_allowed=False,outer_solve_eligible=False,paired_Table4_eligible=False,table4_reproduction_claim=False,
        baseline_candidate_windows_matched=False,causal_Tc_derivative_claim=False,
        same_Tc_continuation=continuing,current_target_window_stability=target_report,
        bounded_outer_metric_sampling_allowed=bool((continuing or stepping) and s['statistics']['periodic_steady_state'] and target_report['precision_pass']),
        remaining_admission_work='Quantify inventory/target error budget and matched-time control before interpolation; no C200 authority promotion.',
        files=[dict(path=str(f.resolve()),sha256=sha256(f)) for f in dict.fromkeys(dependencies)])
    if continuing:
        qualification['obsolete_prefix_raw_retirement_plan_sha256']=sha256(plan_path)
    qout=output/'endpoint_qualification.json';qout.write_text(json.dumps(qualification,indent=2)+'\n',encoding='utf-8')
    if continuing:
        (output/'endpoint_contract.json').write_text(json.dumps(dict(qualification_relative=str(qout.relative_to(repo)),
            qualification_sha256=sha256(qout),operating_point_path=qualification['operating_point_path'],
            operating_point_sha256=parent,production_recovery_allowed=False),indent=2)+'\n',encoding='utf-8')
    (output/'storage_receipt.json').write_text(json.dumps(dict(compact_copies=copies,
        compact_bytes=sum(r['bytes'] for r in copies),raw_copied_bytes=0,raw_retired_bytes_at_sealing=0,
        planned_obsolete_prefix_raw_bytes=sum(r['bytes'] for r in retirement),
        retained_first_packet_for_boundary_event=not continuing,retained_current_window=True,retained_complete_OPs=True,
        execution_collection_bytes=sum(f.stat().st_size for f in collection.rglob('*') if f.is_file())),indent=2)+'\n',encoding='utf-8')
    if not qualification['original_public_thermal_periodic_pass']:
        (output/'REJECTED_NOT_CURRENTLY_PERIODIC.json').write_text(json.dumps(dict(
            reason='The finite candidate budget ended before the original public periodicity predicates passed.',
            physics_gate_failure=False,outer_interpolation_allowed=False,production_recovery_allowed=False),indent=2)+'\n',encoding='utf-8')
    return dict(snapshot_s=stop,Tc_K=Tc,periodic_pass=qualification['original_public_thermal_periodic_pass'],
        performance=d['performance'],finite_window_performance_spread=spread,outer_solve_eligible=False,
        qualification_sha256=sha256(qout),operating_point_sha256=parent)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('collection','measured','thermal','output'):parser.add_argument('--'+name,required=True,type=Path)
    print(json.dumps(close(**vars(parser.parse_args())),indent=2))
