"""Freeze one completed same-case budget and its real split/physical evidence."""
import argparse
from pathlib import Path
import shutil

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Close_HeatDriveECC_SplitObservation import read, validate_gate, validate_comparison, compact_evidence
from Close_HeatDriveECC_SensitivityColdCase import write
from Close_HeatDriveECC_RuntimeWarmup import packet_cycles
from Verify_HeatDriveECC_ObservationPacket import validate_manifest
from HeatDriveECC_PublicPeriodicity import audit_public_statistics


def close(collection,prepared,source_closeout,output):
    collection,prepared,output=collection.resolve(),prepared.resolve(),output.resolve()
    repo=Path(__file__).resolve().parents[1]
    if output.exists() or output.parent!=repo/'outputs_storage_audit':raise ValueError('Require a fresh compact archive')
    path=collection/'continuation_result.json';r=read(path);source=read(source_closeout)
    if (r['schema']!='heatdrive_ecc_sensitivity_continuation_v1' or not r['experiment_completed'] or r['error_message'] or
            not r['split_trajectory_comparison_pass'] or r['source_state_edited'] or r['state_reconstructed_or_reset'] or
            r['production_recovery_allowed'] or sha256(source_closeout)!=r['source_closeout_sha256'] or
            source['case_contract_sha256']!=r['case_contract_sha256']):raise ValueError('Incomplete or changed continuation')
    stop=r['last_verified_snapshot_time_s'];rows=r['completed_packets']
    if stop!=r['planned_window_s'][1] or len(rows)*20!=stop-200:raise ValueError('Incomplete executed budget')
    split=Path(r['split_comparison_root']);protected={};parent=source['final_operating_point_sha256'];chain=[]

    def verify_packet(packet):
        m=read(packet/'packet_manifest.json');g=read(packet/'packet_gate.json');validate_manifest(m);validate_gate(g)
        if g['input_sha256']['manifest']!=sha256(packet/'packet_manifest.json'):raise ValueError('Changed gate binding')
        if m['sensitivity_case_contract_sha256']!=r['case_contract_sha256']:raise ValueError('Cross-case input')
        for item in m['input_files']:
            p=(packet/item['path']).resolve()
            if not p.is_relative_to(packet.resolve()) or sha256(p)!=item['sha256']:raise ValueError('Changed packet evidence')
            protected[str(p)]=item['sha256']
        op=packet/'comparison_only_complete_op.mat'
        if sha256(op)!=m['complete_OP_sha256']:raise ValueError('Changed complete state')
        protected[str(op)]=m['complete_OP_sha256']
        return m,g

    for name in ('reference','prefix','suffix'):verify_packet(split/name)
    for name in ('prefix','suffix'):
        p=split/(name+'_comparison.json');comparison=read(p);validate_comparison(comparison)
        if sha256(p)!=r[name+'_comparison_sha256']:raise ValueError('Changed split trajectory proof')
    cycles=list(source['cycles'])
    for k,row in enumerate(rows):
        packet=Path(row['packet_root']);m,g=verify_packet(packet)
        if (m['packet_role']!='runtime_sensitivity_continuation' or m['window_s']!=[200+20*k,220+20*k] or
                m['parent_complete_OP_sha256']!=parent or m['complete_OP_sha256']!=row['operating_point_sha256']):
            raise ValueError('Broken same-case continuation chain')
        b=read(packet/'boundary_comparison.json');validate_comparison(b)
        if (not b['retained_memories_bitwise_equal'] or b['retained_memory_count']!=4 or
                b['candidate_observation_sha256']!=sha256(packet/'native/observations.mat') or
                b['candidate_state_sha256']!=sha256(packet/'observed_states.mat')):raise ValueError('Changed boundary proof')
        parent=m['complete_OP_sha256'];cycles.extend(packet_cycles(packet))
        chain.append(dict(packet_root=str(packet),window_s=m['window_s'],operating_point_sha256=parent,
            gate_sha256=sha256(packet/'packet_gate.json'),energy_residual_J=g['modeled_energy_balance']['external_heat_minus_total_storage_J']))
    if [c['cycle'] for c in cycles]!=list(range(1,int(stop/10)+1)):raise ValueError('Missing actual cycle metrics')
    output.mkdir();frozen=collection/f'completed_to_{stop}_{sha256(path)}.json'
    if frozen.exists():
        if sha256(frozen)!=sha256(path):raise ValueError('Existing frozen budget differs')
    else:shutil.copyfile(path,frozen)
    copies=[];inventory=[]
    for label,root in (('collection',collection),('prepared',prepared)):
        for p in sorted(root.rglob('*')):
            if not p.is_file():continue
            rel=p.relative_to(root);size=p.stat().st_size
            row=dict(path=str(p),bytes=size,sha256=sha256(p))
            cache=bool({'cache','codegen','component_build','buffer_component_build'}.intersection(rel.parts))
            if not cache and compact_evidence(p,size):
                destination=output/label/rel;destination.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,destination)
                if sha256(destination)!=row['sha256']:raise ValueError('Compact copy changed')
                copies.append(dict(**row,archive_relative=str(destination.relative_to(output))))
            else:inventory.append(dict(**row,classification='regenerable_cache' if cache else 'current_same_case_raw_or_dependency',action='retain_single_execution_copy'))
    for suffix in ('.preflight_config.json','.stdout.log','.stderr.log','.matlab.log'):
        p=Path(str(prepared)+suffix)
        if p.exists():
            shutil.copyfile(p,output/p.name)
            copies.append(dict(path=str(p),bytes=p.stat().st_size,sha256=sha256(p),archive_relative=p.name))
    check=r['latest_public_periodicity'];target=r['latest_target_precision']
    public_review=audit_public_statistics(check['statistics'])
    for name in ('measured_window','thermal_statistics'):
        if sha256(Path(check[name+'_path']))!=check[name+'_sha256']:raise ValueError('Changed current statistics')
    summary=dict(schema='heatdrive_ecc_sensitivity_continuation_closeout_v1',case_index=r['case_index'],
        producer=r['producer'],latest_execution_producer=r['latest_execution_producer'],completed_cycles=int(stop/10),
        frozen_result_path=str(frozen),frozen_result_sha256=sha256(frozen),source_closeout_sha256=sha256(source_closeout),
        case_contract_sha256=r['case_contract_sha256'],final_operating_point_sha256=parent,packet_chain=chain,cycles=cycles,
        all_original_packet_gates_pass=True,split_trajectory_comparison_pass=True,
        split_trajectory_comparison_bitwise=r['split_trajectory_comparison_bitwise'],split_scope_s=[200,220],
        complete_hidden_state_serialization_universally_proven=False,
        public_periodicity=check['statistics'],
        target_precision={k:v for k,v in target.items() if k not in ('cycles','input_manifests')},
        true_public_thermal_predicates=['endpoint_T','same_phase_T_P99','same_phase_T_RMS','phase_extrema','same_phase_phase_P99','same_phase_phase_RMS'],
        same_phase_temperature_max_is_a_public_gate=False,full_internal_state_periodicity_verified=False,
        independent_public_predicate_review=public_review,
        steady_orthogonal_effects_evaluated=False,C200_gap_attribution_authorized=False,
        production_recovery_allowed=False,outer_solve_eligible=False,table4_reproduction_claim=False)
    write(output/'continuation_closeout.json',summary)
    receipt=dict(compact_copies=copies,retained_single_execution_files=inventory,protected_packet_inputs=protected,
        raw_copied_bytes=0,raw_deleted_bytes=0,cache_deleted_bytes=0,compact_copied_bytes=sum(c['bytes'] for c in copies),
        retained_single_execution_bytes=sum(c['bytes'] for c in inventory))
    write(output/'storage_receipt.json',receipt)
    return dict(completed_cycles=int(stop/10),public_periodic=check['periodic_steady_state'],
        target_precision_pass=target['precision_pass'],summary_sha256=sha256(output/'continuation_closeout.json'),
        compact_copied_bytes=receipt['compact_copied_bytes'],retained_single_execution_bytes=receipt['retained_single_execution_bytes'])


if __name__=='__main__':
    import json
    p=argparse.ArgumentParser(description=__doc__)
    for key in ('collection','prepared','source-closeout','output'):p.add_argument('--'+key,type=Path,required=True)
    print(json.dumps(close(**vars(p.parse_args())),indent=2))
