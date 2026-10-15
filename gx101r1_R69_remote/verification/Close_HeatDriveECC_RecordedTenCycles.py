"""Seal the completed recording endpoint and compact evidence, not a production recovery claim."""
import argparse
import json
from pathlib import Path
import shutil

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Close_HeatDriveECC_SplitObservation import read, validate_gate


def close(collection, measured, thermal, output):
    output=output.resolve()
    repo=Path(__file__).resolve().parents[1]
    if output.exists() or output.resolve().parent != (repo/'outputs_storage_audit').resolve():
        raise ValueError('Use a fresh local compact archive')
    observation, original, result=read(measured),read(thermal),read(collection/'collection_result.json')
    if (not result['pass'] or result['last_verified_snapshot_time_s'] != 720 or
            original['measured_window_sha256'] != sha256(measured) or
            not original['original_production_statistics_used'] or not original['statistics']['periodic_steady_state'] or
            len(observation['packets']) != 5 or len(observation['native_temperatures']) != 119 or
            len(observation['native_explicit_inventories']) != 12):
        raise ValueError('This closeout requires the actual completed C72 observation')
    copies,retained,chain=[],[],[]
    evidence_files=[]
    parent=read(collection/'initial_recording_contract.json')['operating_point_sha256']
    for row in result['completed_packets']:
        packet=Path(row['packet_root']);manifest=read(packet/'packet_manifest.json')
        gate=read(packet/'packet_gate.json');validate_gate(gate)
        boundary=read(packet/'boundary_comparison.json')
        if (gate['input_sha256']['manifest'] != sha256(packet/'packet_manifest.json') or
                manifest['complete_OP_sha256'] != row['operating_point_sha256'] or
                manifest['parent_complete_OP_sha256'] != parent or
                sha256(packet/'comparison_only_complete_op.mat') != manifest['complete_OP_sha256'] or
                not boundary['pass'] or not boundary['retained_memories_bitwise_equal'] or
                not all(boundary[key]['bitwise_values_equal'] for key in ('states','native','sources','public'))):
            raise ValueError('Broken actual packet chain')
        for item in manifest['input_files']:
            if sha256(packet/item['path']) != item['sha256']:
                raise ValueError('Changed evidence')
        parent=manifest['complete_OP_sha256']
        chain.append(dict(packet_root=str(packet), window_s=manifest['window_s'], operating_point_sha256=parent,
                          gate_sha256=sha256(packet/'packet_gate.json'), boundary_sha256=sha256(packet/'boundary_comparison.json')))
    output.mkdir()
    compact_names={'packet_manifest.json','packet_gate.json','boundary_comparison.json','mechanism.json',
                   'packet_gate_stdout.log','simulation_start.json','collection_result.json','collection_progress.json',
                   'initial_recording_contract.json','initial_prepared_recipe.json'}
    for path in collection.rglob('*'):
        if not path.is_file():continue
        row=dict(path=str(path), bytes=path.stat().st_size, sha256=sha256(path))
        if path.name in compact_names and row['bytes'] < 2*1024**2:
            target=output/'collection'/path.relative_to(collection)
            target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(path,target)
            if sha256(target) != row['sha256']:raise ValueError('Archive differs')
            copies.append(dict(**row, archive_relative=str(target.relative_to(output))))
        else:
            retained.append(dict(**row, classification='single_execution_copy_required_for_native_window_and_state_proof'))
    for path in (measured,thermal,collection/'collection_result.json'):
        evidence_files.append(dict(path=str(path.resolve()),sha256=sha256(path)))
    endpoint=Path(result['last_verified_packet_root'])
    qualification=dict(schema='heatdrive_ecc_completed_native_observation_endpoint_v1', total_cycles=72,
        snapshot_time_s=720,source_packet_root=str(endpoint),operating_point_path=str(endpoint/'comparison_only_complete_op.mat'),
        operating_point_sha256=parent,source_producer=result['producer'],
        complete_vendor_OP_loaded_after_gates_by_collector=True,partial_state_restore_used=False,source_state_edited=False,
        actual_native_observation_window_s=[620,720],complete_native_ten_cycle_window_collected=True,
        packet_chain=chain,all_original_packet_gates_pass=True,all_four_boundaries_bitwise_equal=True,
        original_public_thermal_periodicity_pass=True,complete_internal_state_periodicity_verified=False,
        unresolved_state_observation='SMA buffers continue energy/mass migration despite passing public thermal criteria',
        checksum_policy='error/error',native_history_cap_cycles=2,state_history_cap_cycles=11,command_horizon_cycles=200,
        source_C62_pointer_unchanged=True,source_C64_recording_pointer_unchanged=True,C200_authority_unchanged=True,
        next_use='Complete C72 diagnostic state; use only an explicitly compatible continuation recipe and bounded scope. Never reset state or substitute C200.',
        production_recovery_allowed=False,outer_solve_eligible=False,table4_reproduction_claim=False,files=evidence_files)
    (output/'endpoint_qualification.json').write_text(json.dumps(qualification,indent=2)+'\n',encoding='utf-8')
    receipt=dict(compact_copies=copies,retained_single_execution_files=retained,
                 raw_copied_bytes=0,raw_deleted_bytes=0,cache_deleted_bytes=0)
    (output/'storage_receipt.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    finalize_pointer(output)
    return dict(compact_files=len(copies),compact_bytes=sum(row['bytes'] for row in copies),
                single_execution_bytes=sum(row['bytes'] for row in retained),endpoint_time_s=720,
                qualification_sha256=sha256(output/'endpoint_qualification.json'))


def finalize_pointer(output):
    output=output.resolve();repo=Path(__file__).resolve().parents[1]
    if output.parent != repo/'outputs_storage_audit':raise ValueError('Not a local archive')
    qualification=read(output/'endpoint_qualification.json');receipt=read(output/'storage_receipt.json')
    for row in qualification['files']:
        if sha256(Path(row['path'])) != row['sha256']:raise ValueError('Changed closeout evidence')
    for row in qualification['packet_chain']:
        root=Path(row['packet_root'])
        if sha256(root/'packet_gate.json') != row['gate_sha256'] or sha256(root/'boundary_comparison.json') != row['boundary_sha256']:
            raise ValueError('Changed chain proof')
        validate_gate(read(root/'packet_gate.json'))
        boundary=read(root/'boundary_comparison.json')
        if not all(boundary[key]['bitwise_values_equal'] for key in ('states','native','sources','public')):
            raise ValueError('Do not claim bitwise boundaries from tolerance-only comparisons')
    for row in receipt['compact_copies']:
        if sha256(output/row['archive_relative']) != row['sha256']:raise ValueError('Changed compact copy')
    if sha256(Path(qualification['operating_point_path'])) != qualification['operating_point_sha256']:
        raise ValueError('Changed complete endpoint')
    pointer=repo/'verification/current_completed_observation_endpoint.json'
    if pointer.exists():raise FileExistsError('Review the existing endpoint before replacing a pointer')
    pointer.write_text(json.dumps(dict(schema=qualification['schema'],total_cycles=72,snapshot_time_s=720,
        qualification_relative=str((output/'endpoint_qualification.json').relative_to(repo)),
        qualification_sha256=sha256(output/'endpoint_qualification.json'),
        operating_point_path=qualification['operating_point_path'],operating_point_sha256=qualification['operating_point_sha256'],
        production_recovery_allowed=False,outer_solve_eligible=False,table4_reproduction_claim=False),indent=2)+'\n',encoding='utf-8')
    return dict(pointer=str(pointer),qualification_sha256=sha256(output/'endpoint_qualification.json'))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for key in ('collection','measured','thermal','output'):
        parser.add_argument('--'+key,required=True,type=Path)
    parser.add_argument('--finalize-existing',action='store_true')
    args=vars(parser.parse_args());finalize=args.pop('finalize_existing')
    print(json.dumps(finalize_pointer(args['output']) if finalize else close(**args),indent=2))
