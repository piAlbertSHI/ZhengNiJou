"""Qualify a completed mechanism-passing endpoint for warmup, never steady studies."""
import argparse
import json
import re
from pathlib import Path

from Audit_HeatDriveECC_SegmentedEvidence import sha256


SCHEMA = 'heatdrive_ecc_latest_diagnostic_endpoint_qualification_v1'
LOCAL_FILES = {
    'execution': 'cold_chamber_execution.json',
    'capture': 'native/diagnostic_state_capture.json',
    'operating_point': 'native/diagnostic_complete_operating_point.mat',
    'history': 'native/diagnostic_state_observation.mat',
    'observation': 'native/observations.mat',
    'configuration': 'native/configuration.mat',
}
AUDIT_ROLES = {'physics_audit', 'mechanism_audit', 'state_audit', 'steadiness_audit'}


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def validate_qualification(receipt, root):
    root = Path(root).resolve()
    stop = receipt.get('snapshot_time_s')
    cycles = receipt.get('total_cycles')
    if (receipt.get('schema') != SCHEMA or Path(receipt['source_root']).resolve() != root
            or not isinstance(cycles, int) or cycles < 22 or cycles > 200
            or stop != cycles * 10 or receipt.get('command_horizon_cycles') != 200
            or receipt.get('qualification_pass') is not True
            or receipt.get('warmup_continuation_allowed') is not True
            or receipt.get('full_mechanism_count') != 73
            or receipt.get('local_inventory_pass') is not True
            or receipt.get('ancestor_complete_cycle_restore_verified') is not True
            or receipt.get('complete_logged_state_coverage') is not True
            or any(receipt.get(key) is not False for key in (
                'production_recovery_allowed', 'steady_outer_solve_allowed',
                'table4_reproduction_claim', 'source_state_edited', 'partial_state_restore_used',
                'latest_endpoint_complete_cycle_reference_compared'))):
        raise ValueError('Invalid latest-endpoint warmup authority')
    rows = receipt.get('files', [])
    roles = [row.get('role') for row in rows]
    if len(roles) != 10 or set(roles) != set(LOCAL_FILES) | AUDIT_ROLES:
        raise ValueError('Missing or duplicated endpoint evidence role')
    for row in rows:
        path = Path(row['path']).resolve()
        if (row['role'] in LOCAL_FILES and path != (root / LOCAL_FILES[row['role']]).resolve()
                or not re.fullmatch('[0-9A-F]{64}', row.get('sha256', ''))
                or sha256(path) != row['sha256']):
            raise ValueError('Changed or substituted endpoint evidence: ' + row['role'])
    if any((root / marker).exists() for marker in (
            'INCOMPLETE_DO_NOT_RESUME.json', 'REJECTED_DO_NOT_RESUME.json',
            'REJECTED_DO_NOT_RESUME.txt')):
        raise ValueError('Rejected or incomplete endpoint cannot propagate')
    return {row['role']: row for row in rows}


