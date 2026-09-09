"""Audit compile-only loop evidence; never qualify a simulation or recovery point."""
import argparse
import json
from pathlib import Path
from Audit_HeatDriveECC_ColdPassivePSObserver import read, sha256


def check_structure(r, baseline):
    if (not r['inspection_pass'] or not r['algebraic_structure_only'] or r['stage'] != 'complete'
            or not r['initialization_only'] or r['diagnostic_stop_time_s'] != 0
            or r['states'] or 'initial_coordinates' in r
            or any(r[k] for k in ('simulation_run', 'production_recovery_allowed', 'checkpoint_saved',
                                  'c200_state_imported', 'failed_terminal_state_imported'))):
        raise ValueError('Compile-only evidence was promoted or contains state propagation')
    keys = ('inventory_formulation', 'global_solver_configuration', 'global_tolerances_after',
            'consistency_settings_after', 'runtime_solver_options_after', 'source_native_sha256',
            'global_tolerance_override', 'initial_pressure_derivative_contract', 'pressure_value_path_contract',
            'inactive_controller_removal_contract', 'passive_ps_observer_contract', 'ps_initial_actuation_contract')
    if any(r[k] != baseline[k] for k in keys):
        raise ValueError('Structure probe changed the actual-actuation baseline')
    callbacks = r['runtime_callbacks']
    if len(callbacks) != 2:
        raise ValueError('Expected update and loop-query compilation callbacks')
    reference = baseline['runtime_callbacks'][0]
    if len(reference['targets']) != 204 or len({t['path'] for t in reference['targets']}) != 204:
        raise ValueError('Incomplete or duplicate public targets')
    for c in callbacks:
        if c['stage'] != 'InitFcn' or c['simulation_status'] != 'updating':
            raise ValueError('Unexpected runtime initialization or execution')
        for key in ('targets', 'solver_settings', 'global_solver_configuration', 'RelTol', 'AbsTol',
                    'runtime_solver_options', 'LoadInitialState', 'has_private_data', 'pressure_converter',
                    'passive_observer_solver', 'passive_observer_flow_input'):
            if c[key] != reference[key]:
                raise ValueError('Compiled configuration or initial targets changed: '+key)
    data = r['algebraic_structure']
    if (data['matlab_release'] != '2025b' or data['loop_count'] != 1 or len(data['loops']) != 1
            or any(data[k] for k in ('simulation_run', 'trajectory_verified', 'production_recovery_allowed'))):
        raise ValueError('Unexpected loop collection contract')
    loop = data['loops'][0]
    if loop['is_artificial'] is not False:
        raise ValueError('Compiler classification changed')
    prefix = 'heatdrive_ecc_coupled_se21/'
    expected = {
        'Solver\nConfiguration/EVAL_KEY/STATE_1': False,
        'Solver\nConfiguration/EVAL_KEY/OUTPUT_1_0': False,
        'ColdObserver_Solver/EVAL_KEY/INPUT_3_1_1': True,
        'ColdObserver_Solver/EVAL_KEY/STATE_1': False,
        'ColdObserver_Solver/EVAL_KEY/OUTPUT_1_1': False,
        'Solver\nConfiguration/EVAL_KEY/INPUT_47_1_1': True,
    }
    actual = {b['path'].removeprefix(prefix): b['is_algebraic_variable'] for b in loop['blocks']}
    if len(loop['blocks']) != 6 or actual != expected:
        raise ValueError('Loop nodes or algebraic variables changed')
    for b in loop['blocks']:
        expected_type = 'SimscapeInputBlock' if b['is_algebraic_variable'] else 'SimscapeExecutionBlock'
        if b['block_type'] != expected_type or not b['inputs']:
            raise ValueError('Missing compiled block or connectivity evidence')
    return dict(evidence_audit_pass=True, compiled_loop_count=1, compiler_classifies_artificial=False,
                compiled_block_count=6, algebraic_variable_count=2, unchanged_public_targets=204,
                simulation_run=False, initial_coordinate_gate_verified=False, causal_root_proven=False,
                production_recovery_allowed=False, table4_reproduction_claim=False)


def audit(repo):
    root = repo/'outputs_storage_audit'
    source = root/'specific_inventory_ps_actuation_compiled_structure_20260910/compiled_states_inspection.json'
    prior = root/'specific_inventory_separate_ps_actuation_initial_20260909/compiled_states_inspection.json'
    r, baseline = read(source), read(prior)
    if r['inspector_commit'] != 'f8dd92cdfb57d8eacfe28bf9e792ef73b3a037b0':
        raise ValueError('Wrong producer')
    if sha256(prior) != '8A5008B95DBE919EB57498FB4EB6461F833679CDE0D5D04E42A7D68F147019BF':
        raise ValueError('Baseline changed')
    result = check_structure(r, baseline)
    contract = repo/'verification/c200_mainline_freeze_contract.json'; freeze = read(contract)
    files = [source, prior, contract]
    for key in ('result', 'checkpoint'):
        p = repo/freeze[key+'_relative_path']
        if sha256(p) != freeze[key+'_sha256']:
            raise ValueError('Frozen C200 changed')
        files.append(p)
    result['input_sha256'] = {str(p.relative_to(repo)): sha256(p) for p in files}
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = audit(Path(__file__).resolve().parents[1])
    with args.output.open('x', encoding='utf-8') as f:
        f.write(json.dumps(result, indent=2, allow_nan=False)+'\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'input_sha256'}, indent=2))
