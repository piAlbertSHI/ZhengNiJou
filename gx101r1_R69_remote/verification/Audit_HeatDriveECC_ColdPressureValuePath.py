"""Audit the single value-edge cold initialization, not a closed-loop cycle."""
import argparse
import copy
import csv
import json
import math
from pathlib import Path
from Audit_HeatDriveECC_ColdChamberRejection import read
from Audit_HeatDriveECC_ColdInitialTolerance import coordinates
from Audit_HeatDriveECC_ColdInitializationPhases import check_phases
from Audit_HeatDriveECC_ColdProjectionInitialization import check_runtime, check_derivative
from Audit_HeatDriveECC_CompiledInventoryStates import CHAMBERS, BUFFERS, decode_tags, component_inventory_preserved
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def check_value_edge(c):
    prefix = 'heatdrive_ecc_coupled_se21/'
    converter, bias, saturation = (prefix+x for x in ('SMAPressurePI_SimulinkPS', 'SMAPressureBiasFromWorkspace', 'SMAPressurePI_Saturation'))
    before, after = c['inputs_before'], c['inputs_after']
    if (len(before) != 15 or len({x['path'] for x in before}) != 15 or c['original_controller_block_count'] != 15
            or c['converter'] != converter or c['value_source_before'] != saturation or c['value_source_after'] != bias
            or not c['model_block_set_unchanged'] or not c['converter_physical_line_unchanged']
            or not c['original_controller_retained'] or c['allowed_stop_time_s'] != 0
            or c['c200_state_imported'] or c['production_recovery_allowed']):
        raise ValueError('Not a bounded single-edge experiment')
    expected = copy.deepcopy(before)
    selected = [x for x in expected if x['path'] == converter]
    if len(selected) != 1 or selected[0]['sources'] != [saturation, c['derivative_source']]:
        raise ValueError('Original converter inputs differ')
    selected[0]['sources'][0] = bias
    if after != expected:
        raise ValueError('More than the declared value edge changed')
    low, high = c['saturation_limits_MPa']; value = c['initial_bias_MPa']
    if not all(math.isfinite(x) for x in (low, high, value)) or not low < value < high:
        raise ValueError('Initial bias is outside the unchanged saturation')
    return True


