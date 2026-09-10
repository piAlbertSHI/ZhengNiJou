"""Audit the declared direct-bias experiment without promoting its terminal state."""
import json
from pathlib import Path
import h5py
import numpy as np
from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series, compare_initial
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def build(repo):
    root=repo/'outputs_storage_audit';folder=root/'nonlinear_ramp_direct_bias_dynamic_20260910'
    path=folder/'compiled_states_inspection.json';r=json.loads(path.read_text(encoding='utf-8'))
    old=json.loads((root/'nonlinear_pre_feedback_ramp_20260910/compiled_states_inspection.json').read_text(encoding='utf-8'))
    assert not r['inspection_pass'] and not r['checkpoint_saved'] and not r['production_recovery_allowed']
    assert not r['c200_state_imported'] and not r['failed_terminal_state_imported']
    assert r['actual_command_schedule']==old['actual_command_schedule']
    assert r['nonlinear_inventory_contract']['physical_targets']==old['nonlinear_inventory_contract']['physical_targets']
    assert r['pre_feedback_ramp_contract']['direct_bias_diagnostic']
    assert '0.099999999999999978' in r['simulation_error_message']
    assert '3.55271E-16' in r['simulation_error_message']
    raw=folder/'failed_public_observations.mat';matches=[]
    with h5py.File(raw) as f:
        native=named_rows(f,f['native']);assert len(native)==1276
        for target in r['nonlinear_inventory_contract']['physical_targets']:
            actual=float(scalar_series(native[target['block_path'],target['state_name']],target['unit'])[0])
            matches.append(compare_initial(actual,target['value'])['within_strict_comparison'])
        s=f['signals/pressure_command_sma_MPa'];t=s['time_s'][()].ravel();p=s['values'][()].ravel()
        assert np.isfinite(t).all() and np.isfinite(p).all()
        last=dict(time_s=float(t[-1]),pressure_MPa=float(p[-1]),samples=len(t))
    assert len(matches)==204 and all(matches)
    files=[dict(path=str(p.relative_to(repo)),bytes=p.stat().st_size,sha256=sha256(p))
           for p in sorted(folder.rglob('*')) if p.is_file()]
    return dict(failure_evidence_audit_pass=True,terminal_session_id=11058,terminal_exit_code=1,
                simulation_wall_seconds=r['simulation_wall_seconds'],initial_targets_matching=204,
                command_schedule_unchanged=True,last_pressure_observation=last,
                observation_feedback_bypass_eliminated_failure=False,complete_ramp_verified=False,
                production_recovery_allowed=False,files=files,total_bytes=sum(p['bytes'] for p in files))


if __name__=='__main__':
    repo=Path(__file__).resolve().parents[1]
    out=repo/'outputs_storage_audit/direct_bias_failure_audit_20260911'
    if out.exists():raise FileExistsError('Never overwrite evidence')
    result=build(repo);out.mkdir()
    (out/'direct_bias_failure_audit.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k!='files'},indent=2))
