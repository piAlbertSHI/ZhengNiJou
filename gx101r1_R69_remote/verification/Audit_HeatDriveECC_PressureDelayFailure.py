"""Audit pressure-onset isolation; this never promotes failed observations."""
import json
import argparse
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series, compare_initial
from Audit_HeatDriveECC_HoldDelayPrefix import compare
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def build(repo, joint=False):
    root = repo / 'outputs_storage_audit'
    folder = root / ('nonlinear_ramp_joint_delay_20260911' if joint else 'nonlinear_ramp_pressure_delay_20260911')
    baseline = root / 'nonlinear_ramp_direct_bias_dynamic_20260910'
    r = json.loads((folder / 'compiled_states_inspection.json').read_text(encoding='utf-8'))
    old = json.loads((baseline / 'compiled_states_inspection.json').read_text(encoding='utf-8'))
    for key in ('inspection_pass', 'checkpoint_saved', 'production_recovery_allowed',
                'failed_terminal_state_imported', 'c200_state_imported'):
        assert r[key] is False, key
    assert r['actual_command_schedule'] == old['actual_command_schedule']
    targets = r['nonlinear_inventory_contract']['physical_targets']
    assert targets == old['nonlinear_inventory_contract']['physical_targets']
    c = r['pre_feedback_ramp_contract']
    assert c['ramp_start_s'] == .12 and c['pressure_onset_delayed']
    assert c['ramp_slope_MPa_s'] == old['pre_feedback_ramp_contract']['ramp_slope_MPa_s']
    expected_failure = '0.11999999999870169' if joint else '0.099999999999999978'
    assert expected_failure in r['simulation_error_message']
    if joint:
        assert r['joint_pressure_hold_delay_diagnostic'] is True
        gate = r['hold_gate_delay_contract']
        assert gate['delayed_event_s'] == .12 and gate['only_one_command_time_changed']
        assert gate['inactive'] == 1e-6 and gate['active'] == 1e6
    assert r['runtime_callbacks']
    for cb in r['runtime_callbacks']:
        runtime = cb['pre_feedback_ramp_contract']
        assert runtime['pressure_onset_delayed'] and runtime['ramp_start_s'] == .12
        assert runtime['bias_MPa'] == c['bias_MPa']
        assert runtime['derivative_MPa_s'] == c['derivative_MPa_s']
        if joint:
            assert cb['hold_gate_delay_contract'] == gate
    rows = []
    with h5py.File(folder / 'failed_public_observations.mat') as f, h5py.File(
            baseline / 'failed_public_observations.mat') as base:
        native = named_rows(f, f['native'])
        assert len(native) == 1276 and len(targets) == 204
        for t in targets:
            actual = float(scalar_series(native[t['block_path'], t['state_name']], t['unit'])[0])
            assert compare_initial(actual, t['value'])['within_strict_comparison']
        assert set(f['signals']) == set(base['signals'])
        for name in f['signals']:
            a, b = f['signals'][name], base['signals'][name]
            rows.append(dict(signal=name, time=compare(a['time_s'][()], b['time_s'][()]),
                             values=compare(a['values'][()], b['values'][()])))
        s = f['signals/pressure_command_sma_MPa']
        last = dict(time_s=float(s['time_s'][()].ravel()[-1]),
                    pressure_MPa=float(s['values'][()].ravel()[-1]))
    assert all(row['values']['finite'] for row in rows)
    if joint:
        assert .1 < last['time_s'] < .120000000001
    files = [dict(path=str(p.relative_to(repo)), bytes=p.stat().st_size, sha256=sha256(p))
             for p in sorted(folder.rglob('*')) if p.is_file()]
    return dict(failure_evidence_audit_pass=True, terminal_session_id=99376 if joint else 67486, terminal_exit_code=1,
                inspector_commit=r['inspector_commit'], simulation_wall_seconds=r['simulation_wall_seconds'],
                initial_targets_matching=204, pressure_ramp_start_s=.12,
                pressure_slope_MPa_s=c['ramp_slope_MPa_s'], last_pressure_observation=last,
                public_signals=len(rows), exact_time_count=sum(x['time']['exactly_equal'] for x in rows),
                exact_value_count=sum(x['values']['exactly_equal'] for x in rows),
                joint_delay=joint, failure_moved_to_pressure_onset=joint, production_recovery_allowed=False,
                signals=rows, files=files, total_bytes=sum(p['bytes'] for p in files))


if __name__ == '__main__':
    repo = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument('--joint', action='store_true')
    args = parser.parse_args()
    out = repo / 'outputs_storage_audit' / ('joint_delay_failure_audit_20260911' if args.joint else 'pressure_delay_failure_audit_20260911')
    if out.exists():
        raise FileExistsError('Never overwrite evidence; build(repo) is read-only')
    result = build(repo, args.joint)
    out.mkdir()
    (out / 'pressure_delay_failure_audit.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in result.items() if k not in ('signals', 'files')}, indent=2))
