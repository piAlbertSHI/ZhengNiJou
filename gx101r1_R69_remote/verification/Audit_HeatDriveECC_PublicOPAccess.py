"""Verify bounded read-only API evidence, not a state-migration qualification."""
import json
from pathlib import Path

from Audit_HeatDriveECC_OPAPIIsolation import require
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def main():
    repo=Path(__file__).resolve().parents[1]
    path=repo/'outputs_storage_audit/public_op_access_20260908_v2/public_op_access.json'
    require(sha256(path)=='4E5F91C70D9FFD42A6C5A2F8C7F1768F88247B0CDA09A8A2F60C5E84EC3219D0','Raw API evidence changed')
    data=json.loads(path.read_text(encoding='utf-8-sig'))
    require(data['schema']=='heatdrive_ecc_public_op_access_v1' and data['matlab_release']=='2025b'
            and data['execution_commit']=='6539cdbd66448ece42e61590619081dbb105bed7'
            and data['read_only'] is True and data['start_time_s']==0 and data['snapshot_time_s']==2000.001,
            'Wrong inspected source or time values')
    require(all(data[k] is False for k in ('model_simulation_executed','private_fields_read_or_written',
                'production_recovery_allowed','runtime_set_access_reflection_available')), 'Read-only scope changed')
    require(len(data['properties'])==3 and {r['name'] for r in data['properties']}=={'startTime','snapshotTime','loggedStates'}
            and all(r['publicly_enumerated'] is True for r in data['properties']), 'Property inventory changed')
    require(len(data['queries'])==1 and data['queries'][0]['block_path']=='heatdrive_ecc_coupled_se21/Solver Configuration'
            and data['queries'][0]['public_get_succeeded'] is False
            and data['queries'][0]['error_identifier']=='Simulink:SimState:CannotFindSimStateForBlock',
            'Named public query evidence changed')
    source=repo/'outputs_storage_audit/c200_source_compatibility_20260907/archived_source_probe_v4/DO_NOT_RESUME_FOR_PRODUCTION.mat'
    require(sha256(source)==data['source_sha256']=='8ACBED525F7F45170EF308B5F6BCB8E008AAEB87A4A90900982052786273E321',
            'Source OP changed')
    print(json.dumps(dict(read_only_evidence_pass=True,source_start_time_s=0,source_snapshot_time_s=2000.001,
        named_solver_get_accessible=False,time_property_write_test_executed=False,
        full_migration_verified=False,production_recovery_allowed=False),indent=2))


if __name__=='__main__':main()
