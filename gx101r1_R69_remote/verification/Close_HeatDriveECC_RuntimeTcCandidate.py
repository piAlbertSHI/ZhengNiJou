"""Seal a measured fixed-Tc trial without promoting it to C200 or an outer root."""
import argparse
import json
from pathlib import Path
import shutil

from Analyze_HeatDriveECC_RecordedTenCycles import runtime_window
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Close_HeatDriveECC_RuntimeWarmup import packet_cycles
from Close_HeatDriveECC_SplitObservation import read, validate_gate


def close(collection, measured, thermal, output):
    repo=Path(__file__).resolve().parents[1];collection=collection.resolve();output=output.resolve()
    if output.exists() or output.parent!=repo/'outputs_storage_audit':raise ValueError('Use a fresh compact archive')
    result=read(collection/'collection_result.json')
    if result['schema']!='heatdrive_ecc_runtime_Tc_candidate_collection_v1':raise ValueError('Not a declared Tc trial')
    start,stop,selected,previous=runtime_window(result);d=read(measured);s=read(thermal)
    trial=result['boundary_trial'];Tc=trial['candidate_Tc_K']
    if (d['window_s']!=[start,stop] or d['sample_count']!=100001 or not d['fixed_Tc_candidate'] or
            d['candidate_Tc_K']!=Tc or d['collection_result_sha256']!=sha256(collection/'collection_result.json') or
            s['measured_window_sha256']!=sha256(measured) or s['physical_tolerances_changed'] or
            not s['original_production_statistics_used']):raise ValueError('Changed measured candidate evaluation')
    latest=result['latest_periodicity'];live=read(Path(latest['thermal_statistics_path']))
    if (s['statistics']!=live['statistics'] or s['statistics_source_sha256']!=live['statistics_source_sha256'] or
            sha256(Path(latest['thermal_statistics_path']))!=latest['thermal_statistics_sha256']):
        raise ValueError('Independent final statistics disagree with the stopping decision')
    p=read(collection/'initial_recording_contract.json');recipe=read(collection/'initial_prepared_recipe.json')
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
    parent=p['operating_point_sha256'];chain=[];cycles=[]
    if sha256(Path(p['operating_point_path']))!=parent:raise ValueError('Changed baseline state')
    dependencies.append(Path(p['operating_point_path']))
    for k,row in enumerate(result['completed_packets']):
        packet=Path(row['packet_root']);m=read(packet/'packet_manifest.json');g=read(packet/'packet_gate.json')
        b=read(packet/'boundary_comparison.json');validate_gate(g)
        if (m['packet_role']!='runtime_boundary_Tc_candidate' or m['prescribed_Tc_K']!=Tc or
                m['boundary_trial']!=trial or m['parent_complete_OP_sha256']!=parent or
                row['operating_point_sha256']!=m['complete_OP_sha256'] or not b['pass'] or
                not b['retained_memories_bitwise_equal'] or b['retained_memory_count']!=4 or
                g['input_sha256']['manifest']!=sha256(packet/'packet_manifest.json') or
                b['candidate_observation_sha256']!=sha256(packet/'native/observations.mat') or
                b['candidate_state_sha256']!=sha256(packet/'observed_states.mat')):
            raise ValueError('Broken candidate packet or retained-memory lineage')
        if k==0:
            if (b['boundary_intervention']!=trial or not b['actual_fixed_boundary_applied'] or
                    not b['all_other_discrete_states_bitwise_equal']):raise ValueError('Undeclared boundary event')
        elif not all(b[key]['bitwise_values_equal'] for key in ('states','native','sources','public')):
            raise ValueError('Same-Tc continuation changed its measured boundary')
        for item in m['input_files']:
            file=(packet/item['path']).resolve()
            if not file.is_relative_to(collection) or sha256(file)!=item['sha256']:raise ValueError('Changed trial raw')
            dependencies.append(file)
        op=packet/'comparison_only_complete_op.mat'
        if sha256(op)!=m['complete_OP_sha256']:raise ValueError('Changed complete candidate state')
        dependencies.extend([op,packet/'packet_manifest.json',packet/'packet_gate.json',packet/'boundary_comparison.json'])
        parent=m['complete_OP_sha256'];cycles.extend(packet_cycles(packet))
        chain.append(dict(window_s=m['window_s'],packet_root=str(packet),operating_point_sha256=parent,
            energy_residual_J=g['modeled_energy_balance']['external_heat_minus_total_storage_J'],
            declared_boundary_intervention=k==0,all_four_memories_bitwise_preserved=True))
    output.mkdir();copies=[]
    names={'packet_manifest.json','packet_gate.json','boundary_comparison.json','mechanism.json','simulation_start.json',
        'collection_result.json','collection_progress.json','initial_recording_contract.json','initial_prepared_recipe.json',
        'original_thermal_statistics.json','measured_window.json'}
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
        remaining_admission_work='Quantify inventory/target error budget and matched-time control before interpolation; no C200 authority promotion.',
        files=[dict(path=str(f.resolve()),sha256=sha256(f)) for f in dict.fromkeys(dependencies)])
    qout=output/'endpoint_qualification.json';qout.write_text(json.dumps(qualification,indent=2)+'\n',encoding='utf-8')
    (output/'storage_receipt.json').write_text(json.dumps(dict(compact_copies=copies,
        compact_bytes=sum(r['bytes'] for r in copies),raw_copied_bytes=0,raw_retired_bytes=0,
        retained_first_packet_for_boundary_event=True,retained_current_window=True,retained_complete_OPs=True,
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
