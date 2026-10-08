"""Keep a state-qualified diagnostic segment distinct from cold and production runs."""
import json
from pathlib import Path

from Audit_HeatDriveECC_SegmentedEvidence import sha256


def diagnostic_arms(root, execution):
    mode=execution.get('diagnostic_state_options', {}).get('mode', 'off')
    if mode == 'restore_preflight' and execution.get('requested_arms') == ['native']:
        if (execution.get('requested_arm_collection_pass') is not True
                or execution.get('collection_pass') is not False
                or execution.get('state_restore_preflight_pass') is not True
                or execution.get('start_time_s') != 0 or execution.get('stop_time_s') != 20
                or execution.get('cycle_count') != 2 or execution.get('checkpoint_saved') is not True
                or execution.get('c200_state_imported') is not False
                or execution.get('production_recovery_allowed') is not False
                or execution.get('error_message') != ''):
            raise ValueError('Incomplete independent cold qualification scope')
        folder = root / 'native'
        read = lambda name: json.loads((folder / name).read_text(encoding='utf-8-sig'))
        mechanism = read('cold_mechanism_audit.json')
        persistence = read('native_ledger_persistence.json')
        preflight = read('state_restore_preflight.json')
        capture = read('diagnostic_state_capture.json')
        completion = read('arm_completion.json')
        if (mechanism.get('execution_commit') != execution['execution_commit']
                or mechanism.get('mechanism_pass') is not True
                or len(mechanism.get('checks', {})) != 73
                or not all(value is True for value in mechanism['checks'].values())
                or mechanism['directional_pressure_observation'].get('pass') is not True
                or persistence.get('all_trace_values_clock_units_metadata_exact') is not True
                or persistence.get('native_trace_count') != 1262
                or preflight.get('same_model_restore_preflight_pass') is not True
                or preflight.get('source_operating_point_sha256') != capture['operating_point_sha256']
                or completion.get('execution_commit') != execution['execution_commit']
                or completion.get('observation_sha256') != sha256(folder / 'observations.mat')
                or mechanism['observation_sha256'] != sha256(folder / 'cold_mechanism_observation.mat')
                or any((root / name).exists() for name in ('REJECTED_DO_NOT_RESUME.json',
                                                          'INCOMPLETE_DO_NOT_RESUME.json'))):
            raise ValueError('Independent cold observation is not a complete hash-bound candidate')
        return ('native',)
    if mode != 'diagnostic_resume':
        return ('native', 'conservative')
    contract=execution.get('diagnostic_resume_contract', {})
    if (execution.get('requested_arm_collection_pass') is not True
            or execution.get('collection_pass') is not False
            or execution.get('requested_arms') != ['native']
            or execution.get('start_time_s') != 20 or execution.get('stop_time_s') != 220
            or execution.get('segment_cycle_count') != 20 or execution.get('cycle_count') != 22
            or execution.get('checkpoint_saved') is not True or execution.get('c200_state_imported') is not False
            or execution.get('production_recovery_allowed') is not False
            or execution.get('error_message') != ''
            or contract.get('schema') != 'heatdrive_ecc_state_qualified_diagnostic_resume_v1'
            or contract.get('full_cycle_state_restore_verified') is not True
            or contract.get('diagnostic_trial_only') is not True
            or contract.get('snapshot_time_s') != 20
            or any(contract.get(key) is not False for key in (
                'failed_state_propagated','source_state_edited','partial_state_restore_used','production_recovery_allowed'))):
        raise ValueError('Invalid diagnostic continuation scope')
    source=Path(contract['source_root'])/'native'
    verified=Path(contract['verification_root'])/'native'
    paths={source/'diagnostic_complete_operating_point.mat': 'operating_point_sha256',
           source/'diagnostic_state_observation.mat': 'history_sha256',
           verified/'rebuilt_cycle_restore.json': 'restore_receipt_sha256',
           verified/'rebuilt_cycle_comparison.mat': 'comparison_sha256'}
    for path,key in paths.items():
        if sha256(path)!=contract[key]:
            raise ValueError('Changed diagnostic continuation source: '+str(path))
    proof=json.loads((verified/'rebuilt_cycle_restore.json').read_text(encoding='utf-8-sig'))
    if (proof.get('rebuilt_complete_cycle_pass') is not True
            or proof.get('source_operating_point_sha256') != contract['operating_point_sha256']
            or proof.get('source_history_sha256') != contract['history_sha256']
            or proof.get('production_recovery_allowed') is not False):
        raise ValueError('Diagnostic restore proof does not bind the input state')
    return ('native',)
