"""Compare full public snapshot controls against strict C200 continuation."""
import argparse
import json
from pathlib import Path

import numpy as np

from Audit_HeatDriveECC_C200RestoredSignals import compare
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_TargetInitialization import rows


LEGACY_METADATA_SHA256 = 'EF96B1A124EAEE0D999181223119C66B3C5717C5C6A2A3F0D6CB98C9E7B734BC'


def validate_source(meta, digest):
    if (not meta['strict_restore_pass'] or not meta['observation_complete'] or meta['error_message']
            or meta['source_operating_point_edited'] or meta['production_recovery_allowed']
            or meta['partial_restore_executed'] or meta['cold_start_executed']
            or not meta['physical_options_unchanged']
            or not all(v is True for v in meta['physical_options_unchanged'].values())):
        raise ValueError('Source is not a strict unchanged C200 continuation')
    # Only this already frozen v4 file predates the explicit command-scope fields.
    if digest == LEGACY_METADATA_SHA256:
        return
    if (meta['command_horizon_extended'] or meta['boundary_sample_hold_diagnostic']
            or meta['original_cycle_count'] != 200 or meta['target_cycle_count'] != 200):
        raise ValueError('Source command scope changed')


def compare_window(reference,actual,reference_times,actual_times,start_index):
    if set(reference)!=set(actual):raise ValueError('Incomplete observation coverage')
    comparisons=[]
    for key,(unit,t,y) in reference.items():
        other_unit,other_t,other_y=actual[key]
        if (unit!=other_unit or not np.array_equal(t,reference_times) or not np.array_equal(other_t,actual_times)
                or not np.array_equal(t[start_index:start_index+len(actual_times)],other_t)
                or y.shape[:-1]!=other_y.shape[:-1] or y.shape[-1]!=len(reference_times)
                or other_y.shape[-1]!=len(actual_times)):
            raise ValueError('Wrong observation identity, grid or shape: '+key)
        compared=[compare(y[...,start_index+i],other_y[...,i]) for i in range(len(actual_times))]
        exact=[bool(np.array_equal(y[...,start_index+i],other_y[...,i])) for i in range(len(actual_times))]
        comparisons.append(dict(key=key,comparisons=compared,exact=exact))
    return comparisons


def observed(root):
    result=rows(root/'restored_step_signals.mat');result.update(rows(root/'registered_states.mat',True));return result