def audit(repo):
    root = repo/'outputs_storage_audit/specific_inventory_original_bias_value_initial_20260909'
    record_path = root/'compiled_states_inspection.json'; r = read(record_path)
    if (r['inspector_commit'] != 'c34840e0f109d313ff8a58a6a0b30556399ce793'
            or not r['inspection_pass'] or r['stage'] != 'complete' or r['error_message']
            or not r['bias_value_path_requested'] or not r['initialization_only'] or r['diagnostic_stop_time_s'] != 0
            or r['inventory_formulation'] != 'specific_inventory'
            or any(r.get(k, False) for k in ('ps_controller_requested', 'initial_bias_only_requested',
                    'initial_mdot_probe_requested', 'constant_bias_derivative_requested', 'analytic_pressure_derivative_requested',
                    'c200_state_imported', 'failed_terminal_state_imported', 'checkpoint_saved', 'production_recovery_allowed'))):
        raise ValueError('Wrong experiment or incomplete initialization')
    reference_path = repo/'outputs_storage_audit/conservative_buffer_coupled_cycle_20260909/conservative/public_inventory_targets.json'
    reference = read(reference_path); targets = reference['targets']
    native = reference_path.parent.parent/'native/observations.mat'
    if len(targets) != 204 or reference['has_private_data'] or sha256(native) != reference['source_sha256']:
        raise ValueError('Native cold targets changed')
    check_runtime(r, targets, 'derivative'); check_derivative(r['initial_pressure_derivative_contract'])
    c = r['pressure_value_path_contract']; check_value_edge(c)
    source = Path(c['reference_path'])
    if sha256(source) != c['reference_sha256'] or c['reference_sha256'] != 'EE5C16D580693FCA925D24D0DB2A8E021BAC65E36F0A77A8E12AE795070ACEE2':
        raise ValueError('Controller reference changed')
    b = read(source)
    if [x['path'] for x in c['inputs_before']] != [x['path'] for x in b['blocks']]:
        raise ValueError('Controller coverage differs')
    for actual, expected in zip(c['inputs_before'], b['blocks']):
        sources = [x['source_block'] for x in expected['inputs']]
        if actual['path'] == c['converter']:
            sources.append(c['derivative_source'])
        if actual['sources'] != sources:
            raise ValueError('Original controller wiring differs')
    for callback in r['runtime_callbacks']:
        if callback['pressure_converter']['value_source'] != c['value_source_after']:
            raise ValueError('Runtime value input does not match the ablation')
    rows = coordinates(r['initial_coordinates'], targets)
    check_phases(r['cached_phase_targets'], targets, rows)
    tagged = [dict(block_name=x['block_name'], variable_name=x['variable_name'], **decode_tags(x)) for x in r['node_metadata']]
    retained = component_inventory_preserved(tagged, CHAMBERS | BUFFERS)
    if not retained or not all(x['within_strict_comparison'] for x in rows):
        raise ValueError('Actual inventory coordinates or differential states did not pass')
    controller_states = []
    for name in ('SMAPressurePI_ErrorLag', 'SMAPressurePI_Integrator'):
        matches = [x for x in r['states'] if x['block_path'] == ['heatdrive_ecc_coupled_se21/'+name]]
        if (len(matches) != 1 or matches[0]['values_class'] != 'timeseries'
                or matches[0]['time_s'] != 0 or matches[0]['value_size'] != [1, 1]):
            raise ValueError('Original controller state logging was lost')
        controller_states.append(name)
    initial = {x['path']: x for x in r['initial_coordinates']}
    pressures = [initial[f'SMA_Pump{side}ConnectingPipeVolume/p_I'] for side in ('Inlet', 'Outlet')]
    if any(x['unit'] != 'MPa' for x in pressures):
        raise ValueError('Unexpected chamber pressure units')
    pressure_error = pressures[1]['actual']-pressures[0]['actual']-c['initial_bias_MPa']
    if abs(pressure_error) > 1e-9:
        raise ValueError('Actual initial pressure difference disagrees with the bias')
    files = [record_path, root/'compiled_initial_state_dataset.mat', root/'matlab_diary.log', reference_path, native, source]
    library = Path(r['loaded_chamber_library'])
    if sha256(library) != r['loaded_library_sha256']:
        raise ValueError('Compiled chamber library changed')
    files.append(library)
    freeze_path = repo/'verification/c200_mainline_freeze_contract.json'; freeze = read(freeze_path); files.append(freeze_path)
    for key in ('result', 'checkpoint'):
        p = repo/freeze[key+'_relative_path']
        if sha256(p) != freeze[key+'_sha256']:
            raise ValueError('C200 benchmark changed')
        files.append(p)
    return dict(schema='heatdrive_ecc_cold_pressure_value_path_audit_v1', initial_point_audit_pass=True,
                matching_initial_coordinates=len(rows), compiled_inventory_gate=retained,
                original_controller_retained=True, changed_value_edges=1,
                original_controller_logged_states=controller_states,
                initial_pressure_difference_residual_MPa=pressure_error, pressure_difference_limit_MPa=1e-9,
                original_feedback_value_path_required_for_this_initial_point=False,
                ps_controller_initialization_verified=False, full_cycle_derivative_verified=False,
                trajectory_conservation_verified=False, production_recovery_allowed=False,
                full_device_first_law_verified=False, table4_reproduction_claim=False,
                input_sha256={str(p.relative_to(repo)): sha256(p) for p in files}), rows


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--output-root', type=Path, required=True)
    args = parser.parse_args()
    if args.output_root.exists():
        raise FileExistsError('Never overwrite evidence')
    result, rows = audit(Path(__file__).resolve().parents[1]); args.output_root.mkdir(parents=True)
    (args.output_root/'pressure_value_path_audit.json').write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    with (args.output_root/'initial_coordinates.csv').open('w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)
    print(json.dumps({k: v for k, v in result.items() if k != 'input_sha256'}, indent=2))
