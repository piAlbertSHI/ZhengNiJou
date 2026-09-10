"""Preserve a terminal ramp failure; prefix samples cannot qualify the ramp."""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import h5py
import numpy as np
from Audit_HeatDriveECC_ColdPassivePSObserver import read,sha256
from Audit_HeatDriveECC_NonlinearColdInitial import build as initial_audit
from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series,compare_initial


def build(repo):
    initial=initial_audit(repo)
    if not initial['strict_initial_coordinate_gate']:raise ValueError('Frozen initial evidence failed')
    root=repo/'outputs_storage_audit';folder=root/'nonlinear_pre_feedback_ramp_20260910'
    path=folder/'compiled_states_inspection.json';r=read(path)
    if (r['inspection_pass'] or r['stage']!='export_onset_observations' or not r['simulation_error_message']
            or r['inspector_commit']!='82eb2527a185030283fa72a493af2bda86f14cd6'
            or r['diagnostic_stop_time_s']!=.14 or any(r[k] for k in ('production_recovery_allowed','checkpoint_saved',
                'c200_state_imported','failed_terminal_state_imported'))):raise ValueError('Unexpected failure scope')
    if '0.10000000000000037' not in r['simulation_error_message'] or '3.55271E-16' not in r['simulation_error_message']:
        raise ValueError('Different solver failure requires a new diagnosis')
    prior=read(root/'nonlinear_inventory_cold_held_10us_20260910/compiled_states_inspection.json')
    if r['actual_command_schedule']!=prior['actual_command_schedule']:raise ValueError('Full command schedule changed')
    c=r['pre_feedback_ramp_contract'];captured={k:v for k,v in c.items() if k!='qualification_sha256'}
    if c['qualification_sha256']!='2B7B49C81DC82F2F4F114E3FDB6086EF25AE3D4EC816FFBB26AF1134327992BF':raise ValueError('Wrong ramp prerequisite')
    if len(r['runtime_callbacks'])!=3:raise ValueError('Incomplete callback record')
    for actual,old in zip(r['runtime_callbacks'],prior['runtime_callbacks']):
        expected=deepcopy(old);expected.pop('held_interval_contract')
        expected['pre_feedback_ramp_contract']=captured
        expected['pressure_converter']['StopTime']='0.14'
        expected['pressure_converter']['derivative_source']=c['derivative_source']
        if expected!=actual:raise ValueError('Unexpected controller or solver change')
    raw=folder/'failed_public_observations.mat';comparisons=[]
    with h5py.File(raw) as f:
        if bool(f['record/valid_simulation'][()].item()):raise ValueError('Failed result promoted')
        rows=named_rows(f,f['native'])
        if len(rows)!=1276:raise ValueError('Missing native failure evidence')
        for target in r['nonlinear_inventory_contract']['physical_targets']:
            value=scalar_series(rows[target['block_path'],target['state_name']],target['unit'])[0]
            comparisons.append(compare_initial(float(value),target['value']))
        s=f['signals/cold_pre_feedback_derivative_MPa_s'];t=s['time_s'][()].ravel();d=s['values'][()].ravel()
        p=f['signals/cold_observer_pressure'];pt=p['time_s'][()].ravel();pressure=p['values'][()].ravel()
        if (not np.array_equal(t,pt) or not np.isfinite([t,d,pressure]).all() or np.any(np.diff(t)<=0)
                or t[0]!=0 or t[-1]!=.1 or not np.all(d==0) or not np.all(pressure==-1e-6)):
            raise ValueError('Different observed prefix requires separate diagnosis')
        prefix=dict(samples=len(t),last_exported_time_s=float(t[-1]),last_pressure_MPa=float(pressure[-1]),
            last_derivative_MPa_s=float(d[-1]),ramp_start_s=c['ramp_start_s'],
            last_sample_is_before_ramp_start=bool(t[-1]<c['ramp_start_s']))
    files=[dict(path=str(p.relative_to(repo)),bytes=p.stat().st_size,sha256=sha256(p)) for p in sorted(folder.rglob('*')) if p.is_file()]
    return dict(failure_evidence_audit_pass=True,terminal_session_id=78753,terminal_exit_code=1,
        simulation_call_wall_seconds=r['simulation_wall_seconds'],solver_error=r['simulation_error_message'],
        strict_initial_matching_count=sum(x['within_strict_comparison'] for x in comparisons),
        prefix_observations=prefix,actual_failed_iteration_signals_observed=False,
        diagnosis='Failure occurs just beyond ramp start. Last exported values are valid left-side values, not evidence of a wrong right-side derivative.',
        next_required_evidence='Capture solver event/consistency diagnostics at the ramp start before choosing any repair.',
        complete_ramp_verified=False,production_recovery_allowed=False,table4_reproduction_claim=False,
        files=files,evidence_bytes=sum(x['bytes'] for x in files),evidence_file_count=len(files))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output-root',type=Path,required=True);args=parser.parse_args()
    if args.output_root.exists():raise FileExistsError('Never overwrite failure evidence')
    r=build(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'pre_feedback_failure_audit.json').write_text(json.dumps(r,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in r.items() if k!='files'},indent=2))
