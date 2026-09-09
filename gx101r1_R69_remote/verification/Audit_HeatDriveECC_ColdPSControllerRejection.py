"""Audit failed cold PS integrations without promoting missing initial states."""
import argparse
import json
from pathlib import Path
from Audit_HeatDriveECC_ColdChamberRejection import read
from Audit_HeatDriveECC_ColdInitializationPhases import target_map, RUNTIME_BASE
from Audit_HeatDriveECC_ColdInitialTolerance import BASE
from Audit_HeatDriveECC_ColdProjectionInitialization import GLOBAL, TOLERANCES
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def reject_state_promotion(record):
    forbidden = ('initial_coordinates', 'ps_controller_initial', 'cached_phase_targets')
    if (record['inspection_pass'] or record['stage'] != 'initialization_state_logging'
            or record['states'] or any(key in record for key in forbidden)
            or any(record[key] for key in ('c200_state_imported', 'failed_terminal_state_imported',
                                          'checkpoint_saved', 'production_recovery_allowed'))):
        raise ValueError('Failed initialization cannot promote states')
    required = ['ColdSMAPSController.error_lag.Y', 'SMA_PumpInletConnectingPipeVolume.stored_mass',
                'SMA_PumpInletConnectingPipeVolume.stored_energy',
                'SMA_PumpOutletConnectingPipeVolume.stored_mass',
                'SMA_PumpOutletConnectingPipeVolume.stored_energy']
    if not all(s in record['error_message'] for s in required):
        raise ValueError('Failure signature changed')
    return required


def check_connections(contract):
    before, after = contract['physical_connections_before'], contract['physical_connections_after']
    keys = [(r['block'], r['port'], r['domain']) for r in before]
    if (len(before) != 1183 or len(set(keys)) != len(keys) or before != after
            or not contract['physical_connections_unchanged']):
        raise ValueError('Physical connection evidence is incomplete or changed')
    return len(before)


