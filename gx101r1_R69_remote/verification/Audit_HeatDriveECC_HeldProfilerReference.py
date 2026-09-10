"""Audit a runnable profiler archive without claiming full saved-state coverage."""
import argparse
import json
from pathlib import Path
from Audit_HeatDriveECC_ColdPassivePSObserver import read, sha256
from Audit_HeatDriveECC_HeldProfilerFailure import check_callbacks, OPTIONS, SETTINGS

PRODUCER='a3a24996044059728843133a2d71537271d9bed5'
PROFILE_SHA='E1AB0F0AEB9C1EB482BC385290BAC3CF9C068A220A9F46053929AAB0F6106F11'
BASE_SHA='BB1136088658C84AD15F6A369FF087C617D2F5349F1EE00B0FAEECCFED0F1C21'
FAIL_SHA='790C79509A3DD4173A3DF3707D327A7F39E5C7744D8914B720AF5860238819D9'


def check_summary(summary):
    expected=dict(solver='ode23t',tStart=0,tStop=.04,absTol=1e-8,relTol=1e-6,
        hMax=.00025,hAverage=.00025,steps=160,zcNumber=0,resetNumber=40,jacobianNumber=40,exceptionNumber=0)
    if {k:summary[k] for k in expected}!=expected:
        raise ValueError('Unexpected profiling summary; inspect actual outcome')
    if not isinstance(summary['profileTime'],(int,float)) or not 0<summary['profileTime']<float('inf'):
        raise ValueError('Invalid profiling time')


def audit(repo):
    root=repo/'outputs_storage_audit/specific_inventory_hybrid_held_moderate_profiler_20260910'
    path=root/'compiled_states_inspection.json';r=read(path);p=r['profiler']
    bp=repo/'outputs_storage_audit/hybrid_held_ode23t_audit_20260910/held_interval_audit.json';base=read(bp)
    fp=repo/'outputs_storage_audit/hybrid_held_profiler_failure_audit_20260910/held_profiler_failure_audit.json'
    if sha256(bp)!=BASE_SHA or sha256(fp)!=FAIL_SHA:raise ValueError('Reference evidence changed')
    for relative,expected in base['input_sha256'].items():
        if sha256(repo/relative)!=expected:raise ValueError('Runnable reference or C200 changed')
    rp=repo/'outputs_storage_audit/specific_inventory_hybrid_held_ode23t_after_restart_20260910/compiled_states_inspection.json';reference=read(rp)
    if (r['inspector_commit']!=PRODUCER or not r['held_profiler_requested'] or not r['simulation_run']
            or not r['profiler_capture_pass'] or r['stage']!='profiler_capture_complete'
            or r['runnable_profile_reference_sha256']!=BASE_SHA or r['failed_profiler_evidence_sha256']!=FAIL_SHA
            or any(r[k] for k in ('inspection_pass','held_split_tolerances','initialization_only',
                'c200_state_imported','failed_terminal_state_imported','production_recovery_allowed','checkpoint_saved'))):
        raise ValueError('Wrong reference profiling run')
    settings=dict(SETTINGS,RelTol='1e-6',AbsTol='1e-8')
    if (not p['capture_pass'] or not p['api_returned'] or not p['data_file_exists'] or p['profile_case']!='moderate'
            or p['requested_options']!=OPTIONS or p['expected_settings']!=settings or p['settings_after']!=settings
            or p['AutoScaleAbsTol_before']!='on' or p['AutoScaleAbsTol_after']!='on'
            or p['error_message'] or p['error_report'] or any(p[k] for k in
                ('science_gate_pass','full_jacobian_analyzed','production_recovery_allowed'))):
        raise ValueError('Unexpected archive outcome or science claim')
    check_callbacks(r['runtime_callbacks'],reference['runtime_callbacks']);check_summary(p['api_result']['summary'])
    for k in ('source_native_sha256','global_tolerances_after','global_solver_configuration',
              'consistency_settings_after','runtime_solver_options_after','passive_ps_observer_contract',
              'ps_initial_actuation_contract','held_interval_contract','model_nominal_value_table'):
        if r[k]!=reference[k]:raise ValueError('Changed reference settings: '+k)
    data=root/'solver_profile.mat'
    if sha256(data)!=PROFILE_SHA or p['data_sha256']!=PROFILE_SHA or data.stat().st_size!=p['data_file_bytes']:
        raise ValueError('Profiler archive changed')
    if p['mat_file_variables']['class']!='solverprofiler.internal.SolverProfilerSessionDataClass':
        raise ValueError('Unexpected archive representation')
    diary=(root/'matlab_diary.log').read_bytes()
    if b'simscape.logging.Node' not in diary or b'Simulink.sdi.exportRun' not in diary:
        raise ValueError('Expected Simscape archive warning is missing')
    prepath=root/'pre_simulation_inspection.json';pre=read(prepath)
    if pre['simulation_run'] or pre['global_tolerances_after']!=r['global_tolerances_after']:
        raise ValueError('Incorrect pre-simulation evidence')
    files=[path,prepath,bp,fp,rp,data,root/'matlab_diary.log'];stored=[x for x in root.rglob('*') if x.is_file()]
    return dict(evidence_audit_pass=True,profiler_archive_created=True,profiler_summary=p['api_result']['summary'],
        actual_AutoScaleAbsTol='on',actual_callbacks=3,profiler_call_wall_seconds=p['wall_seconds'],
        requested_options=OPTIONS,archive_matlab_class=p['mat_file_variables']['class'],
        simscape_state_archive_warning_observed=True,full_simscape_state_payload_verified=False,
        jacobian_update_count_reported=40,individual_jacobian_matrices_analyzed=False,
        this_run_initial_coordinates_audited=False,this_run_local_balances_audited=False,
        science_gate_pass=False,production_recovery_allowed=False,unique_root_cause_verified=False,
        full_system_first_law_verified=False,table4_reproduction_claim=False,
        package_file_count=len(stored),package_bytes=sum(x.stat().st_size for x in stored),
        input_sha256={str(x.relative_to(repo)):sha256(x) for x in files})


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output-root',type=Path,required=True);args=parser.parse_args()
    if args.output_root.exists():raise FileExistsError('Never overwrite evidence')
    result=audit(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'held_profiler_reference_audit.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k!='input_sha256'},indent=2))
