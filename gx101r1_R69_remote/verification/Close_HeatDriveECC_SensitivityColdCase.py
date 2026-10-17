"""Seal a completed case without granting steady-response or cross-case authority."""
import argparse
import json
from pathlib import Path
import shutil

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Close_HeatDriveECC_SplitObservation import read, validate_gate, validate_comparison, compact_evidence
from Close_HeatDriveECC_RuntimeWarmup import packet_cycles
from Verify_HeatDriveECC_ObservationPacket import validate_manifest


def write(path, value):
    path.write_text(json.dumps(value, indent=2, allow_nan=False)+'\n', encoding='utf-8')


def execution_budget(experiment,output):
    if output.exists():raise FileExistsError('Never overwrite timing evidence')
    rows=[]
    for packet in sorted((experiment/'native/sensitivity_cold_case').glob('packet_C*')):
        path=packet/'simulation_timing.json';r=read(path);v=r['vendor_timing']
        if not r['metadata_available'] or r['simulation_settings_changed'] or r['timing_is_physical_gate']:
            raise ValueError('Incomplete or wrongly scoped timing record')
        rows.append(dict(window_s=r['window_s'],source_path=str(path),source_sha256=sha256(path),
            sim_call_wall_s=r['sim_call_wall_s'],initialization_s=v['InitializationElapsedWallTime'],
            execution_s=v['ExecutionElapsedWallTime'],termination_s=v['TerminationElapsedWallTime']))
    if len(rows)!=10:raise ValueError('Require all ten actual packet timings')
    totals={key:sum(r[key] for r in rows) for key in ('sim_call_wall_s','initialization_s','execution_s','termination_s')}
    write(output,dict(schema='heatdrive_ecc_sensitivity_execution_budget_v1',packets=rows,totals_s=totals,
        execution_fraction_of_sim_call=totals['execution_s']/totals['sim_call_wall_s'],
        timing_is_physical_gate=False,settings_changed=False,
        interpretation='Actual model execution dominates; cache cleanup alone cannot remove this cost. Benchmark a state-equivalent execution path before a long steady L8 cohort.',
        acceleration_validated=False))


