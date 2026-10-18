"""Independent implementation identity checks, not relaxed physical acceptance."""
import json
from pathlib import Path

from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def admission(path):
    path = Path(path)
    r = read(path)
    if (r['schema'] != 'heatdrive_ecc_kernel_independent_cold_admission_v1'
            or r['independent_cold_20cycle_admitted'] is not True
            or r['old_backend_OP_import_allowed'] is not False
            or r['strict_vendor_restore_required'] is not True
            or r['same_case_split_test_required_before_long_continuation'] is not True
            or r['production_recovery_allowed'] is not False or r['outer_solve_allowed'] is not False
            or r['table4_reproduction_claim'] is not False):
        raise ValueError('Wrong independent cold implementation scope')
    source = Path(__file__).parent
    if (r['wrapper_name'] != 'HeatDriveECC_ConstitutiveStateVectorStep21_KernelCandidate'
            or r['kernel_name'] != 'HeatDriveECC_StableKernelCandidate'
            or sha256(source/(r['wrapper_name']+'.m')) != r['wrapper_sha256']
            or sha256(source/(r['kernel_name']+'.m')) != r['kernel_sha256']):
        raise ValueError('Candidate implementation changed after its comparisons')
    repo = path.parent.parent
    for name in ('offline', 'coupled'):
        p = (repo/r[name+'_relative']).resolve()
        if not p.is_relative_to(repo.resolve()) or sha256(p) != r[name+'_sha256']:
            raise ValueError('Changed or escaped implementation evidence')
    a = read(repo/r['offline_relative'])
    b = read(repo/r['coupled_relative'])
    if (not a['all_captured_samples_bitwise_equal'] or not a['all_original_L8_option_cases_bitwise_equal']
            or a['captured_samples'] != 200 or a['edge_samples'] != 180 or a['invalid_contracts_rejected'] != 8
            or a['candidate_source_sha256'] != r['kernel_sha256'] or a['error_message']
            or not b['coupled_cold_trajectory_equivalence_verified'] or b['replay_physical_cycles'] != 4
            or sorted(row['case_index'] for row in b['records']) != [0, 1]
            or not all(row['pass_all_original_gates'] and row['all_actual_arrays_bitwise_equal'] for row in b['records'])
            or b['offline_sha256'] != r['offline_sha256'] or b['production_recovery_allowed']):
        raise ValueError('Incomplete actual implementation comparisons')
    return r


def audit_execution(packet, case, configuration):
    if 'execution_backend' not in case:
        return None
    bound = case['execution_backend']
    path = Path(bound['admission_path'])
    if bound['old_backend_OP_imported'] is not False or sha256(path) != bound['admission_sha256']:
        raise ValueError('Changed or cross-backend complete-state declaration')
    r = admission(path)
    if (bound['function'] != r['wrapper_name'] or bound['kernel_sha256'] != r['kernel_sha256']
            or bound['wrapper_sha256'] != r['wrapper_sha256']
            or text_field(configuration['options/constitutive/diagnostic_step_function']) != r['wrapper_name']):
        raise ValueError('Stored constructor has the wrong implementation')
    record = read(Path(packet)/'execution_backend.json')
    for when in ('before', 'after'):
        row = record[when]
        if (row['actual_function'] != r['wrapper_name'] or row['requested_function'] != r['wrapper_name']
                or row['actual_source_sha256'] != r['wrapper_sha256']
                or row['function_matches_request'] is not True or row['base_kernel_parameters_match'] is not True
                or row['node_count'] != 21 or row['sample_time_s'] != .001 or row['substeps'] != 32
                or row['simulation_settings_changed'] or row['source_state_edited']):
            raise ValueError('Actual interpreted backend differs from the case contract')
    return dict(function=r['wrapper_name'],admission_sha256=bound['admission_sha256'],
                actual_before_and_after_binding_verified=True,old_backend_OP_imported=False,
                full_state_restore_equivalence_claim=False)