def compute(repo):
    base=repo/'outputs_storage_audit';old_root=base/'c200_source_compatibility_20260907/archived_source_probe_v4'
    old=observed(old_root);strict_root=base/'c200_two_step_snapshot_20260908';reference=observed(strict_root)
    repeated_root=base/'c200_logged_simscape_op_20260908';repeated=observed(repeated_root)
    hashes={}
    for root in (old_root,strict_root,repeated_root):
        meta=json.loads((root/'source_restore_audit.json').read_text(encoding='utf-8-sig'))
        validate_source(meta,sha256(root/'source_restore_audit.json'))
        for name in ('source_restore_audit.json','restored_step_signals.mat','registered_states.mat'):
            hashes[str((root/name).relative_to(repo))]=sha256(root/name)
    prefix=compare_window(reference,old,[2000,2000.001,2000.002],[2000,2000.001],0)
    full=compare_window(reference,repeated,[2000,2000.001,2000.002],[2000,2000.001,2000.002],0)
    if len(prefix)!=1474 or not all(all(r['exact']) for r in prefix+full):
        raise ValueError('Strict reference prefix or repeat changed')
    snapshot_path=strict_root/'registered_op_snapshot.mat';snapshot=rows(snapshot_path,True)
    solver=[k for k in snapshot if '/Solver Configuration/' in k]
    if len(snapshot)!=73 or len(solver)!=1:raise ValueError('Unexpected public snapshot coverage')
    key=solver[0];unit,t,y=snapshot[key]
    if not np.array_equal(t,[2000.002]) or y.size!=995 or unit!=reference[key][0]:
        raise ValueError('Wrong public solver snapshot')
    previous_exact=bool(np.array_equal(y[...,0],reference[key][2][...,1]))
    same_exact=bool(np.array_equal(y[...,0],reference[key][2][...,2]))
    if not previous_exact or same_exact:raise ValueError('Observed solver snapshot phase relation changed')
    hashes[str(snapshot_path.relative_to(repo))]=sha256(snapshot_path)
    log_meta=json.loads((repeated_root/'source_restore_audit.json').read_text(encoding='utf-8-sig'))
    log_path=repeated_root/'LOG_OPERATING_POINT_DIAGNOSTIC_ONLY.mat'
    log_hash=sha256(log_path)
    if (log_hash!=log_meta['log_operating_point_sha256']
            or log_meta['log_operating_point_time_s']!=2000.001
            or log_meta['log_operating_point_target_count']!=2668
            or log_meta['log_operating_point_has_private_data'] is not True
            or log_meta['log_operating_point_restore_verified'] is not False):
        raise ValueError('Log-derived operating point provenance changed')
    hashes[str(log_path.relative_to(repo))]=log_hash
    source_op=old_root/'DO_NOT_RESUME_FOR_PRODUCTION.mat'
    source_op_hash=sha256(source_op)
    if source_op_hash!='8ACBED525F7F45170EF308B5F6BCB8E008AAEB87A4A90900982052786273E321':
        raise ValueError('Public source snapshot changed')
    hashes[str(source_op.relative_to(repo))]=source_op_hash
    cases=[];arrays=[]
    variants=[('public_snapshot_control_20260908_v2','nonnetwork_snapshot',72),
              ('public_snapshot_control_20260908_v2','whole_snapshot',73),
              ('logged_simscape_snapshot_control_20260908','nonnetwork_snapshot',72)]
    for folder,arm,count in variants:
        root=base/folder;meta_path=root/'public_snapshot_control.json'
        meta=json.loads(meta_path.read_text(encoding='utf-8-sig'))
        if (not meta['computation_complete'] or meta['error_message'] or not meta['seed_target_pass']
                or any(meta[k] for k in ('production_recovery_allowed','source_physical_model_changed',
                    'source_op_edited','final_checkpoint_saved','anonymous_indices_edited'))):
            raise ValueError('Wrong snapshot control scope')
        if (meta['source_snapshot_sha256']!=source_op_hash or meta['start_time_s']!=2000.001
                or meta['stop_time_s']!=2000.002 or len(meta['seed_matches'])!=196
                or not all(r['pass'] is True for r in meta['seed_matches'])):
            raise ValueError('Snapshot source, interval or seed preservation changed')
        if folder=='logged_simscape_snapshot_control_20260908':
            if (meta['seed_source']!='logged_simscape_point'
                    or meta['logged_simscape_point_unedited'] is not True
                    or meta['logged_simscape_point_sha256']!=log_hash):
                raise ValueError('Log-derived seed was changed or replaced')
        selected=[r for r in meta['cases'] if r['arm']==arm]
        path=root/(arm+'_observations.mat')
        if len(selected)!=1 or selected[0]['copied_public_groups']!=count or sha256(path)!=selected[0]['observation_sha256']:
            raise ValueError('Copied group count or observation hash changed')
        actual=rows(path);arrays.append(actual)
        comparison=compare_window(reference,actual,[2000,2000.001,2000.002],[2000.001,2000.002],1)
        cases.append(dict(folder=folder,arm=arm,copied_public_groups=count,
            failed_initial_groups=sum(not r['comparisons'][0]['pass_endpoint_match'] for r in comparison),
            failed_one_step_groups=sum(not r['comparisons'][1]['pass_endpoint_match'] for r in comparison),
            exact_initial_groups=sum(r['exact'][0] for r in comparison),
            exact_one_step_groups=sum(r['exact'][1] for r in comparison),
            full_observation_match=all(c['pass_endpoint_match'] for r in comparison for c in r['comparisons']),
            comparisons=comparison))
        hashes[str(meta_path.relative_to(repo))]=sha256(meta_path);hashes[str(path.relative_to(repo))]=sha256(path)
    identical=all(np.array_equal(arrays[0][k][2],arrays[1][k][2]) for k in arrays[0])
    return dict(schema='heatdrive_ecc_public_snapshot_evidence_v1',strict_reference_group_count=1474,
        strict_prefix_bitwise_match=True,strict_repeat_bitwise_match=True,
        solver_snapshot_channels=995,solver_snapshot_matches_previous_log=previous_exact,
        solver_snapshot_matches_same_time_log=same_exact,
        memory_only_and_whole_public_assignment_outputs_identical=identical,
        cases=cases,production_recovery_allowed=False,whole_model_migration_verified=False,
        full_device_first_law_verified=False,input_sha256=hashes,
        scope='Observed same-graph public-API controls; no individual packed indices interpreted or edited.')


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--repo',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True);args=p.parse_args()
    if args.output.exists():raise FileExistsError('Do not overwrite evidence')
    result=compute(args.repo)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('cases','input_sha256')},indent=2))
    print(json.dumps([{k:v for k,v in r.items() if k!='comparisons'} for r in result['cases']],indent=2))
    if not all(r['full_observation_match'] for r in result['cases']):raise SystemExit(1)


if __name__=='__main__':main()