def audit(repo):
    root = repo / 'outputs_storage_audit'
    reference_path = root / 'sma_derivative_contract_20260909_v3/sma_derivative_contract.json'
    reference = read(reference_path)
    target_path = root / 'conservative_buffer_coupled_cycle_20260909/conservative/public_inventory_targets.json'
    target_record = read(target_path)
    targets = target_record['targets']
    if len(targets) != 204 or target_record['has_private_data'] or target_record['source_time_s'] != 0:
        raise ValueError('Original cold target coverage changed')
    native = target_path.parent.parent / 'native/observations.mat'
    if sha256(native) != target_record['source_sha256']:
        raise ValueError('Native cold source changed')
    cases = [('ps_closed_loop', 'specific_inventory_ps_controller_initial_20260909',
              'a93500ce7c2fd87ac8b347e7195dc246952bb2c4', False),
             ('initial_bias_only', 'specific_inventory_ps_bias_only_initial_20260909',
              '7227ad47911c50c7c4ced13147947a0ba11ef113', True)]
    files = [reference_path, target_path, native]
    results = []
    component = repo / 'verification/simscape_sma_controller/+ecc_sma_controller/pressure_controller.ssc'
    component_hash = sha256(component)
    if component_hash != 'EB6AC72398E21E9069674744E1F1ECE1D8133E4729D23E42FDE3AC5C332AEA71':
        raise ValueError('Qualified PS component changed')
    files.append(component)
    for label, folder, commit, bypass in cases:
        case_root = root / folder
        path = case_root / 'compiled_states_inspection.json'
        r = read(path)
        if (r['inspector_commit'] != commit or not r['initialization_only']
                or r['source_time_s'] != 0 or not r['ps_controller_requested']
                or r.get('initial_bias_only_requested', False) != bypass or r['diagnostic_stop_time_s'] != 0
                or r['source_native_sha256'] != target_record['source_sha256']
                or r['inventory_formulation'] != 'specific_inventory'):
            raise ValueError('Wrong diagnostic identity')
        signature = reject_state_promotion(r)
        for filename in ('observations.mat', 'compiled_initial_state_dataset.mat', 'final_operating_point.mat'):
            if (case_root / filename).exists():
                raise ValueError('Unexpected state artifact in rejected package')
        c = r['ps_controller_contract']
        count = check_connections(c)
        driver = 'ColdSMA_bias_PS' if bypass else 'ColdSMAPSController'
        if (c.get('initial_bias_only', False) != bypass or c.get('pressure_driver_path', c['candidate_path'])
                != 'heatdrive_ecc_coupled_se21/' + driver or c['commands'] != reference['commands']
                or c['component_sha256'] != component_hash or c['original_controller_sha256'] != sha256(reference_path)
                or c['production_recovery_allowed'] or c['c200_state_imported']):
            raise ValueError('Controller wiring/command contract changed')
        library = Path(c['library_path'])
        if sha256(library) != c['library_sha256']:
            raise ValueError('PS library changed')
        settings, runtime = dict(BASE, UseLocalSolver='off'), dict(RUNTIME_BASE, IndexReductionMethod='Projection')
        if (r['global_solver_configuration'] != GLOBAL or r['global_tolerances_after'] != TOLERANCES
                or r['consistency_settings_after'] != settings or r['runtime_solver_options_after'] != runtime):
            raise ValueError('Numerical configuration differs')
        if [x['stage'] for x in r['runtime_callbacks']] != ['InitFcn', 'StartFcn', 'StopFcn']:
            raise ValueError('Missing runtime callback evidence')
        for callback in r['runtime_callbacks']:
            if (target_map(callback['targets']) != target_map(targets) or callback['has_private_data']
                    or callback['solver_settings'] != settings or callback['runtime_solver_options'] != runtime
                    or callback['global_solver_configuration'] != GLOBAL
                    or {k: callback[k] for k in TOLERANCES} != TOLERANCES
                    or callback['LoadInitialState'] != 'off' or callback['mode'] != 'accelerator'
                    or callback['pressure_converter']['source_file'] != 'ecc_sma_controller.pressure_controller'):
                raise ValueError('Actual runtime contract changed')
        canonical = Path(r['runtime_callbacks'][0]['model_file'])
        if sha256(canonical) != reference['canonical_sha256']:
            raise ValueError('Canonical model changed')
        results.append(dict(case=label, inspector_commit=r['inspector_commit'],
                            failure_class='initial_iteration_matrix_failure', failed_derivative_signatures=signature,
                            initial_bias_only=bypass, unchanged_physical_port_records=count,
                            preserved_public_target_count=204, actual_initial_coordinates_available=False,
                            strict_initial_coordinate_match=None, accepted_as_recovery=False))
        files += [path, case_root / 'matlab_diary.log', library, canonical]
    freeze_path = repo / 'verification/c200_mainline_freeze_contract.json'
    freeze = read(freeze_path)
    files.append(freeze_path)
    for key in ('result', 'checkpoint'):
        path = repo / freeze[key + '_relative_path']
        if sha256(path) != freeze[key + '_sha256']:
            raise ValueError('Frozen benchmark changed')
        files.append(path)
    return dict(schema='heatdrive_ecc_cold_ps_rejection_audit_v1', rejection_evidence_audit_pass=True,
                cases=results, pressure_expression_bypass_sufficient=False,
                coupled_controller_initialization_pass=False, initial_coordinate_gate=None,
                trajectory_conservation_verified=False, production_recovery_allowed=False,
                full_device_first_law_verified=False, table4_reproduction_claim=False,
                c200_restore_allowed_current_model=freeze['resume_policy']['state_recovery_allowed_current_model'],
                input_sha256={str(p.relative_to(repo)): sha256(p) for p in files})


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-root', type=Path, required=True)
    args = parser.parse_args()
    if args.output_root.exists():
        raise FileExistsError('Never overwrite evidence')
    result = audit(Path(__file__).resolve().parents[1])
    args.output_root.mkdir(parents=True)
    (args.output_root / 'cold_ps_rejection_audit.json').write_text(
        json.dumps(result, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in result.items() if k != 'input_sha256'}, indent=2))
