"""Compare joint target initialization with the frozen strict-OP probe."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C200RestoredSignals import compare
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field


def rows(path, registered_only=False):
    out={}
    with h5py.File(path) as f:
        if not registered_only:
            for name,r in f['signals'].items():
                out['signal/'+name]=('',r['time_s'][:].reshape(-1),r['values'][:])
            for ref in f['native'][:].flat:
                r=f[ref]
                key='native/'+text_field(r['block_path'])+'/'+text_field(r['state_name'])
                if key in out:
                    raise ValueError('Duplicate native identity')
                out[key]=(text_field(r['unit']),r['time_s'][:].reshape(-1),r['values'][:])
        if 'observation' in f:
            for ref in f['observation']['states'][:].flat:
                r=f[ref]
                key='state/'+text_field(r['block_path'])+'/'+text_field(r['state_name'])
                if key in out:
                    raise ValueError('Duplicate state identity')
                out[key]=(text_field(r['unit']),r['time_s'][:].reshape(-1),r['values'][:])
    return out


def compare_rows(reference, actual):
    if set(reference)!=set(actual):
        raise ValueError('Incomplete comparison coverage')
    result=[]
    for key,(unit,t,y) in reference.items():
        other_unit,other_t,other_y=actual[key]
        if (unit!=other_unit or not np.array_equal(t,[2000,2000.001])
                or not np.array_equal(t,other_t) or y.shape[-1]!=2 or other_y.shape!=y.shape):
            raise ValueError('Wrong unit, shape or sample grid: '+key)
        start=compare(y[...,0],other_y[...,0]); end=compare(y[...,1],other_y[...,1])
        result.append(dict(key=key,initial=start,one_step=end,
                           exact_initial=bool(np.array_equal(y[...,0],other_y[...,0])),
                           exact_one_step=bool(np.array_equal(y[...,1],other_y[...,1]))))
    return result


def compute(repo, root):
    origin=repo/'outputs_storage_audit/c200_source_compatibility_20260907'
    probe=origin/'archived_source_probe_v4'
    capture=json.loads((origin/'c200_state_capture_v1.json').read_text(encoding='utf-8-sig'))
    reference_path=probe/'restored_step_signals.mat'
    memory_path=probe/'registered_states.mat'
    if (sha256(reference_path)!=capture['input_sha256']['observed']
            or sha256(memory_path)!=capture['input_sha256']['registered']):
        raise ValueError('Strict reference changed')
    audit_path=root/'initialization_probe_audit.json'
    audit=json.loads(audit_path.read_text(encoding='utf-8-sig'))
    if (audit['schema']!='heatdrive_ecc_target_initialization_probe_v1' or not audit['computation_complete']
            or not audit['joint_initialization_attempted'] or audit['error_message']
            or any(audit[k] for k in ('production_recovery_allowed','strict_model_operating_point_restore',
                'source_operating_point_edited','packed_solver_state_imported','source_physical_model_changed',
                'state_preservation_verified','final_checkpoint_saved'))):
        raise ValueError('Unexpected joint initialization execution scope')
    if audit.get('method','').startswith('seeded_model_op'):
        if (not audit.get('seed_generated_model_op_used') or not audit.get('seeded_operating_point_memory_edited')
                or not audit.get('seed_target_preservation_pass') or len(audit.get('seed_target_matches',[]))!=125
                or any(not r['pass'] for r in audit['seed_target_matches'])):
            raise ValueError('Target-seeded OP did not preserve all prerequisite physical targets')
    path=root/'joint_initialization_observations.mat'
    if sha256(path)!=audit['observation_sha256']:
        raise ValueError('Probe observations changed')
    reference=rows(reference_path)
    reference.update(rows(memory_path,registered_only=True))
    actual=rows(path)
    comparisons=compare_rows(reference,actual)
    if len(comparisons)!=1474:
        raise ValueError('Require all 1474 observation groups')
    mapping_path=repo/'outputs_storage_audit/state_target_catalog_20260908/c200_target_mapping.json'
    mapping=json.loads(mapping_path.read_text(encoding='utf-8-sig'))
    if sha256(mapping_path)!=audit['mapping_sha256']:
        raise ValueError('Input target mapping changed')
    active={'native/heatdrive_ecc_coupled_se21/'+r['path'] for r in mapping['initialization_candidates']}
    targets=[r for r in comparisons if r['key'] in active]
    memories=[r for r in comparisons if r['key'].startswith('state/') and '/Solver Configuration/' not in r['key']]
    if len(targets)!=125 or len(memories)!=72:
        raise ValueError('Incomplete primary state preservation coverage')
    initial_pass=all(r['initial']['pass_endpoint_match'] for r in targets+memories)
    all_pass=all(r['initial']['pass_endpoint_match'] and r['one_step']['pass_endpoint_match'] for r in comparisons)
    result=dict(schema='heatdrive_ecc_joint_initialization_audit_v1',computation_complete=True,
        comparison_group_count=1474,initial_state_target_count=125,named_memory_group_count=72,
        initial_primary_state_preservation_pass=initial_pass,
        initial_target_failures=[r['key'] for r in targets if not r['initial']['pass_endpoint_match']],
        initial_memory_failures=[r['key'] for r in memories if not r['initial']['pass_endpoint_match']],
        failed_initial_groups=sum(not r['initial']['pass_endpoint_match'] for r in comparisons),
        failed_one_step_groups=sum(not r['one_step']['pass_endpoint_match'] for r in comparisons),
        exact_initial_groups=sum(r['exact_initial'] for r in comparisons),
        exact_one_step_groups=sum(r['exact_one_step'] for r in comparisons),
        all_observations_roundtrip_pass=all_pass,production_recovery_allowed=False,
        whole_model_first_law_verified=False,structural_migration_verified=False,
        checkpoint_saved=False,comparisons=comparisons,
        comparison_tolerance='Existing compare: absolute 1e-10 + relative 1e-11; no new relaxed gate.',
        execution_commit=audit['execution_commit'],
        input_sha256=dict(producer=sha256(audit_path),observed=sha256(path),reference=sha256(reference_path),
                          registered=sha256(memory_path),mapping=sha256(mapping_path)))
    if audit.get('converter_history_applied'):
        from Audit_HeatDriveECC_DigitalConverterHistory import compute as digital_compute
        digital_root=repo/'outputs_storage_audit/c200_converter_digital_history_20260908'
        digital_path=digital_root/'independent_digital_history_audit.json'
        digital=json.loads(digital_path.read_text(encoding='utf-8-sig'))
        records=audit['converter_history_records']
        if (digital_compute(repo,digital_root)!=digital or not digital['diagnostic_digital_memory_observation_pass']
                or len(records)!=42 or any(r['proof_sha256']!=sha256(digital_path)
                    or r['raw_sha256']!=digital['input_sha256']['raw'] for r in records)):
            raise ValueError('Digital snapshot evidence changed')
        converters=[r for r in comparisons if '/ConstitutiveHeatPS_' in r['key']]
        if len(converters)!=42:raise ValueError('Incomplete converter comparison')
        result['replayed_converter_count']=42
        result['exact_initial_converter_count']=sum(r['exact_initial'] for r in converters)
        result['digital_history_audit_sha256']=sha256(digital_path)
    if audit.get('differential_targets_applied'):
        metadata_path=repo/'outputs_storage_audit/c200_differential_target_metadata_20260908.json'
        metadata=json.loads(metadata_path.read_text(encoding='utf-8-sig'))
        dynamic={'native/heatdrive_ecc_coupled_se21/'+r['path']:r for r in metadata['targets'] if r['differential']}
        if len(dynamic)!=125 or any(r['eliminated'] for r in dynamic.values()):
            raise ValueError('Unexpected independent dynamic coordinates')
        records=audit['differential_target_records']
        selected={r['path'] for r in metadata['targets'] if r['differential'] or r['priority']!='None'}
        if len(records)!=196 or {r['path'] for r in records}!=selected:
            raise ValueError('Dynamic/algebraic target coverage changed')
        for record in records:
            key='native/heatdrive_ecc_coupled_se21/'+record['path'];unit,_,values=reference[key]
            if (record['reference_sha256']!=sha256(reference_path)
                    or record['metadata_sha256']!=sha256(metadata_path) or unit!=record['unit']
                    or float(values.reshape(-1)[0])!=record['value']
                    or record['new_priority']!=('High' if key in dynamic else 'Low')):
                raise ValueError('Dynamic target provenance mismatch: '+key)
        matches=[r for r in comparisons if r['key'] in dynamic]
        if len(matches)!=125:raise ValueError('Incomplete dynamic comparison')
        result['dynamic_state_count']=125
        result['exact_initial_dynamic_state_count']=sum(r['exact_initial'] for r in matches)
        result['initial_dynamic_state_preservation_pass']=all(r['initial']['pass_endpoint_match'] for r in matches)
        result['failed_one_step_dynamic_state_count']=sum(not r['one_step']['pass_endpoint_match'] for r in matches)
        result['dynamic_metadata_sha256']=sha256(metadata_path)
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--run-root',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite audit evidence')
    result=compute(args.repo,args.run_root)
    args.output.write_text(json.dumps(result,indent=2,ensure_ascii=False,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('comparisons','input_sha256')},indent=2))
    if not result['all_observations_roundtrip_pass']:
        raise SystemExit(1)


if __name__=='__main__':
    main()