def qualify(root, physics_path, mechanism_path, state_path, steadiness_path):
    from Analyze_HeatDriveECC_DiagnosticSteadiness import completed_mechanism
    from HeatDriveECC_DiagnosticAnalysisScope import diagnostic_arms

    root = Path(root).resolve()
    execution = read(root / LOCAL_FILES['execution'])
    if (execution.get('diagnostic_state_options', {}).get('mode') != 'diagnostic_resume'
            or diagnostic_arms(root, execution) != ('native',)
            or execution['diagnostic_state_options'].get('command_horizon_cycles') != 200):
        raise ValueError('Require a complete fixed-horizon diagnostic segment')
    paths = {role: root / file for role, file in LOCAL_FILES.items()}
    paths.update(physics_audit=physics_path, mechanism_audit=mechanism_path,
                 state_audit=state_path, steadiness_audit=steadiness_path)
    files = [dict(role=role, path=str(Path(path).resolve()), sha256=sha256(path))
             for role, path in paths.items()]
    hashes = {row['role']: row['sha256'] for row in files}
    physics, mechanism, states, steady = map(read, (
        physics_path, mechanism_path, state_path, steadiness_path))
    capture = read(paths['capture'])
    normalized = {key.replace('\\', '/'): value for key, value in physics['input_sha256'].items()}
    if (physics.get('analysis_scope') != 'state_qualified_diagnostic_segment'
            or physics.get('producer') != execution['execution_commit']
            or physics.get('cycles_run') != execution['cycle_count']
            or physics.get('mechanism_subset_pass') is not True or len(physics['arms']) != 1
            or physics['arms'][0]['mechanism_subset_gates'].get('local_inventory') is not True
            or any(value is not True for value in physics['arms'][0]['mechanism_subset_gates'].values())):
        raise ValueError('Completed local physical gates failed or belong to another segment')
    for role, relative in LOCAL_FILES.items():
        if normalized.get(relative) != hashes[role]:
            raise ValueError('Physics audit does not bind endpoint ' + role)
    for relative, expected in normalized.items():
        path = (root / relative).resolve()
        if not path.is_relative_to(root) or sha256(path) != expected:
            raise ValueError('Changed or escaped local-ledger audit input: ' + relative)
    full = completed_mechanism(root, physics, execution, mechanism)
    if not full['pass_gate']:
        raise ValueError('A mechanism-failed endpoint cannot propagate')
    if (capture.get('schema') != 'heatdrive_ecc_diagnostic_state_capture_v1'
            or capture.get('snapshot_time_s') != execution['stop_time_s']
            or capture.get('complete_op_class') not in (
                'Simulink.op.ModelOperatingPoint', 'Simulink.SimulationOperatingPoint')
            or capture.get('operating_point_sha256') != hashes['operating_point']
            or capture.get('history_sha256') != hashes['history']
            or any(capture.get(key) is not False for key in (
                'production_recovery_allowed', 'source_op_edited', 'state_reconstruction_used'))
            or capture['settings'].get('complete_operating_point_requested') is not True
            or capture['settings'].get('hidden_state_reconstruction_used') is not False
            or states.get('observation_sha256') != hashes['history']
            or states.get('logged_group_count') != 74 or states.get('logged_coordinate_count') != 1414
            or states.get('all_logged_groups_have_ten_cycle_comparisons') is not True
            or states.get('all_three_PI_memories_observed') is not True):
        raise ValueError('Complete intact endpoint or logged state coverage missing')
    for role in ('physics_audit', 'state_audit', 'mechanism_audit'):
        key = {'physics_audit': 'physics_audit', 'state_audit': 'state_audit',
               'mechanism_audit': 'full_mechanism_audit'}[role]
        if steady['input_sha256'].get(key) != hashes[role]:
            raise ValueError('Steadiness receipt does not bind the same evidence')
    if (steady.get('producer') != execution['execution_commit']
            or steady.get('total_cycles') != execution['cycle_count']
            or steady.get('all_mechanism_gates_evaluated') is not True
            or steady.get('full_mechanism', {}).get('pass_gate') is not True
            or steady.get('physical_tolerances_changed') is not False
            or steady.get('production_recovery_allowed') is not False):
        raise ValueError('Incomplete or promoted steadiness receipt')
    parent = execution['diagnostic_resume_contract']
    ancestor = (dict(source_root=parent['source_root'], verification_root=parent['verification_root'],
                     restore_receipt_sha256=parent['restore_receipt_sha256'],
                     comparison_sha256=parent['comparison_sha256'])
                if parent['schema'] == 'heatdrive_ecc_state_qualified_diagnostic_resume_v1'
                else parent['ancestor_complete_cycle_proof'])
    receipt = dict(schema=SCHEMA, source_root=str(root), producer=execution['execution_commit'],
        snapshot_time_s=execution['stop_time_s'], total_cycles=execution['cycle_count'],
        command_horizon_cycles=200, qualification_pass=True, warmup_continuation_allowed=True,
        full_mechanism_count=73, local_inventory_pass=True, complete_logged_state_coverage=True,
        ancestor_complete_cycle_restore_verified=True, ancestor_complete_cycle_proof=ancestor,
        latest_endpoint_complete_cycle_reference_compared=False,
        production_recovery_allowed=False, steady_outer_solve_allowed=False,
        table4_reproduction_claim=False, source_state_edited=False, partial_state_restore_used=False,
        core_periodic_last_pair=steady['core_periodic_last_pair'], files=files,
        interpretation='Mechanism-passing transient endpoint may continue warmup under strict vendor '
                       'checksum policy. Nonsteady drift blocks steady studies, not further warmup. '
                       'Independent complete-cycle reference proof belongs to the C2 ancestor only.')
    validate_qualification(receipt, root)
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--experiment-root', type=Path, required=True)
    for role in ('physics', 'mechanism', 'state', 'steadiness'):
        parser.add_argument('--' + role + '-audit', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Never overwrite an endpoint decision')
    result = qualify(args.experiment_root, args.physics_audit, args.mechanism_audit,
                     args.state_audit, args.steadiness_audit)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    print(json.dumps({key: result[key] for key in (
        'snapshot_time_s', 'total_cycles', 'qualification_pass', 'warmup_continuation_allowed',
        'production_recovery_allowed', 'steady_outer_solve_allowed')}, indent=2))
