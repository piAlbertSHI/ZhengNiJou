"""Preserve the runtime family's gated cold state without replacing the frozen mainline."""
import argparse
import json
from pathlib import Path
import shutil

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Close_HeatDriveECC_SplitObservation import read,validate_gate


def close(study,measurements,output):
    repo=Path(__file__).resolve().parents[1];output=output.resolve()
    if output.exists() or output.parent!=repo/'outputs_storage_audit':raise ValueError('Use a fresh local archive')
    family=study/'native/runtime_boundary_family';record=read(family/'runtime_boundary_family.json')
    observed=read(measurements);cold=family/'cold_C002';manifest=read(cold/'packet_manifest.json')
    validate_gate(read(cold/'packet_gate.json'))
    if (not record['experiment_completed'] or not record['same_family_parameter_compatible'] or
            record['old_complete_state_imported'] or not observed['recipe_comparison']['only_declared_change'] or
            observed['input_sha256']['family']!=sha256(family/'runtime_boundary_family.json') or
            observed['input_sha256']['runtime_observation']!=sha256(cold/'native/observations.mat')):
        raise ValueError('Require the completed actual family and shared physical recipe')
    for row in manifest['input_files']:
        if sha256(cold/row['path'])!=row['sha256']:raise ValueError('Changed cold input')
    if sha256(Path(record['baseline_complete_OP_path']))!=record['baseline_complete_OP_sha256']:
        raise ValueError('Changed runtime complete state')
    baseline,candidate=record['cases']
    if (not baseline['initial_states_bitwise_equal'] or not baseline['initial_native_bitwise_equal'] or
            not candidate['strict_vendor_restore_pass'] or not candidate['retained_memories_initial_bitwise_equal'] or
            not candidate['boundary_value_applied']):raise ValueError('Runtime tuning proof incomplete')
    copies=[];retained=[];output.mkdir()
    allowed={'packet_manifest.json','packet_gate.json','mechanism.json','simulation_start.json','probe_start.json'}
    for source in study.rglob('*'):
        if not source.is_file():continue
        relative=source.relative_to(study)
        if any(part in ('cache','codegen') for part in relative.parts):
            category='regenerable_build_cache_retained_not_authority'
        elif source.suffix=='.mat':category='single_execution_scientific_or_construction_MAT'
        else:category='single_execution_metadata_or_log'
        row=dict(path=str(source),bytes=source.stat().st_size,sha256=sha256(source),classification=category)
        if source.name in allowed and source.stat().st_size<1024**2:
            destination=output/'runtime_family'/relative;destination.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(source,destination)
            if sha256(destination)!=row['sha256']:raise ValueError('Archive changed bytes')
            copies.append(dict(**row,archive_relative=str(destination.relative_to(output))))
        else:retained.append(row)
    proofs=[family/'runtime_boundary_family.json',measurements,cold/'packet_gate.json',cold/'packet_manifest.json',
            family/'runtime_positive_control/probe_result.json',family/'runtime_Tc_candidate/probe_result.json']
    for label in ('runtime_positive_control','runtime_Tc_candidate'):
        raw=family/label/'measured_probe.mat';entry=read(family/label/'probe_result.json')
        if sha256(raw)!=entry['measured_probe_sha256']:raise ValueError('Changed tuning measurement')
        proofs.append(raw)
    qualification=dict(schema='heatdrive_ecc_runtime_boundary_cold_endpoint_v1',source_producer=record['producer'],
        independent_model_family=True,source_packet_root=str(cold),snapshot_time_s=20,total_cycles=2,
        operating_point_path=record['baseline_complete_OP_path'],operating_point_sha256=record['baseline_complete_OP_sha256'],
        temperature_K=276.95,temperature_configurability='runtime',checksum_policy='error/error',
        native_history_cap_cycles=2,state_history_cap_cycles=11,command_horizon_cycles=200,
        original_73_mechanism_checks_pass=True,six_local_inventory_gates_pass=True,modeled_energy_closure_pass=True,
        cold_baseline_complete_OP_loaded_after_all_gates=True,
        unchanged_restore_initial_states_and_native_bitwise_equal=True,runtime_0p1K_change_strict_restore_pass=True,
        all_four_memories_initial_bitwise_equal=True,old_model_OP_imported=False,
        numerical_trajectory_bitwise_equivalent_to_compiletime_family=False,
        baseline_trajectory_difference_is_quantified=True,temperature_step_has_prescribed_node_storage_jump=True,
        next_action='Same-family bounded transient warmup from intact C2; gate each actual complete-cycle packet before state propagation. Exclude boundary-transition cycles from later periodic outer metrics.',
        steady_parameter_study_allowed=False,production_recovery_allowed=False,outer_solve_eligible=False,
        table4_reproduction_claim=False,C200_and_C72_reference_unchanged=True,
        files=[dict(path=str(path.resolve()),sha256=sha256(path)) for path in proofs])
    q=output/'endpoint_qualification.json';q.write_text(json.dumps(qualification,indent=2)+'\n',encoding='utf-8')
    receipt=dict(compact_copies=copies,single_execution_files=retained,raw_copied_bytes=0,raw_deleted_bytes=0,
                 cache_deleted_bytes=0,excluded_large_array_JSON_from_Git=True)
    (output/'storage_receipt.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    pointer=repo/'verification/current_runtime_boundary_cold_family.json'
    if pointer.exists():raise FileExistsError('Do not overwrite an existing family pointer')
    pointer.write_text(json.dumps(dict(schema=qualification['schema'],snapshot_time_s=20,total_cycles=2,
        qualification_relative=str(q.relative_to(repo)),qualification_sha256=sha256(q),
        operating_point_path=qualification['operating_point_path'],operating_point_sha256=qualification['operating_point_sha256'],
        production_recovery_allowed=False,outer_solve_eligible=False,steady_parameter_study_allowed=False),indent=2)+'\n',encoding='utf-8')
    return dict(qualified_cold_snapshot_s=20,source_OP_sha256=qualification['operating_point_sha256'],
                compact_files=len(copies),compact_bytes=sum(row['bytes'] for row in copies),
                retained_single_execution_bytes=sum(row['bytes'] for row in retained),qualified_for_steady_outer=False)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('study','measurements','output'):parser.add_argument('--'+name,required=True,type=Path)
    print(json.dumps(close(**vars(parser.parse_args())),indent=2))
