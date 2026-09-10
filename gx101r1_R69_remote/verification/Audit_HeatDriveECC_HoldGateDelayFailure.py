"""Preserve the single-event delay failure without qualifying a recovery state."""
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series, compare_initial
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def build(repo):
    root = repo / 'outputs_storage_audit'
    folder = root / 'nonlinear_ramp_hold_gate_delay_20260911'
    record_path = folder / 'compiled_states_inspection.json'
    r = json.loads(record_path.read_text(encoding='utf-8'))
    baseline_path = root / 'nonlinear_ramp_direct_bias_dynamic_20260910/compiled_states_inspection.json'
    old = json.loads(baseline_path.read_text(encoding='utf-8'))
    for key in ('inspection_pass', 'checkpoint_saved', 'production_recovery_allowed',
                'c200_state_imported', 'failed_terminal_state_imported'):
        assert r[key] is False, key
    assert r['actual_command_schedule'] == old['actual_command_schedule']
    targets = r['nonlinear_inventory_contract']['physical_targets']
    assert targets == old['nonlinear_inventory_contract']['physical_targets']
    for key in ('time_s', 'bias_MPa', 'derivative_MPa_s', 'direct_bias_diagnostic'):
        assert r['pre_feedback_ramp_contract'][key] == old['pre_feedback_ramp_contract'][key]
    gate = r['hold_gate_delay_contract']
    assert gate['only_one_command_time_changed'] is True
    assert gate['original_event_s'] == .10000000000000002
    assert gate['delayed_event_s'] == .12
    assert gate['inactive'] == 1e-6 and gate['active'] == 1e6
    callbacks = r['runtime_callbacks']
    assert callbacks and all(c['hold_gate_delay_contract'] == gate for c in callbacks)
    assert '0.099999999999999978' in r['simulation_error_message']
    assert '3.55271E-16' in r['simulation_error_message']
    with h5py.File(folder / 'failed_public_observations.mat') as f:
        native = named_rows(f, f['native'])
        assert len(native) == 1276
        matches = [compare_initial(float(scalar_series(
            native[t['block_path'], t['state_name']], t['unit'])[0]),
            t['value'])['within_strict_comparison'] for t in targets]
        assert len(matches) == 204 and all(matches)
        s = f['signals/pressure_command_sma_MPa']
        times, pressure = s['time_s'][()].ravel(), s['values'][()].ravel()
        assert np.isfinite(times).all() and np.isfinite(pressure).all()
        last = dict(time_s=float(times[-1]), pressure_MPa=float(pressure[-1]), samples=len(times))
    files = [dict(path=str(p.relative_to(repo)), bytes=p.stat().st_size, sha256=sha256(p))
             for p in sorted(folder.rglob('*')) if p.is_file()]
    return dict(failure_evidence_audit_pass=True, terminal_session_id=65791,
                terminal_exit_code=1, inspector_commit=r['inspector_commit'],
                baseline_record_sha256=sha256(baseline_path),
                simulation_wall_seconds=r['simulation_wall_seconds'],
                initial_targets_matching=204, original_schedule_preserved=True,
                pressure_commands_unchanged=True, runtime_gate_contract=gate,
                last_pressure_observation=last, failure_moved_to_delayed_gate=False,
                complete_ramp_verified=False, production_recovery_allowed=False,
                files=files, total_bytes=sum(p['bytes'] for p in files))


if __name__ == '__main__':
    repo = Path(__file__).resolve().parents[1]
    out = repo / 'outputs_storage_audit/hold_gate_delay_failure_audit_20260911'
    if out.exists():
        raise FileExistsError('Never overwrite evidence; use build(repo) for read-only verification')
    result = build(repo)
    out.mkdir()
    (out / 'hold_gate_delay_failure_audit.json').write_text(
        json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in result.items() if k != 'files'}, indent=2))
