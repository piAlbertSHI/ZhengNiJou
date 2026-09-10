"""Verify reset/coordinate diagnostic evidence and write a nonduplicating manifest."""
import argparse
import json
from pathlib import Path
import numpy as np
from Audit_HeatDriveECC_ColdPassivePSObserver import read,sha256
from Audit_HeatDriveECC_AnalyticResetProbe import audit_case
from Audit_HeatDriveECC_ShiftedInventoryProbe import build as audit_shifted


FOLDERS=[
    'hybrid_held_reset_step_signature_20260910',
    'ode23t_analytic_reset_probe_20260910','ode23tb_analytic_reset_probe_20260910',
    'analytic_reset_probe_audit_20260910','ode23t_20us_analytic_reset_probe_20260910',
    'specific_inventory_hybrid_held_ode23tb_20260910',
    'hybrid_held_ode23tb_interface_failure_audit_20260910',
    'hybrid_held_inventory_roundoff_replay_20260910',
    'hybrid_held_inventory_roundoff_replay_validated_20260910',
    'shifted_inventory_closed_fixture_20260910','shifted_inventory_flow_fixture_20260910',
    'shifted_inventory_fixture_audit_20260910']


def fine_step_evidence(case):
    try:
        return dict(evidence_audit_pass=True,details=audit_case(case))
    except ValueError as error:
        if str(error)!='Actual fixture forcing differs':raise
        t=np.asarray(case['time_s']);f=np.asarray(case['logged_flux'])
        expected=1+2*t+.001*np.floor(t/.001+1e-12)
        mismatch=np.flatnonzero(abs(f-expected)>2e-15)
        return dict(evidence_audit_pass=False,failed_gate=str(error),forcing_threshold=2e-15,
            mismatches=[dict(index=int(i),time_s=float(t[i]),logged_flux=float(f[i]),
                expected_flux=float(expected[i])) for i in mismatch],
            reported_analytic_error_not_independent_qualification=case['max_abs_analytic_error'],
            event_side_sampling_unresolved=True,coupled_fine_step_trial_qualified=False)


def build(repo):
    root=repo/'outputs_storage_audit';cache={}
    def digest(path):
        path=path.resolve()
        if path not in cache:cache[path]=sha256(path)
        return cache[path]
    for sub,name in [('analytic_reset_probe_audit_20260910','analytic_reset_probe_audit.json'),
                     ('hybrid_held_ode23tb_interface_failure_audit_20260910','trbdf2_interface_failure_audit.json'),
                     ('hybrid_held_inventory_roundoff_replay_validated_20260910','inventory_roundoff_replay.json'),
                     ('shifted_inventory_fixture_audit_20260910','shifted_inventory_probe_audit.json')]:
        report=read(root/sub/name)
        for relative,expected in report['input_sha256'].items():
            path=repo/relative
            if digest(path)!=expected:raise ValueError('Archived audit dependency changed: '+relative)
    shifted=audit_shifted(repo)
    original=read(root/'shifted_inventory_fixture_audit_20260910/shifted_inventory_probe_audit.json')
    if shifted!=original:raise ValueError('Recomputed shifted-fixture audit differs')
    fine=read(root/'ode23t_20us_analytic_reset_probe_20260910/ode23t_reset_probe.json')
    if (fine['solver']!='ode23t' or fine['max_step_s']!=.00002 or len(fine['case_results'])!=1
            or fine['actual_coupled_model_tested'] or fine['production_recovery_allowed']):
        raise ValueError('Unexpected fine-step fixture')
    fine_audit=fine_step_evidence(fine['case_results'][0])
    files=[];totals=[]
    for name in FOLDERS:
        folder=root/name
        if not folder.is_dir():raise FileNotFoundError(folder)
        selected=sorted(p for p in folder.rglob('*') if p.is_file())
        size=sum(p.stat().st_size for p in selected)
        totals.append(dict(directory=str(folder.relative_to(repo)),files=len(selected),bytes=size))
        for p in selected:files.append(dict(path=str(p.relative_to(repo)),bytes=p.stat().st_size,sha256=digest(p)))
    frozen_manifest=root/'reset_coordinate_package_20260910/reset_coordinate_package.json'
    if frozen_manifest.exists():
        if digest(frozen_manifest)!='4FB2B282E68F78211C200D014722DD54BD249147ECFB441F86243D7491372D81':
            raise ValueError('Frozen package manifest changed')
        if read(frozen_manifest)['files']!=files:
            raise ValueError('Package files differ from the frozen manifest')
    return dict(package_integrity_pass=True,scientific_goal_complete=False,production_recovery_allowed=False,
        coupled_replacement_qualified=False,mass_coordinate_retention_pass=False,
        fine_step_analytic_fixture_audit=fine_audit,fixture_balances_passing=shifted['passing_local_balances'],
        files=files,directory_totals=totals,file_count=len(files),total_bytes=sum(d['bytes'] for d in totals),
        deleted_files=0,raw_or_checkpoint_duplicated=False,
        checkcode_only_process=dict(session_id=64245,pid=42332,exit_code=1,phase='after checkcode output, MATLAB full exit',
            diagnosis='Stack includes ddux/purecall/mnFullExitFcn; underlying runtime cause not proven; no model simulation.'),
        closed_fixture_process=dict(session_id=90596,exit_code=0),flow_fixture_process=dict(session_id=23708,exit_code=0))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output-root',type=Path,required=True);args=parser.parse_args()
    if args.output_root.exists():raise FileExistsError('Never overwrite a manifest')
    r=build(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'reset_coordinate_package.json').write_text(json.dumps(r,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in r.items() if k not in ('files','directory_totals')},indent=2))
