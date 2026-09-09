"""Compare shared and separated passive PS networks at the initial point."""
import argparse
import csv
import json
import math
from pathlib import Path
from Audit_HeatDriveECC_ColdChamberRejection import read
from Audit_HeatDriveECC_ColdInitialTolerance import coordinates
from Audit_HeatDriveECC_ColdInitializationPhases import check_phases
from Audit_HeatDriveECC_ColdProjectionInitialization import check_runtime, check_derivative
from Audit_HeatDriveECC_ColdPressureValuePath import check_value_edge, check_inactive_removal
from Audit_HeatDriveECC_CompiledInventoryStates import CHAMBERS, BUFFERS, decode_tags, component_inventory_preserved
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def check_topology(c, separate):
    prefix = 'heatdrive_ecc_coupled_se21/'
    observer = prefix+'ColdSMAPassiveObserver'; converter = prefix+'SMAPressurePI_SimulinkPS'
    before = [prefix+'SMA Pressure Source (TL)']; after = before if separate else before+[observer]
    if (c['observer_path'] != observer or c['pressure_converter'] != converter
            or c['pressure_value_source'] != prefix+'SMAPressureBiasFromWorkspace'
            or c['pressure_derivative_source'] != prefix+'ColdInitialPressureDerivativeOnly'
            or c['pressure_destinations_before'] != before or sorted(c['pressure_destinations_after']) != sorted(after)
            or c['observer_drives_pump'] or c['separate_solver_added'] != separate
            or c['allowed_stop_time_s'] != 0 or c['production_recovery_allowed'] or c['c200_state_imported']):
        raise ValueError('Observer is not a passive bounded topology')
    if separate:
        solver = c['observer_solver_contract']
        if (c['observer_bias_driver'] != prefix+'ColdObserver_bias_PS' or not solver['copied_settings_identical']
                or solver['observer_path'] != prefix+'ColdObserver_Solver'
                or solver['settings']['UseLocalSolver'] != 'off' or solver['settings']['IndexReductionMethod'] != 'Projection'):
            raise ValueError('Separated observer solver differs')
    return True


def check_live_input(c, callback):
    prefix = 'heatdrive_ecc_coupled_se21/'
    expected = dict(path=prefix+'ColdObserver_mdot_PS', Unit='kg/s', FilteringAndDerivatives='provide',
                    UdotUserProvided='0', input_count=1, value_source=prefix+'FlowSensor_SMA_stage13_loop_PS')
    if (c['flow_input_mode'] != 'live_simulink_bridge' or c['provided_flow_derivatives'] != '0'
            or c['flow_value_source'] != expected['value_source'] or callback != expected):
        raise ValueError('Live flow must use the unfiltered value-only signal bridge')
    return True


def check_initial(rows, c, measured_mdot=None):
    commands = c['commands']
    mdot = c['frozen_mdot_kg_s'] if measured_mdot is None else measured_mdot
    if not math.isfinite(mdot):
        raise ValueError('Nonfinite measured flow')
    expected = dict(mdot=(mdot, 'kg/s'), target=(commands[1]['values'][0], 'kg/s'),
                    bias=(commands[0]['values'][0], 'MPa'), enable=(0., '1'), reset=(1., '1'),
                    pressure=(commands[0]['values'][0], 'MPa'), lag=(0., '1'), integral=(0., 'MPa'))
    if len(rows) != 8 or set(x['name'] for x in rows) != set(expected):
        raise ValueError('Incomplete actual observer state and input coverage')
    for row in rows:
        value, unit = expected[row['name']]
        if (row['unit'] != unit or row['source_time_s'] != 0 or not math.isfinite(row['actual'])
                or not math.isclose(row['actual'], value, rel_tol=0., abs_tol=1e-12)):
            raise ValueError('Observer initial state or command differs')
    return True


def check_actuation(a, c):
    prefix = 'heatdrive_ecc_coupled_se21/'; driver = prefix+'ColdObserver_pressure_Output'
    expected = [dict(destination=x, input=1, before=c['pressure_value_source'], after=driver)
                for x in (c['pressure_converter'], prefix+'SMAPressurePI_Saturation')]
    if (a['changed_inputs'] != expected or a['pressure_driver'] != driver or a['pressure_converter'] != c['pressure_converter']
            or a['pressure_derivative_source'] != c['pressure_derivative_source'] or not a['observer_drives_pump']
            or a['initial_feedback_enable'] != 0 or a['initial_reset'] != 1 or a['first_derivative_MPa_s'] != 0
            or a['allowed_stop_time_s'] != 0 or a['full_cycle_derivative_verified']
            or a['c200_state_imported'] or a['production_recovery_allowed']):
        raise ValueError('Actuation must preserve the bounded initial derivative and logging path')
    return True


