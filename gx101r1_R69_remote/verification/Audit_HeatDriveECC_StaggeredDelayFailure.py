"""Audit staggered event failure without qualifying its diagnostic state."""
import json
from pathlib import Path
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def build(repo):
    folder=repo/'outputs_storage_audit/nonlinear_ramp_staggered_delay_20260911'
    path=folder/'compiled_states_inspection.json'
    r=json.loads(path.read_text(encoding='utf-8'))
    assert not r['inspection_pass'] and not r['checkpoint_saved']
    assert not r['production_recovery_allowed'] and not r['c200_state_imported']
    assert r['joint_pressure_hold_delay_diagnostic'] is True
    gate=r['hold_gate_delay_contract']
    assert gate['original_event_s']==.10000000000000002 and gate['delayed_event_s']==.13
    assert r['pre_feedback_ramp_contract']['ramp_start_s']==.12
    assert '0.11999999999870169' in r['simulation_error_message']
    files=[dict(path=str(p.relative_to(repo)),bytes=p.stat().st_size,sha256=sha256(p))
           for p in sorted(folder.rglob('*')) if p.is_file()]
    return dict(failure_evidence_audit_pass=True,terminal_session_id=81465,terminal_exit_code=1,
        inspector_commit=r['inspector_commit'],simulation_wall_seconds=r['simulation_wall_seconds'],
        pressure_onset_s=.12,hold_gate_onset_s=.13,failure_time_s=.11999999999870169,
        failure_follows_pressure_onset=True,hot_gate_not_yet_active_at_failure=True,
        initial_targets_and_event_side_audit_pending=True,production_recovery_allowed=False,
        files=files,total_bytes=sum(x['bytes'] for x in files))


if __name__=='__main__':
    repo=Path(__file__).resolve().parents[1]
    out=repo/'outputs_storage_audit/staggered_delay_failure_audit_20260911'
    if out.exists():raise FileExistsError('Never overwrite evidence')
    result=build(repo);out.mkdir()
    (out/'staggered_delay_failure.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('files',)},indent=2))
