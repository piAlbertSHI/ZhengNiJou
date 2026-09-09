"""Audit the bounded Projection initial-point repair and preceding failures."""
import argparse
import csv
import json
import math
from pathlib import Path

from Audit_HeatDriveECC_ColdChamberRejection import read
from Audit_HeatDriveECC_ColdInitialTolerance import coordinates, BASE
from Audit_HeatDriveECC_ColdInitializationPhases import target_map, check_phases, RUNTIME_BASE
from Audit_HeatDriveECC_CompiledInventoryStates import CHAMBERS, BUFFERS, decode_tags, component_inventory_preserved
from Audit_HeatDriveECC_SegmentedEvidence import sha256

CASES = [
    ('implicit', 'specific_inventory_global_implicit_initial_20260909', '69f5bbee35059f7209d3a1aa865a21db6b41e777'),
    ('projection', 'specific_inventory_global_projection_initial_20260909', 'a7043046959e64535725aff65b154636ac5c8c97'),
    ('derivative', 'specific_inventory_projection_derivative_initial_20260909', '5dcb288b5fcf792017dc92d442ee9d1129e0805c'),
]
GLOBAL = dict(Solver='ode15s', SolverType='Variable-step', MaxStep='0.001', InitialStep='auto')
TOLERANCES = dict(RelTol='1e-2', AbsTol='1e-3')


def check_derivative(c):
    if (not c['initialization_only'] or c['allowed_stop_time_s'] != 0 or c['constant_interval_start_s'] != 0
            or c['first_derivative_MPa_per_s'] != 0 or c['filtering'] != 'provide'
            or c['provided_derivatives_before'] != '0' or c['provided_derivatives_after'] != '1'
            or c['production_recovery_allowed'] or c['full_cycle_derivative_verified']):
        raise ValueError('Derivative contract must be initial-point only and unfiltered')
    samples = c['command_samples']
    names = ['SMA_pressure_bias_command', 'SMA_pressure_feedback_enable_command', 'SMA_pressure_feedback_reset_command']
    if len(samples) != 3 or [s['variable'] for s in samples] != names:
        raise ValueError('Incomplete initial command evidence')
    for s, interpolation in zip(samples, ['on', 'off', 'off']):
        t, v = s['time_s'], s['values']
        if (len(t) != 2 or len(v) != 2 or not all(math.isfinite(x) for x in t+v)
                or t[0] != 0 or t[1] <= 0 or v[0] != v[1] or s['interpolate'] != interpolation):
            raise ValueError('Unverified constant initial command interval')
    if (samples[1]['values'] != [0, 0] or samples[2]['values'] != [1, 1]
            or c['constant_interval_end_exclusive_s'] != min(s['time_s'][1] for s in samples)):
        raise ValueError('Feedback is not disabled and reset held across the declared interval')


def check_runtime(r, targets, case):
    projection = case != 'implicit'
    settings = dict(BASE, UseLocalSolver='off')
    runtime = dict(RUNTIME_BASE, IndexReductionMethod='Projection') if projection else RUNTIME_BASE
    if (not r['global_implicit_requested'] or r.get('projection_requested', False) != projection
            or r.get('initial_pressure_derivative_requested', False) != (case == 'derivative')
            or r['global_solver_configuration'] != GLOBAL or r['global_tolerances_after'] != TOLERANCES
            or r['consistency_settings_before'] != BASE or r['consistency_settings_after'] != settings
            or r['runtime_solver_options_before'] != RUNTIME_BASE or r['runtime_solver_options_after'] != runtime
            or any(r[k] for k in ('half_step_requested', 'disable_regularization_requested', 'momentum_buffers_requested',
                                 'normal_mode_requested', 'buffer_nominal_scaling_requested', 'global_tolerance_override',
                                 'consistency_tolerance_override', 'residual_tolerance_override'))):
        raise ValueError('Global Projection experiment changed another factor')
    stages = ['InitFcn', 'StopFcn'] if case == 'projection' else ['InitFcn', 'StartFcn', 'StopFcn']
    if [c['stage'] for c in r['runtime_callbacks']] != stages:
        raise ValueError('Unexpected failure/success callback sequence')
    for c in r['runtime_callbacks']:
        if (c['solver_settings'] != settings or c['runtime_solver_options'] != runtime
                or c['global_solver_configuration'] != GLOBAL or {k: c[k] for k in TOLERANCES} != TOLERANCES
                or target_map(c['targets']) != target_map(targets) or c['has_private_data']
                or c['LoadInitialState'] != 'off' or c['SimscapeUseOperatingPoints'] != 'on'
                or c['mode'] != 'accelerator'
                or c['simulation_status'] != ('terminating' if c['stage'] == 'StopFcn' else 'initializing')):
            raise ValueError('Actual callback configuration or public targets changed')
        if case == 'derivative':
            p = c['pressure_converter']
            if (p['Unit'] != 'MPa' or p['FilteringAndDerivatives'] != 'provide' or p['UdotUserProvided'] != '1'
                    or p['StopTime'] != '0' or p['derivative_source'] != r['initial_pressure_derivative_contract']['derivative_source']):
                raise ValueError('Actual derivative interface differs')


