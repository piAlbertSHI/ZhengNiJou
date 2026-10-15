"""Seal real split evidence and a bounded transient recording endpoint; never production authority."""
import argparse
import json
from pathlib import Path
import shutil

from Audit_HeatDriveECC_SegmentedEvidence import sha256


REGENERATED_METADATA = {'distributed_pressure_ff_contract.json', 'thermal_connectivity.json',
                        'tl_connectivity.json', 'inventory_metadata.json',
                        'public_inventory_targets.json', 'runtime_inventory_targets.json'}


def compact_evidence(path, size):
    return (path.name not in REGENERATED_METADATA and path.suffix.lower() in ('.json', '.log', '.txt', '.csv')
            and size <= 8*1024**2)


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def validate_comparison(record):
    expected = {'states': (74, 1414), 'native': (1262, None), 'sources': (162, None), 'public': (201, None)}
    if not record['pass']:
        raise ValueError('Split comparison failed')
    for key, (count, channels) in expected.items():
        row = record[key]
        if (not row['pass'] or not row['bitwise_values_equal'] or row['trace_count'] != count or
                row['max_tolerance_ratio'] != 0 or (channels and row['channel_count'] != channels)):
            raise ValueError('Incomplete or nonidentical split evidence: '+key)


def validate_gate(gate):
    energy = gate['modeled_energy_balance']
    if (not gate['gate_pass'] or gate['original_mechanism_count'] != 73 or not gate['original_mechanism_pass'] or
            gate['six_local_inventory_gates'] != [True]*6 or gate['storage_count'] != 119 or gate['source_count'] != 49 or
            not energy['model_equation_energy_closure_pass'] or energy['energy_tolerance_J'] != 1e-8 or
            abs(energy['external_heat_minus_total_storage_J']) > 1e-8 or
            abs(energy['numerical_terms_retained_residual_J']) > 1e-8 or
            len(gate['flow_gates']) != 6 or
            not all(row['selected_flow_gate'] for row in gate['flow_gates']) or
            gate['production_recovery_allowed'] or gate['outer_solve_eligible']):
        raise ValueError('No failed, relaxed, incomplete or promoted packet may be sealed')


