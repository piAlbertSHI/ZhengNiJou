"""Audit the rejected global error-control trial without granting continuation."""
import argparse
import csv
import json
from pathlib import Path
import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series, compare_initial
from Audit_HeatDriveECC_ColdPassivePSObserver import read, sha256, summarize_coordinates
from Audit_HeatDriveECC_HeldIntervalBalance import check_held_contract


ROOT = 'specific_inventory_hybrid_held_error_control_failfast_20260910'
PRODUCER = '6606ab02d6aff159f01aff44f50f16e4f20a3e38'
BASE_SHA = 'BF349757912910B57EFD1895E48EC8EF1B1E72299BE53D817716B0697325E51E'
TOL = dict(RelTol='1e-10', AbsTol='1e-12')
POLICY = dict(MinStepSizeMsg='error', MaxConsecutiveMinStep='1', MinStep='auto')


def check_error_policy(before, after, tolerances):
    if (tolerances != TOL or after != POLICY
            or before != dict(POLICY, MinStepSizeMsg='warning')):
        raise ValueError('Error controls or fail-fast action changed')


def check_record(r, base):
    if (r['inspector_commit'] != PRODUCER or r['inspection_pass'] or not r['simulation_run']
            or not r['held_error_control_trial'] or not r['global_tolerance_override']
            or r['diagnostic_stop_time_s'] != .04 or r['algebraic_structure']['loop_count'] != 0
            or any(r[k] for k in ('initialization_only', 'c200_state_imported',
                'failed_terminal_state_imported', 'production_recovery_allowed', 'checkpoint_saved'))):
        raise ValueError('Wrong rejected diagnostic')
    check_error_policy(r['solver_failure_policy_before'], r['solver_failure_policy_after'], r['global_tolerances_after'])
    for k in ('global_solver_configuration', 'global_tolerances', 'consistency_settings_after',
              'runtime_solver_options_after', 'passive_ps_observer_contract', 'ps_initial_actuation_contract',
              'source_native_sha256', 'inventory_formulation', 'output_sampling_settings',
              'held_interval_contract', 'held_max_step_override_s'):
        if r[k] != base[k]:
            raise ValueError('Change outside declared global error control: ' + k)
    check_held_contract(r['held_interval_contract'])
    callbacks = r['runtime_callbacks']
    if [(c['stage'], c['simulation_status']) for c in callbacks] != [
            ('InitFcn','initializing'), ('StartFcn','initializing'), ('StopFcn','terminating')]:
        raise ValueError('Incomplete actual runtime callbacks')
    for c, b in zip(callbacks, base['runtime_callbacks']):
        if {k:c[k] for k in TOL} != TOL or c['solver_failure_policy'] != POLICY:
            raise ValueError('Actual error controls differ')
        for k in ('targets', 'solver_settings', 'runtime_solver_options', 'LoadInitialState',
                  'has_private_data', 'external_controller_lag', 'passive_observer_solver',
                  'passive_observer_flow_input', 'global_solver_configuration',
                  'pressure_converter', 'held_interval_contract', 'output_sampling_settings'):
            if c[k] != b[k]:
                raise ValueError('Actual physical/interface configuration differs: ' + k)
    error = r['simulation_error_message']
    if (error != r['error_message'] or '4.1534373984471013e-174' not in error
            or '1.4756E-188' not in error):
        raise ValueError('Unexpected failure; diagnose before changing the audit')


def audit(repo):
    root = repo/'outputs_storage_audit'/ROOT
    path = root/'compiled_states_inspection.json'; r = read(path)
    bp = repo/'outputs_storage_audit/specific_inventory_hybrid_held_quarterstep_20260910/compiled_states_inspection.json'
    if sha256(bp) != BASE_SHA: raise ValueError('Quarter-step baseline changed')
    base = read(bp); check_record(r, base)
    prepath = root/'pre_simulation_inspection.json'; pre = read(prepath)
    if pre['simulation_run'] or pre['stage'] != 'ready_for_held_error_control_simulation':
        raise ValueError('Incorrect pre-simulation stage')
    for k in ('global_solver_configuration', 'global_tolerances_after', 'solver_failure_policy_after',
              'held_interval_contract', 'source_native_sha256', 'inspector_commit'):
        if pre[k] != r[k]: raise ValueError('Pre/post configuration differs: ' + k)
    tp = repo/'outputs_storage_audit/conservative_buffer_coupled_cycle_20260909/conservative/public_inventory_targets.json'
    reference = read(tp); targets = reference['targets']; native = tp.parent.parent/'native/observations.mat'
    if len(targets) != 204 or sha256(native) != reference['source_sha256']:
        raise ValueError('Public cold reference changed')
    raw = root/'failed_public_observations.mat'; comparisons = []
    with h5py.File(raw) as f:
        rows = named_rows(f, f['native']); times = []
        if len(rows) != 1258: raise ValueError('Incomplete failed storage export')
        for row in rows.values():
            t = row['time_s'][:].ravel(); v = row['values'][:].ravel()
            if (t.size == 0 or t[0] != 0 or t.shape != v.shape or not np.isfinite([t,v]).all()
                    or np.any(np.diff(t) < 0) or t[-1] >= 1e-100):
                raise ValueError('Unexpected failed-history shape or endpoint')
            times.append(float(t[-1]))
        for target in targets:
            row = rows[target['block_path'], target['state_name']]
            v = scalar_series(row, target['unit'])
            comparisons.append(dict(path=target['path'], priority=target['priority'], unit=target['unit'],
                                    **compare_initial(float(v[0]), target['value']),
                                    max_change_over_failed_interval=float(np.max(abs(v-v[0])))))
    freeze_path = repo/'verification/c200_mainline_freeze_contract.json'; freeze = read(freeze_path)
    files = [path, prepath, bp, tp, native, raw, root/'matlab_diary.log', freeze_path]
    for k in ('result','checkpoint'):
        p = repo/freeze[k+'_relative_path']
        if sha256(p) != freeze[k+'_sha256']: raise ValueError('C200 changed')
        files.append(p)
    stored = [p for p in root.rglob('*') if p.is_file()]
    return dict(evidence_audit_pass=True, rejected_diagnostic=True, initial_coordinate_audit=summarize_coordinates(comparisons),
                global_tolerances=TOL, global_max_step_s=.00025, solver_failure_policy=POLICY,
                simulation_wall_seconds=r['simulation_wall_seconds'], actual_callbacks=len(r['runtime_callbacks']),
                compiled_algebraic_loops=0, exported_storage_leaves=len(rows),
                exported_endpoint_range_s=[min(times),max(times)], required_endpoint_s=.04,
                complete_held_interval=False, local_balance_gate=False, unique_root_cause_verified=False,
                production_recovery_allowed=False, full_system_first_law_verified=False, table4_reproduction_claim=False,
                preserved_error_message=r['simulation_error_message'],
                package_file_count=len(stored), package_bytes=sum(p.stat().st_size for p in stored),
                input_sha256={str(p.relative_to(repo)):sha256(p) for p in files}), comparisons


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output-root',type=Path,required=True);args=p.parse_args()
    if args.output_root.exists(): raise FileExistsError('Never overwrite evidence')
    report, rows = audit(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'held_error_control_audit.json').write_text(json.dumps(report,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    with (args.output_root/'initial_coordinates.csv').open('x',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
    print(json.dumps({k:v for k,v in report.items() if k not in ('input_sha256','preserved_error_message')},indent=2))