def summarize_coordinates(rows):
    rejected = [x for x in rows if not x['within_strict_comparison']]
    return dict(strict_initial_coordinate_gate=not rejected, matching_initial_coordinates=len(rows)-len(rejected),
                failed_initial_coordinates=len(rejected), failed_high_priority=sum(x['priority'] == 'High' for x in rejected),
                max_fraction_of_strict_limit=max(x['abs_error']/x['limit'] for x in rows), failed_coordinate_rows=rejected)


def audit(repo):
    root = repo/'outputs_storage_audit'; reference_path = root/'conservative_buffer_coupled_cycle_20260909/conservative/public_inventory_targets.json'
    reference = read(reference_path); targets = reference['targets']; native = reference_path.parent.parent/'native/observations.mat'
    if len(targets) != 204 or reference['has_private_data'] or sha256(native) != reference['source_sha256']:
        raise ValueError('Original public cold reference changed')
    command_path = root/'sma_derivative_contract_20260909_v3/sma_derivative_contract.json'; command = read(command_path)
    qualified_path = root/'ps_controller_pair_audit_20260909/controller_pair_audit.json'
    flow_path = root/'initial_flux_pressure_audit_20260909_v2/initial_flux_pressure_audit.json'; flow = read(flow_path)
    if sha256(flow_path) != '25BD6933EF469E29F77474659B0D8F74027B890D8E3B80910660559E9CA50B4D':
        raise ValueError('Frozen input qualification changed')
    cases = [('shared', 'specific_inventory_passive_ps_original_converter_initial_20260909',
              '6dfcb4b7792bfba183da39f53390b77033c8432f', False, False, False, False),
             ('separate', 'specific_inventory_passive_ps_separate_network_initial_20260909',
              'd9a6a4a011989bb4ef1a1c02b595a286715278b9', True, False, False, False),
             ('live_flow', 'specific_inventory_passive_ps_live_flow_initial_20260909',
              '1d0c35c7018e3f784aa2385d7d3e61da43c72c32', True, True, False, False),
             ('initial_actuation', 'specific_inventory_separate_ps_actuation_initial_20260909',
              '1b09b41bab2413ede514e95e9a4175bab709b026', True, True, True, False),
             ('tight_initial_actuation', 'specific_inventory_separate_ps_actuation_tight_initial_20260909',
              '363909a37ad1ecd9c31f41e0c536b964d0d9490c', True, True, True, True)]
    files = [reference_path, native, command_path, qualified_path, flow_path]; results = []; rows = []
    base_actuation = None; tight_comparison = None
    for label, folder, producer, separate, live, actuate, tight in cases:
        case_root = root/folder; path = case_root/'compiled_states_inspection.json'; r = read(path)
        if (r['inspector_commit'] != producer or not r['passive_ps_observer_requested']
                or r.get('separate_observer_network_requested', False) != separate
                or r.get('live_observer_flow_requested', False) != live
                or r.get('actuate_ps_output_requested', False) != actuate
                or r.get('tight_actuation_tolerance_trial', False) != tight
                or not r['remove_inactive_controller_requested'] or not r['bias_value_path_requested']
                or not r['initialization_only'] or r['diagnostic_stop_time_s'] != 0 or r['inventory_formulation'] != 'specific_inventory'
                or any(r[k] for k in ('ps_controller_requested', 'analytic_pressure_derivative_requested',
                    'c200_state_imported', 'failed_terminal_state_imported', 'checkpoint_saved', 'production_recovery_allowed'))):
            raise ValueError('Wrong passive observer experiment')
        check_runtime(r, targets, 'tight_actuation' if tight else 'derivative'); check_derivative(r['initial_pressure_derivative_contract'])
        if tight:
            if any(x['algebraic_loop_options'] != dict(solver='Auto', diagnostic='warning') for x in r['runtime_callbacks']):
                raise ValueError('Unexpected algebraic-loop configuration')
            if base_actuation is None:
                raise ValueError('Missing baseline numerical comparison')
            current = {x['path']: x['actual'] for x in r['initial_coordinates']}
            previous = {x['path']: x['actual'] for x in base_actuation['initial_coordinates']}
            tight_comparison = dict(initial_coordinate_keys_identical=set(current) == set(previous),
                initial_coordinate_values_identical=current == previous,
                actual_sensor_flow_identical=r['actual_initial_sensor_mdot_kg_s'] == base_actuation['actual_initial_sensor_mdot_kg_s'],
                observer_initial_values_identical=r['ps_controller_initial'] == base_actuation['ps_controller_initial'],
                baseline_tolerances=base_actuation['global_tolerances_after'], tightened_tolerances=r['global_tolerances_after'])
        elif actuate:
            base_actuation = r
        check_value_edge(r['pressure_value_path_contract'])
        check_inactive_removal(r['inactive_controller_removal_contract'], r['pressure_value_path_contract'])
        c = r['passive_ps_observer_contract']; check_topology(c, separate)
        runtime_driver = c['pressure_value_source']
        if actuate:
            a = r['ps_initial_actuation_contract']; check_actuation(a, c); runtime_driver = a['pressure_driver']
            qualification = Path(a['qualification_path'])
            if sha256(qualification) != a['qualification_sha256'] or a['qualification_sha256'] != '3C47AB592F9CC5BBAC3C4005BEA53B9EE58CE36D0F0FA36B42A62B0FE8598330':
                raise ValueError('Live-flow prerequisite changed')
            files.append(qualification)
        if (c['commands'] != command['commands'] or c['reference_sha256'] != sha256(command_path)
                or c['qualification_sha256'] != sha256(qualified_path)
                or c['flow_audit_sha256'] != sha256(flow_path) or c['frozen_mdot_kg_s'] != flow['measured_flow_signal_initial_kg_s']
                or c['component_sha256'] != 'EB6AC72398E21E9069674744E1F1ECE1D8133E4729D23E42FDE3AC5C332AEA71'):
            raise ValueError('Observer source, commands or fixed flow changed')
        raw = Path(c['flow_observations_path']); library = Path(c['library_path'])
        if sha256(raw) != c['flow_observations_sha256'] or sha256(library) != c['library_sha256']:
            raise ValueError('Qualified observer artifact changed')
        for callback in r['runtime_callbacks']:
            if live:
                check_live_input(c, callback['passive_observer_flow_input'])
            if (callback['pressure_converter']['value_source'] != runtime_driver
                    or callback['original_control_state_blocks_present'] != dict(lag=False, integral=False)):
                raise ValueError('Runtime pressure path changed')
            if separate:
                solver = callback['passive_observer_solver']
                if (solver['settings'] != c['observer_solver_contract']['settings'] or not solver['copied_settings_identical']
                        or solver['path'] != c['observer_solver_contract']['observer_path']):
                    raise ValueError('Actual observer solver was not the declared copy')
        coordinate_summary = None
        if separate:
            if not r['inspection_pass'] or r['stage'] != 'complete' or r['error_message']:
                raise ValueError('Separated observer did not initialize')
            rows = coordinates(r['initial_coordinates'], targets); check_phases(r['cached_phase_targets'], targets, rows)
            tagged = [dict(block_name=x['block_name'], variable_name=x['variable_name'], **decode_tags(x)) for x in r['node_metadata']]
            coordinate_summary = summarize_coordinates(rows)
            if not component_inventory_preserved(tagged, CHAMBERS | BUFFERS):
                raise ValueError('Physical inventory differential-state structure was lost')
            if not actuate and not coordinate_summary['strict_initial_coordinate_gate']:
                raise ValueError('Previously qualified passive initial coordinates changed')
            check_initial(r['ps_controller_initial'], c, r['actual_initial_sensor_mdot_kg_s'] if live else None)
            if live:
                mdot = next(x['actual'] for x in r['ps_controller_initial'] if x['name'] == 'mdot')
                if abs(mdot-r['actual_initial_sensor_mdot_kg_s']) > 1e-15:
                    raise ValueError('Live observer input differs from the simultaneous sensor')
            files.append(case_root/'compiled_initial_state_dataset.mat')
        else:
            if (r['inspection_pass'] or r['stage'] != 'initialization_state_logging' or r['states']
                    or 'initial_coordinates' in r or 'ps_controller_initial' in r
                    or (case_root/'compiled_initial_state_dataset.mat').exists()):
                raise ValueError('Shared-network failure must not promote missing states')
            signature = [f'SMA_Pump{side}ConnectingPipeVolume.stored_{state}' for side in ('Inlet', 'Outlet') for state in ('mass', 'energy')]
            if not all(s in r['error_message'] for s in signature):
                raise ValueError('Shared-network failure signature changed')
        warning_nodes = []; pressure_residual = None
        if actuate:
            warning_nodes = ['Solver Configuration/EVAL_KEY/STATE_1 (discontinuity)',
                             'ColdObserver_Solver/EVAL_KEY/STATE_1 (discontinuity)',
                             'ColdObserver_Solver/EVAL_KEY/INPUT_3_1_1', 'Solver Configuration/EVAL_KEY/INPUT_47_1_1']
            diary = (case_root/'matlab_diary.log').read_bytes()
            if not all(node.encode('ascii') in diary for node in warning_nodes):
                raise ValueError('Expected algebraic loop evidence changed')
            initial = {x['path']: x for x in r['initial_coordinates']}
            p = [initial[f'SMA_Pump{side}ConnectingPipeVolume/p_I'] for side in ('Inlet', 'Outlet')]
            if any(x['unit'] != 'MPa' for x in p):
                raise ValueError('Unexpected pressure units')
            pressure_residual = p[1]['actual']-p[0]['actual']-next(x['actual'] for x in r['ps_controller_initial'] if x['name'] == 'pressure')
            if abs(pressure_residual) > 1e-9:
                raise ValueError('PS pressure output does not match the initial plant pressure difference')
        results.append(dict(case=label, solver_initialization_completed=separate, actual_initial_coordinates=204 if separate else None,
                            coordinate_audit=coordinate_summary,
                            observer_initial_values_pass=True if separate else None, separate_solver=separate,
                            live_flow_input=live,
                            controller_drives_pump=actuate, actual_sensor_flow_kg_s=r.get('actual_initial_sensor_mdot_kg_s'),
                            global_tolerance_profile=r['global_tolerances_after'],
                            pressure_difference_residual_MPa=pressure_residual,
                            discontinuous_algebraic_loop_warning_nodes=warning_nodes,
                            production_recovery_allowed=False))
        files += [path, case_root/'matlab_diary.log', raw, library]
    freeze_path = repo/'verification/c200_mainline_freeze_contract.json'; freeze = read(freeze_path); files.append(freeze_path)
    for key in ('result', 'checkpoint'):
        p = repo/freeze[key+'_relative_path']
        if sha256(p) != freeze[key+'_sha256']:
            raise ValueError('C200 benchmark changed')
        files.append(p)
    return dict(schema='heatdrive_ecc_cold_passive_ps_network_audit_v5', evidence_audit_pass=True, cases=results,
                tight_global_tolerance_comparison=tight_comparison,
                separated_passive_initialization_pass=True, compiled_inventory_gate_all_completed_cases=True,
                live_flow_passive_initialization_pass=True,
                ps_output_initial_actuation_strict_pass=results[-1]['coordinate_audit']['strict_initial_coordinate_gate'],
                active_feedback_transient_verified=False,
                actuation_has_discontinuous_algebraic_loop_warning=True,
                causal_root_proven=False, closed_loop_initialization_verified=False, trajectory_conservation_verified=False,
                full_device_first_law_verified=False, production_recovery_allowed=False, table4_reproduction_claim=False,
                input_sha256={str(p.relative_to(repo)): sha256(p) for p in files}), rows


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--output-root', type=Path, required=True)
    args = parser.parse_args()
    if args.output_root.exists():
        raise FileExistsError('Never overwrite evidence')
    result, rows = audit(Path(__file__).resolve().parents[1]); args.output_root.mkdir(parents=True)
    (args.output_root/'passive_ps_network_audit.json').write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    with (args.output_root/'initial_coordinates.csv').open('w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)
    displayed = {k: v for k, v in result.items() if k not in ('input_sha256', 'cases')}
    displayed['case_summary'] = [dict(case=x['case'], solver_initialization_completed=x['solver_initialization_completed'],
        coordinate_audit={k: v for k, v in (x['coordinate_audit'] or {}).items() if k != 'failed_coordinate_rows'}) for x in result['cases']]
    print(json.dumps(displayed, indent=2))
