"""Audit the failed split-tolerance experiment, never authorize continuation."""
import argparse
import csv
import json
from copy import deepcopy
from decimal import Decimal
from pathlib import Path

import h5py
import numpy as np
from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series, compare_initial
from Audit_HeatDriveECC_ColdPassivePSObserver import read, sha256, summarize_coordinates
from Audit_HeatDriveECC_HeldErrorControl import check_error_policy, POLICY, TOL
from Audit_HeatDriveECC_HybridHeldResult import check_discrete_constitutive_blocks
from Audit_HeatDriveECC_HeldIntervalBalance import check_held_contract

ROOT = 'specific_inventory_hybrid_held_split_tolerances_20260910'
BASE = 'specific_inventory_hybrid_held_ode23t_after_restart_20260910'
PRODUCER = '516231e0b3b395651a0e7c839e71e3c8f28d475d'
BASE_SHA = '32E1A6091A04A3150CBF6E23C101C65429E0D4B98181321A3EFA5ED29CFF352F'
PRIOR_SHA = 'BB1136088658C84AD15F6A369FF087C617D2F5349F1EE00B0FAEECCFED0F1C21'
LOCAL = dict(ConsistencyTolSource='LOCAL', ConsistencyAbsTol='1e-8', ConsistencyRelTol='1e-6')


def local_settings(settings):
    if settings['ConsistencyTolSource'] != 'GLOBAL' or settings['ConsistencyTolFactor'] != '0.001':
        raise ValueError('Unexpected reference consistency controls')
    return dict(settings, **LOCAL)


def effective_consistency(settings, global_tolerances):
    if settings['ConsistencyTolSource'] not in ('GLOBAL', 'LOCAL'):
        raise ValueError('Unknown consistency source')
    factor = Decimal(settings['ConsistencyTolFactor'])
    return tuple(factor * Decimal(global_tolerances[k] if settings['ConsistencyTolSource'] == 'GLOBAL'
                 else settings['Consistency' + k]) for k in ('AbsTol', 'RelTol'))


def check_configuration(r, b):
    check_error_policy(r['solver_failure_policy_before'], r['solver_failure_policy_after'], r['global_tolerances_after'])
    expected = local_settings(b['consistency_settings_after'])
    if r['consistency_settings_after'] != expected or effective_consistency(expected, TOL) != effective_consistency(
            b['consistency_settings_after'], b['global_tolerances_after']):
        raise ValueError('Effective consistency controls were not preserved')
    observer = deepcopy(b['passive_ps_observer_contract'])
    observer['observer_solver_contract']['settings'] = local_settings(observer['observer_solver_contract']['settings'])
    if r['passive_ps_observer_contract'] != observer:
        raise ValueError('Observer changed beyond declared local consistency controls')
    # Compare every captured callback field, not just the selected solver fields.
    if len(r['runtime_callbacks']) != 3 or len(b['runtime_callbacks']) != 3:
        raise ValueError('Incomplete runtime callbacks')
    for c, old in zip(r['runtime_callbacks'], b['runtime_callbacks']):
        expected_callback = deepcopy(old)
        expected_callback.update(TOL)
        expected_callback['solver_settings'] = local_settings(old['solver_settings'])
        expected_callback['passive_observer_solver']['settings'] = local_settings(old['passive_observer_solver']['settings'])
        if c != expected_callback:
            raise ValueError('Unexpected actual callback change')
        check_discrete_constitutive_blocks(c)
    for k in ('global_solver_configuration', 'global_tolerances', 'runtime_solver_options_after',
              'source_native_sha256', 'inventory_formulation', 'output_sampling_settings',
              'ps_initial_actuation_contract', 'held_interval_contract', 'held_max_step_override_s',
              'consistency_settings_before', 'model_nominal_value_table', 'buffer_nominal_changes',
              'initial_pressure_derivative_contract', 'pressure_value_path_contract',
              'inactive_controller_removal_contract', 'solver_iteration_options'):
        if r[k] != b[k]:
            raise ValueError('Unexpected physical or numerical change: ' + k)
    check_held_contract(r['held_interval_contract'])


def failed_history(row):
    t = row['time_s'][:].ravel(); v = row['values'][:].ravel()
    if (t.size == 0 or t[0] != 0 or t.shape != v.shape or not np.isfinite([t, v]).all()
            or np.any(np.diff(t) < 0) or not 0 <= t[-1] < 1e-290):
        raise ValueError('Unexpected failed-history endpoint or shape')
    return t, v