def audit(repo):
    targets_path = repo/'outputs_storage_audit/conservative_buffer_coupled_cycle_20260909/conservative/public_inventory_targets.json'
    reference = read(targets_path); targets = reference['targets']
    native = targets_path.parent.parent/'native/observations.mat'
    if len(targets) != 204 or reference['has_private_data'] or reference['source_time_s'] != 0 or sha256(native) != reference['source_sha256']:
        raise ValueError('Native public cold reference changed')
    original = repo/'verification/simscape_inventory/+ecc_inventory/conservative_chamber.ssc'
    expected = original.read_text(encoding='utf-8').replace('stored_mass == volume * rho_I;', 'rho_I == stored_mass / volume;')
    expected = expected.replace('stored_energy == stored_mass * u_I;', 'u_I == stored_energy / stored_mass;')
    files = [targets_path, native, original]; results = []; rows = []
    for name, folder, commit in CASES:
        root = repo/'outputs_storage_audit'/folder; path = root/'compiled_states_inspection.json'; r = read(path)
        if (r['inspector_commit'] != commit or not r['initialization_only'] or r['source_time_s'] != 0
                or r['source_native_sha256'] != reference['source_sha256'] or not r['runtime_callback_capture_requested']
                or r['inventory_formulation'] != 'specific_inventory'
                or any(r[k] for k in ('c200_state_imported', 'failed_terminal_state_imported', 'checkpoint_saved',
                                     'production_recovery_allowed', 'component_inventory_priority_high', 'block_temperature_pressure_priority_low'))):
            raise ValueError('Wrong cold experiment identity')
        check_runtime(r, targets, name)
        library = root/'component_build/ecc_inventory_specific_lib.slx'
        component = root/'component_build/+ecc_inventory_specific/conservative_chamber.ssc'
        if (Path(r['loaded_chamber_library']).resolve() != library.resolve() or sha256(library) != r['loaded_library_sha256']
                or component.read_text(encoding='utf-8') != expected or r['chamber_source_file'] != 'ecc_inventory_specific.conservative_chamber'):
            raise ValueError('Compiled component source changed')
        result = dict(case=name, inspector_commit=commit, initial_matching_count=None, strict_initial_coordinate_match=False,
                      compiled_inventory_gate=None, actual_initial_coordinates_available=False)
        if name != 'derivative':
            if r['inspection_pass'] or r['stage'] != 'initialization_state_logging' or 'initial_coordinates' in r:
                raise ValueError('Failed solve must not supply accepted initial state')
            signatures = (['SMA_PumpInletConnectingPipeVolume.stored_mass', 'SMA_PumpOutletConnectingPipeVolume.stored_energy']
                          if name == 'implicit' else ['SMAPressurePI_SimulinkPS', '1', '0'])
            if not all(s in r['error_message'] for s in signatures) or (root/'compiled_initial_state_dataset.mat').exists():
                raise ValueError('Failure evidence differs')
            result['failure_class'] = 'initial_iteration_matrix_failure' if name == 'implicit' else 'missing_pressure_first_derivative'
        else:
            if (not r['inspection_pass'] or r['stage'] != 'complete' or r['error_message']
                    or not r['post_initialization_source_file_verified'] or r['cached_extraction_added_callbacks']):
                raise ValueError('Incomplete successful initial-point collection')
            check_derivative(r['initial_pressure_derivative_contract'])
            rows = coordinates(r['initial_coordinates'], targets)
            check_phases(r['cached_phase_targets'], targets, rows)
            tagged = [dict(block_name=t['block_name'], variable_name=t['variable_name'], **decode_tags(t)) for t in r['node_metadata']]
            result.update(initial_matching_count=sum(t['within_strict_comparison'] for t in rows),
                strict_initial_coordinate_match=all(t['within_strict_comparison'] for t in rows),
                compiled_inventory_gate=component_inventory_preserved(tagged, CHAMBERS | BUFFERS),
                actual_initial_coordinates_available=True,
                matching_by_priority={p:sum(t['within_strict_comparison'] for t in rows if t['priority']==p) for p in ('High','Low')},
                max_fraction_of_strict_limit=max(t['abs_error']/t['limit'] for t in rows),
                initial_derivative_contract=r['initial_pressure_derivative_contract'],
                dataset_elements=r['dataset_elements'], cached_phase_contract_pass=True)
            files.append(root/'compiled_initial_state_dataset.mat')
        results.append(result); files += [path, library, component, root/'matlab_diary.log']
    frozen_path = repo/'verification/c200_mainline_freeze_contract.json'; frozen = read(frozen_path); files.append(frozen_path)
    for key in ('result', 'checkpoint'):
        p = repo/frozen[key+'_relative_path']
        if sha256(p) != frozen[key+'_sha256']: raise ValueError('C200 changed')
        files.append(p)
    return dict(schema='heatdrive_ecc_cold_projection_initialization_v1', evidence_audit_pass=True, cases=results,
                initial_point_repair_verified=results[-1]['strict_initial_coordinate_match'] and results[-1]['compiled_inventory_gate'],
                production_recovery_allowed=False, full_cycle_derivative_verified=False, trajectory_conservation_verified=False,
                full_device_first_law_verified=False, table4_reproduction_claim=False, algebraic_independence_proven=False,
                input_sha256={str(p.relative_to(repo)):sha256(p) for p in files}), rows


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--output-root', type=Path, required=True)
    args = parser.parse_args()
    if args.output_root.exists(): raise FileExistsError('Never overwrite evidence')
    result, rows = audit(Path(__file__).resolve().parents[1]); args.output_root.mkdir(parents=True)
    (args.output_root/'projection_initialization_audit.json').write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    with (args.output_root/'initial_coordinates.csv').open('w', newline='', encoding='utf-8') as f:
        writer=csv.DictWriter(f, fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)
    print(json.dumps({k:v for k,v in result.items() if k!='input_sha256'}, indent=2))
    raise SystemExit(0 if result['initial_point_repair_verified'] else 1)