def close(experiment, output):
    experiment=experiment.resolve();output=output.resolve()
    if (experiment/'HISTORICAL_COLD_PREFIX_RAW_RETIRED.json').exists():
        raise ValueError('Cold prefix raw was deliberately retired; use its sealed closeout, not a new physical-failure claim')
    repo=Path(__file__).resolve().parents[1]
    if output.exists() or output.parent != repo/'outputs_storage_audit':
        raise ValueError('Require a fresh compact archive in the calling repository')
    folder=experiment/'native/sensitivity_cold_case';path=folder/'case_result.json';r=read(path)
    if (r['schema']!='heatdrive_ecc_runtime_sensitivity_cold_result_v1' or r['probe_only'] or
            not r['experiment_completed'] or r['error_message'] or r['coordinate_count']!=204 or
            not r['coordinate_match_pass'] or not r['full_cycle_gates_evaluated'] or
            not r['all_original_packet_gates_pass'] or r['completed_cold_cycles']!=20 or
            r['last_verified_snapshot_time_s']!=200 or len(r['completed_packets'])!=10 or
            r['source_state_imported'] or r['production_recovery_allowed'] or r['orthogonal_effects_evaluated']):
        raise ValueError('Not a completed twenty-cycle independent cold case')
    coordinates=r['coordinate_comparisons']
    if len(coordinates)!=204 or any(not c['pass'] or abs(c['actual']-c['expected'])>c['limit'] for c in coordinates):
        raise ValueError('Original initial-coordinate comparison failed')
    contract=experiment/'native/sensitivity_case_contract.json';case_hash=sha256(contract)
    chain=[];cycles=[];parent='';protected={};maximum_energy_residual=0
    for k,row in enumerate(r['completed_packets']):
        packet=Path(row['packet_root']);m=read(packet/'packet_manifest.json');g=read(packet/'packet_gate.json')
        validate_manifest(m);validate_gate(g)
        if (m['window_s']!=[20*k,20*(k+1)] or m['sensitivity_case_contract_sha256']!=case_hash or
                m['parent_complete_OP_sha256']!=parent or m['complete_OP_sha256']!=row['operating_point_sha256'] or
                g['input_sha256']['manifest']!=sha256(packet/'packet_manifest.json') or
                not g['sensitivity_parameter_review']['all_declared_parameters_match']):
            raise ValueError('Broken immutable same-case chain')
        for item in m['input_files']:
            p=(packet/item['path']).resolve()
            if not p.is_relative_to(packet.resolve()) or sha256(p)!=item['sha256']:
                raise ValueError('Changed packet input')
            protected[str(p)]=item['sha256']
        op=packet/'comparison_only_complete_op.mat'
        if sha256(op)!=m['complete_OP_sha256']:raise ValueError('Changed Operating Point')
        protected[str(op)]=m['complete_OP_sha256']
        if k:
            b=read(packet/'boundary_comparison.json');validate_comparison(b)
            if (not b['retained_memories_bitwise_equal'] or b['retained_memory_count']!=4 or
                    b['candidate_observation_sha256']!=sha256(packet/'native/observations.mat') or
                    b['candidate_state_sha256']!=sha256(packet/'observed_states.mat')):
                raise ValueError('Changed observed boundary or route memory')
        cycles.extend(packet_cycles(packet));parent=m['complete_OP_sha256']
        maximum_energy_residual=max(maximum_energy_residual,abs(g['modeled_energy_balance']['external_heat_minus_total_storage_J']))
        chain.append(dict(packet_root=str(packet),window_s=m['window_s'],operating_point_sha256=parent,
                          gate_sha256=sha256(packet/'packet_gate.json')))
    if [c['cycle'] for c in cycles]!=list(range(1,21)):raise ValueError('Incomplete cycle metrics')
    check=r['current_public_periodicity'];target=r['current_target_precision']
    if check['window_s']!=[100,200] or target['window_s']!=[100,200]:raise ValueError('Wrong current window')
    for name in ('measured_window','thermal_statistics'):
        if sha256(Path(check[name+'_path']))!=check[name+'_sha256']:raise ValueError('Changed current statistics')
    output.mkdir();copies=[];inventory=[]
    excluded={'cache','codegen','component_build','buffer_component_build'}
    for p in sorted(experiment.rglob('*')):
        if not p.is_file():continue
        relative=p.relative_to(experiment);size=p.stat().st_size
        row=dict(path=str(p),bytes=size,sha256=sha256(p))
        if not excluded.intersection(relative.parts) and compact_evidence(p,size):
            destination=output/'evidence'/relative;destination.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(p,destination)
            if sha256(destination)!=row['sha256']:raise ValueError('Compact archive mismatch')
            copies.append(dict(**row,archive_relative=str(destination.relative_to(output))))
        else:
            category='regenerable_build_cache' if excluded.intersection(relative.parts) else 'current_case_raw_or_constructor_dependency'
            inventory.append(dict(**row,classification=category,action='retain_single_execution_copy'))
    for suffix in ('.preflight_config.json','.stdout.log','.stderr.log','.matlab.log'):
        p=Path(str(experiment)+suffix)
        if p.exists():
            destination=output/p.name;shutil.copyfile(p,destination)
            copies.append(dict(path=str(p),bytes=p.stat().st_size,sha256=sha256(p),archive_relative=destination.name))
    summary=dict(schema='heatdrive_ecc_runtime_sensitivity_cold_closeout_v1',producer=r['producer'],
        source_result_path=str(path),source_result_sha256=sha256(path),case_index=r['case_index'],
        case_contract_sha256=case_hash,terminal_exit_code=0,completed_cycles=20,
        coordinate_count=204,maximum_initial_coordinate_tolerance_ratio=max(abs(c['actual']-c['expected'])/c['limit'] for c in coordinates),
        all_ten_original_packet_gates_pass=True,nine_recorded_boundaries_bitwise_equal=True,
        four_route_memories_preserved_at_each_recorded_boundary=True,
        maximum_packet_energy_residual_J=maximum_energy_residual,packet_chain=chain,
        final_operating_point_sha256=parent,cycles=cycles,
        public_periodicity=check['statistics'],target_precision={k:v for k,v in target.items() if k not in ('cycles','input_manifests')},
        vendor_persistent_variable_restore_warning_requires_separate_equivalence_review=True,
        complete_hidden_state_restore_equivalence_proven=False,steady_sensitivity_response_qualified=False,
        full_orthogonal_effects_evaluated=False,C200_gap_attribution_authorized=False,
        production_recovery_allowed=False,table4_reproduction_claim=False)
    write(output/'case_closeout.json',summary)
    receipt=dict(compact_copies=copies,retained_single_execution_files=inventory,
        protected_packet_inputs=protected,raw_copied_bytes=0,raw_deleted_bytes=0,cache_deleted_bytes=0,
        compact_copied_bytes=sum(c['bytes'] for c in copies),
        retained_single_execution_bytes=sum(c['bytes'] for c in inventory),
        classification='current nominal cold control, keep raw until compatible same-case continuation is qualified')
    write(output/'storage_receipt.json',receipt)
    return dict(completed_cycles=20,public_periodic=check['periodic_steady_state'],
                target_precision_pass=target['precision_pass'],summary_sha256=sha256(output/'case_closeout.json'),
                compact_copied_bytes=receipt['compact_copied_bytes'],retained_single_execution_bytes=receipt['retained_single_execution_bytes'])


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--experiment',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    print(json.dumps(close(**vars(p.parse_args())),indent=2))
