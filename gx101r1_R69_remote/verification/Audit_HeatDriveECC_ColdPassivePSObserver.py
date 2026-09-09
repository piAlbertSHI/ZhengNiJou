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


def check_initial(rows, c):
    commands = c['commands']
    expected = dict(mdot=(c['frozen_mdot_kg_s'], 'kg/s'), target=(commands[1]['values'][0], 'kg/s'),
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
              '6dfcb4b7792bfba183da39f53390b77033c8432f', False),
             ('separate', 'specific_inventory_passive_ps_separate_network_initial_20260909',
              'd9a6a4a011989bb4ef1a1c02b595a286715278b9', True)]
    files = [reference_path, native, command_path, qualified_path, flow_path]; results = []; rows = []
    for label, folder, producer, separate in cases:
        case_root = root/folder; path = case_root/'compiled_states_inspection.json'; r = read(path)
        if (r['inspector_commit'] != producer or not r['passive_ps_observer_requested']
                or r.get('separate_observer_network_requested', False) != separate
                or not r['remove_inactive_controller_requested'] or not r['bias_value_path_requested']
                or not r['initialization_only'] or r['diagnostic_stop_time_s'] != 0 or r['inventory_formulation'] != 'specific_inventory'
                or any(r[k] for k in ('ps_controller_requested', 'analytic_pressure_derivative_requested',
                    'c200_state_imported', 'failed_terminal_state_imported', 'checkpoint_saved', 'production_recovery_allowed'))):
            raise ValueError('Wrong passive observer experiment')
        check_runtime(r, targets, 'derivative'); check_derivative(r['initial_pressure_derivative_contract'])
        check_value_edge(r['pressure_value_path_contract'])
        check_inactive_removal(r['inactive_controller_removal_contract'], r['pressure_value_path_contract'])
        c = r['passive_ps_observer_contract']; check_topology(c, separate)
        if (c['commands'] != command['commands'] or c['reference_sha256'] != sha256(command_path)
                or c['qualification_sha256'] != sha256(qualified_path)
                or c['flow_audit_sha256'] != sha256(flow_path) or c['frozen_mdot_kg_s'] != flow['measured_flow_signal_initial_kg_s']
                or c['component_sha256'] != 'EB6AC72398E21E9069674744E1F1ECE1D8133E4729D23E42FDE3AC5C332AEA71'):
            raise ValueError('Observer source, commands or fixed flow changed')
        raw = Path(c['flow_observations_path']); library = Path(c['library_path'])
        if sha256(raw) != c['flow_observations_sha256'] or sha256(library) != c['library_sha256']:
            raise ValueError('Qualified observer artifact changed')
        for callback in r['runtime_callbacks']:
            if (callback['pressure_converter']['value_source'] != c['pressure_value_source']
                    or callback['original_control_state_blocks_present'] != dict(lag=False, integral=False)):
                raise ValueError('Runtime pressure path changed')
            if separate:
                solver = callback['passive_observer_solver']
                if (solver['settings'] != c['observer_solver_contract']['settings'] or not solver['copied_settings_identical']
                        or solver['path'] != c['observer_solver_contract']['observer_path']):
                    raise ValueError('Actual observer solver was not the declared copy')
        if separate:
            if not r['inspection_pass'] or r['stage'] != 'complete' or r['error_message']:
                raise ValueError('Separated observer did not initialize')
            rows = coordinates(r['initial_coordinates'], targets); check_phases(r['cached_phase_targets'], targets, rows)
            tagged = [dict(block_name=x['block_name'], variable_name=x['variable_name'], **decode_tags(x)) for x in r['node_metadata']]
            if not all(x['within_strict_comparison'] for x in rows) or not component_inventory_preserved(tagged, CHAMBERS | BUFFERS):
                raise ValueError('Actual physical inventories were not preserved')
            check_initial(r['ps_controller_initial'], c); files.append(case_root/'compiled_initial_state_dataset.mat')
        else:
            if (r['inspection_pass'] or r['stage'] != 'initialization_state_logging' or r['states']
                    or 'initial_coordinates' in r or 'ps_controller_initial' in r
                    or (case_root/'compiled_initial_state_dataset.mat').exists()):
                raise ValueError('Shared-network failure must not promote missing states')
            signature = [f'SMA_Pump{side}ConnectingPipeVolume.stored_{state}' for side in ('Inlet', 'Outlet') for state in ('mass', 'energy')]
            if not all(s in r['error_message'] for s in signature):
                raise ValueError('Shared-network failure signature changed')
        results.append(dict(case=label, initialization_pass=separate, actual_initial_coordinates=204 if separate else None,
                            observer_initial_values_pass=True if separate else None, separate_solver=separate,
                            controller_drives_pump=False, production_recovery_allowed=False))
        files += [path, case_root/'matlab_diary.log', raw, library]
    freeze_path = repo/'verification/c200_mainline_freeze_contract.json'; freeze = read(freeze_path); files.append(freeze_path)
    for key in ('result', 'checkpoint'):
        p = repo/freeze[key+'_relative_path']
        if sha256(p) != freeze[key+'_sha256']:
            raise ValueError('C200 benchmark changed')
        files.append(p)
    return dict(schema='heatdrive_ecc_cold_passive_ps_network_audit_v1', evidence_audit_pass=True, cases=results,
                separated_passive_initialization_pass=True, physical_inventory_gate=True,
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
    print(json.dumps({k: v for k, v in result.items() if k != 'input_sha256'}, indent=2))