def close(study, reference_review, typed_path, parent_path, output):
    study, reference_review, output = map(lambda p: p.resolve(), (study, reference_review, output))
    repo = Path(__file__).resolve().parents[1]
    if output.exists() or output.parent != repo/'outputs_storage_audit':
        raise ValueError('Require a new archive directly inside the calling repository audit root')
    split = study/'native/split_observation'
    proof = read(split/'split_observation_preflight.json')
    parent = read(parent_path)
    if (not proof['pass'] or proof['error_message'] or proof['full_window_s'] != [620, 640] or
            proof['split_time_s'] != 630 or proof['history_cap_cycles'] != 2 or proof['state_history_cap_cycles'] != 11 or
            proof['checksum_policy'] != 'error/error' or proof['source_state_edited'] or proof['physical_parameters_changed'] or
            proof['production_recovery_allowed'] or proof['source_operating_point_sha256'] != parent['operating_point_sha256'] or
            proof['source_history_sha256'] != parent['history_sha256']):
        raise ValueError('Require the completed original-C62 strict split experiment')
    parent_root = Path(parent['execution_repo'])/parent['source_root_relative']
    for kind in ('operating_point', 'history'):
        if sha256(parent_root/parent[kind+'_relative']) != parent[kind+'_sha256']:
            raise ValueError('Parent C62 changed')
    review = read(reference_review)
    if (not review['mechanism_pass'] or not review['reference_comparison_only'] or
            sha256(Path(review['packet_gate_path'])) != review['packet_gate_sha256'] or
            sha256(Path(review['mechanism_review_path'])) != review['mechanism_review_sha256']):
        raise ValueError('Continuous reference review incomplete')
    reference = Path(review['source_packet_root'])
    validate_gate(read(review['packet_gate_path']))
    packets = {'reference': reference, 'prefix': split/'prefix', 'suffix': split/'suffix'}
    input_files = [split/'split_observation_preflight.json', reference_review, typed_path, parent_path]
    for label in ('prefix', 'suffix'):
        comparison = split/(label+'_comparison.json')
        validate_comparison(read(comparison))
        validate_gate(read(packets[label]/'packet_gate.json'))
        input_files.append(comparison)
    for label, packet in packets.items():
        manifest_file = packet/'packet_manifest.json'
        manifest = read(manifest_file)
        for row in manifest['input_files']:
            if sha256(packet/row['path']) != row['sha256']:
                raise ValueError('Changed actual packet input: '+label+'/'+row['path'])
        if sha256(packet/'comparison_only_complete_op.mat') != manifest['complete_OP_sha256']:
            raise ValueError('Comparison OP changed')
        input_files.append(manifest_file)
    endpoint = packets['suffix']
    manifest = read(endpoint/'packet_manifest.json')
    typed = read(typed_path)
    if (Path(typed['packet_root']).resolve() != endpoint.resolve() or not typed['complete_vendor_OP_loaded'] or
            typed['snapshot_time_s'] != 640 or typed['source_state_edited'] or typed['simulation_executed'] or
            typed['actual_class'] not in ('Simulink.op.ModelOperatingPoint', 'Simulink.SimulationOperatingPoint') or
            typed['operating_point_sha256'] != manifest['complete_OP_sha256'] or
            typed['packet_manifest_sha256'] != sha256(endpoint/'packet_manifest.json')):
        raise ValueError('Actual complete vendor endpoint loading is unproven')
    output.mkdir()
    copies, retained = [], []
    execution_outputs = study.parent
    roots = [execution_outputs/'v47_C62_recording_split_preflight_r1',
             execution_outputs/'v47_C62_recording_split_preflight_r2', study, reference_review.parent]
    for root in roots:
        for source in root.rglob('*'):
            if not source.is_file() or any(part in ('cache', 'codegen') for part in source.relative_to(root).parts):
                continue
            relative = source.relative_to(root)
            row = dict(path=str(source), bytes=source.stat().st_size, sha256=sha256(source))
            if compact_evidence(source, source.stat().st_size):
                destination = output/root.name/relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, destination)
                if sha256(destination) != row['sha256']:
                    raise ValueError('Archive bytes changed')
                copies.append(dict(**row, archive_relative=str(destination.relative_to(output))))
            else:
                retained.append(dict(**row, classification='retained_single_execution_copy'))
        for suffix in ('.preflight_config.json', '.matlab_stdout.log', '.matlab_stderr.log'):
            source = Path(str(root)+suffix)
            if source.is_file():
                destination = output/source.name
                shutil.copyfile(source, destination)
                copies.append(dict(path=str(source), bytes=source.stat().st_size, sha256=sha256(source),
                                   archive_relative=destination.name))
    for kind in ('operating_point', 'history'):
        if sha256(parent_root/parent[kind+'_relative']) != parent[kind+'_sha256']:
            raise ValueError('Parent C62 changed while archiving')
    qualification = dict(schema='heatdrive_ecc_bounded_observation_endpoint_v1',
        source_packet_root=str(endpoint), snapshot_time_s=640, total_cycles=64,
        operating_point_path=str(endpoint/'comparison_only_complete_op.mat'),
        operating_point_sha256=typed['operating_point_sha256'], actual_class=typed['actual_class'],
        parent_C62_operating_point_sha256=parent['operating_point_sha256'],
        parent_C62_contract_path=str(parent_path.resolve()), split_comparison_root=str(split),
        source_producer=proof['producer'], native_history_cap_cycles=2, state_history_cap_cycles=11,
        command_horizon_cycles=200, checksum_policy='error/error', source_state_edited=False,
        complete_vendor_OP_independently_loaded=True, split_states_and_native_bitwise_equal=True,
        all_three_packets_mechanism_and_energy_pass=True,
        bounded_transient_observation_collection_allowed=True, next_collection_stop_s=720,
        additional_scope='Untouched diagnostic recording only, after full split and actual type proof; old comparison gates remain unchanged',
        current_mainline_recovery_source_changed=False, production_recovery_allowed=False,
        steady_outer_solve_allowed=False, ten_cycle_native_inventory_periodicity_verified=False,
        real_fluid_EOS_claim=False, table4_reproduction_claim=False,
        files=[dict(path=str(path.resolve()), sha256=sha256(path)) for path in input_files])
    (output/'bounded_observation_endpoint_qualification.json').write_text(
        json.dumps(qualification, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    receipt = dict(schema='heatdrive_ecc_split_observation_storage_v1', compact_copies=copies,
        retained_single_execution_files=retained, raw_copied_bytes=0, retired_raw_bytes=0, retired_cache_bytes=0,
        retained_reference_JSON_note='Historical 320 MB full-result JSON remains hash-bound; future packets use compact mechanism JSON',
        C62_unchanged=True, C200_untouched=True, Agent6_untouched=True)
    (output/'storage_receipt.json').write_text(json.dumps(receipt, indent=2)+'\n', encoding='utf-8')
    return dict(compact_copies=len(copies), retained_files=len(retained),
        retained_bytes=sum(row['bytes'] for row in retained), retired_raw_bytes=0,
        bounded_observation_endpoint_s=640, mainline_source_changed=False)


def compact_existing(output):
    output=output.resolve()
    repo=Path(__file__).resolve().parents[1]
    if output.parent != repo/'outputs_storage_audit':
        raise ValueError('Only this repository archive may be compacted')
    receipt_path=output/'storage_receipt.json'
    receipt=read(receipt_path)
    plan=[]
    for row in receipt['compact_copies']:
        if Path(row['path']).name not in REGENERATED_METADATA:
            continue
        target=(output/row['archive_relative']).resolve()
        source=Path(row['path'])
        if (not target.is_relative_to(output) or target.is_symlink() or not target.is_file() or
                sha256(target)!=row['sha256'] or sha256(source)!=row['sha256']):
            raise ValueError('Both archive duplicate and retained execution original must match')
        plan.append(dict(**row, archive_duplicate_path=str(target)))
    plan_path=output/'archive_metadata_copy_retirement_plan.json'
    if plan_path.exists():
        raise FileExistsError('Never replace a prior retirement plan')
    plan_path.write_text(json.dumps(plan,indent=2)+'\n',encoding='utf-8')
    for row in plan:
        Path(row['archive_duplicate_path']).unlink()
    removed={row['archive_relative'] for row in plan}
    receipt['compact_copies']=[row for row in receipt['compact_copies'] if row['archive_relative'] not in removed]
    receipt['retained_single_execution_files'].extend(dict(path=row['path'],bytes=row['bytes'],sha256=row['sha256'],
        classification='retained_execution_metadata_not_duplicated_into_Git') for row in plan)
    receipt['retired_archive_duplicate_bytes']=sum(row['bytes'] for row in plan)
    receipt['retired_archive_duplicate_count']=len(plan)
    receipt_path.write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    return dict(compact_copies=len(receipt['compact_copies']), retired_archive_duplicate_count=len(plan),
        retired_archive_duplicate_bytes=receipt['retired_archive_duplicate_bytes'],
        retired_raw_bytes=0, execution_originals_deleted=0)


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--study', required=True, type=Path)
    parser.add_argument('--reference-review', required=True, type=Path)
    parser.add_argument('--typed', required=True, type=Path)
    parser.add_argument('--parent', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--compact-existing',action='store_true')
    args=parser.parse_args()
    result=(compact_existing(args.output) if args.compact_existing else
            close(args.study,args.reference_review,args.typed,args.parent,args.output))
    print(json.dumps(result,indent=2))
