"""Verify profiler failure and actual configuration; no saved Jacobian claim."""
import argparse
import json
from copy import deepcopy
from pathlib import Path
from Audit_HeatDriveECC_ColdPassivePSObserver import read, sha256

ROOT='specific_inventory_hybrid_held_split_profiler_20260910'
PRODUCER='0bc787b21a33efa09d043647768f005a275ddd42'
PRIOR_SHA='4A398B9E07CA55B2A84FEBBF440A601274BBE0102624AE0383AC39E3C6002370'
OPTIONS=dict(SaveStates='on',SaveSimscapeStates='on',SaveJacobian='on',SaveZCSignals='off',OpenSP='off',BufferSize=50000)
SETTINGS=dict(Solver='ode23t',RelTol='1e-10',AbsTol='1e-12',MinStepSizeMsg='error',
              MaxConsecutiveMinStep='1',MinStep='auto',LoadInitialState='off',SaveOperatingPoint='off')


def check_callbacks(current, previous):
    if len(current)!=3 or len(previous)!=3: raise ValueError('Incomplete callbacks')
    for new, old in zip(current,previous):
        compared=deepcopy(new)
        if compared.pop('AutoScaleAbsTol',None)!='on' or compared!=old:
            raise ValueError('Changed configuration beyond added read-only snapshot')


def check_profiler(p):
    if (p['capture_pass'] or p['api_returned'] or p['data_file_exists']
            or p['science_gate_pass'] or p['full_jacobian_analyzed'] or p['production_recovery_allowed']
            or p['requested_options']!=OPTIONS or p['expected_settings']!=SETTINGS
            or p['settings_after']!=SETTINGS
            or p['AutoScaleAbsTol_before']!='on' or p['AutoScaleAbsTol_after']!='on'
            or '1.584348158130581e-301' not in p['error_message']
            or '\u5947\u5f02\u8fed\u4ee3\u77e9\u9635' not in p['error_report']):
        raise ValueError('Unexpected profiler outcome; diagnose before changing audit')


def audit(repo):
    root=repo/'outputs_storage_audit'/ROOT
    path=root/'compiled_states_inspection.json';r=read(path)
    prior_path=repo/'outputs_storage_audit/hybrid_held_split_failure_audit_20260910/held_split_failure_audit.json'
    if sha256(prior_path)!=PRIOR_SHA: raise ValueError('Previous failure evidence changed')
    prior=read(prior_path)
    for relative,expected in prior['input_sha256'].items():
        if sha256(repo/relative)!=expected: raise ValueError('Prior reference or C200 changed')
    bp=repo/'outputs_storage_audit/specific_inventory_hybrid_held_split_tolerances_20260910/compiled_states_inspection.json';b=read(bp)
    if (r['inspector_commit']!=PRODUCER or not r['held_profiler_requested'] or not r['simulation_run']
            or not r['held_split_tolerances'] or r['profiled_failure_sha256']!=PRIOR_SHA
            or r['stage']!='profiler_capture_complete' or r['algebraic_structure']['loop_count']!=0
            or any(r[k] for k in ('inspection_pass','profiler_capture_pass','initialization_only',
                'c200_state_imported','failed_terminal_state_imported','production_recovery_allowed','checkpoint_saved'))):
        raise ValueError('Wrong profiler experiment')
    check_profiler(r['profiler']);check_callbacks(r['runtime_callbacks'],b['runtime_callbacks'])
    if (root/'solver_profile.mat').exists() or (root/'observations.mat').exists():
        raise ValueError('Unexpected data appeared after rejected capture')
    for k in ('source_native_sha256','global_tolerances_after','global_solver_configuration',
              'consistency_settings_after','runtime_solver_options_after','passive_ps_observer_contract',
              'ps_initial_actuation_contract','held_interval_contract','model_nominal_value_table'):
        if r[k]!=b[k]: raise ValueError('Undeclared configuration difference: '+k)
    prepath=root/'pre_simulation_inspection.json';pre=read(prepath)
    if pre['simulation_run'] or pre['stage']!='ready_for_held_error_control_simulation':
        raise ValueError('Wrong pre-simulation snapshot')
    for k in ('source_native_sha256','global_tolerances_after','global_solver_configuration',
              'held_profiler_requested','profiled_failure_sha256','consistency_settings_after'):
        if pre[k]!=r[k]: raise ValueError('Pre/post settings differ')
    files=[path,prepath,prior_path,bp,root/'matlab_diary.log']
    stored=[p for p in root.rglob('*') if p.is_file()]
    return dict(evidence_audit_pass=True,profiler_capture_pass=False,science_gate_pass=False,
        actual_AutoScaleAbsTol='on',actual_callbacks=3,compiled_algebraic_loops=0,
        requested_options=OPTIONS,profiler_wall_seconds=r['profiler']['wall_seconds'],
        profiler_API_returned=False,profiler_data_file_exists=False,
        initial_coordinate_audit_performed_this_run=False,full_compiled_iteration_matrix_verified=False,
        complete_held_interval=False,production_recovery_allowed=False,full_system_first_law_verified=False,
        table4_reproduction_claim=False,unique_root_cause_verified=False,
        preserved_error_report=r['profiler']['error_report'],package_file_count=len(stored),
        package_bytes=sum(p.stat().st_size for p in stored),
        input_sha256={str(p.relative_to(repo)):sha256(p) for p in files})


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output-root',type=Path,required=True);args=parser.parse_args()
    if args.output_root.exists(): raise FileExistsError('Never overwrite evidence')
    result=audit(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'held_profiler_failure_audit.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('preserved_error_report','input_sha256')},indent=2))