def audit(repo):
    root = repo/'outputs_storage_audit'/ROOT
    path = root/'compiled_states_inspection.json'; r = read(path)
    bp = repo/'outputs_storage_audit'/BASE/'compiled_states_inspection.json'
    prior = repo/'outputs_storage_audit/hybrid_held_ode23t_audit_20260910/held_interval_audit.json'
    if sha256(bp) != BASE_SHA or sha256(prior) != PRIOR_SHA:
        raise ValueError('Qualified comparison evidence changed')
    b = read(bp)
    if (r['inspector_commit'] != PRODUCER or r['inspection_pass'] or not r['simulation_run']
            or not r['held_split_tolerances'] or not r['held_error_control_trial']
            or r['held_error_control_level'] != 'moderate' or r['held_solver_method'] != 'ode23t'
            or r['held_one_step_rejection_sha256'] != PRIOR_SHA or r['diagnostic_stop_time_s'] != .04
            or r['stage'] != 'export_onset_observations' or r['algebraic_structure']['loop_count'] != 0
            or any(r[k] for k in ('initialization_only', 'c200_state_imported',
                'failed_terminal_state_imported', 'production_recovery_allowed', 'checkpoint_saved'))):
        raise ValueError('Wrong failed diagnostic')
    check_configuration(r, b)
    error = r['simulation_error_message']
    if error != r['error_message'] or '1.584348158130581e-301' not in error or '\u5947\u5f02\u8fed\u4ee3\u77e9\u9635' not in error:
        raise ValueError('Unexpected failure; diagnose before changing the audit')
    prepath = root/'pre_simulation_inspection.json'; pre = read(prepath)
    if pre['simulation_run'] or pre['stage'] != 'ready_for_held_error_control_simulation':
        raise ValueError('Incorrect pre-simulation record')
    for k in ('global_solver_configuration', 'global_tolerances_after', 'consistency_settings_after',
              'passive_ps_observer_contract', 'solver_failure_policy_after', 'held_split_tolerances',
              'held_one_step_rejection_sha256', 'inspector_commit', 'source_native_sha256'):
        if pre[k] != r[k]: raise ValueError('Pre/post configuration differs: ' + k)
    tp = repo/'outputs_storage_audit/conservative_buffer_coupled_cycle_20260909/conservative/public_inventory_targets.json'
    reference = read(tp); targets = reference['targets']; native = tp.parent.parent/'native/observations.mat'
    if len(targets) != 204 or sha256(native) != reference['source_sha256'] or r['source_native_sha256'] != reference['source_sha256']:
        raise ValueError('Public cold reference changed')
    raw = root/'failed_public_observations.mat'; comparisons = []; times = []
    with h5py.File(raw) as f:
        rows = named_rows(f, f['native'])
        if len(rows) != 1258 or len({p for p, n in rows}) != 119:
            raise ValueError('Incomplete failed storage export')
        for row in rows.values(): times.append(float(failed_history(row)[0][-1]))
        for target in targets:
            v = scalar_series(rows[target['block_path'], target['state_name']], target['unit'])
            comparisons.append(dict(path=target['path'], priority=target['priority'], unit=target['unit'],
                **compare_initial(float(v[0]), target['value']), max_change_over_failed_interval=float(np.max(abs(v-v[0])))))
    freeze_path = repo/'verification/c200_mainline_freeze_contract.json'; freeze = read(freeze_path)
    files = [path, prepath, bp, prior, tp, native, raw, root/'matlab_diary.log', freeze_path]
    for k in ('result', 'checkpoint'):
        p = repo/freeze[k+'_relative_path']
        if sha256(p) != freeze[k+'_sha256']: raise ValueError('C200 changed')
        files.append(p)
    stored = [p for p in root.rglob('*') if p.is_file()]
    return dict(evidence_audit_pass=True, rejected_diagnostic=True, initial_coordinate_audit=summarize_coordinates(comparisons),
        global_tolerances=TOL, consistency_settings=r['consistency_settings_after'],
        effective_consistency_abs_rel=[str(v) for v in effective_consistency(r['consistency_settings_after'], TOL)],
        simulation_wall_seconds=r['simulation_wall_seconds'], actual_callbacks=3, compiled_algebraic_loops=0,
        exported_storage_leaves=len(rows), exported_endpoint_range_s=[min(times), max(times)], required_endpoint_s=.04,
        complete_held_interval=False, local_balance_gate=False, unique_root_cause_verified=False,
        compiled_inventory_gate_verified=False, production_recovery_allowed=False,
        full_system_first_law_verified=False, table4_reproduction_claim=False, preserved_error_message=error,
        package_file_count=len(stored), package_bytes=sum(p.stat().st_size for p in stored),
        input_sha256={str(p.relative_to(repo)):sha256(p) for p in files}), comparisons


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-root', type=Path, required=True); args = parser.parse_args()
    if args.output_root.exists(): raise FileExistsError('Never overwrite evidence')
    report, rows = audit(Path(__file__).resolve().parents[1]); args.output_root.mkdir(parents=True)
    (args.output_root/'held_split_failure_audit.json').write_text(json.dumps(report, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    with (args.output_root/'initial_coordinates.csv').open('x', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)
    print(json.dumps({k:v for k,v in report.items() if k not in ('input_sha256', 'preserved_error_message')}, indent=2))
