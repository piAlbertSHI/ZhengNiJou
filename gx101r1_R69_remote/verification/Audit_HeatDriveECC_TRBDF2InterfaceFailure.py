"""Preserve the TR-BDF2 derivative-contract failure; no trajectory/initial-state pass."""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import re
import h5py
from Audit_HeatDriveECC_ColdPassivePSObserver import read,sha256
from Audit_HeatDriveECC_SegmentedEvidence import text_field


MODEL='heatdrive_ecc_coupled_se21'
PRODUCER='09fc269dbcab0f49160566a72e2e3b2ffcb556ec'


def derivative_requirements(message):
    marker='\u4ee5\u4e0b Simulink-PS Converter \u6a21\u5757\u5177\u6709\u8fde\u7eed\u8f93\u5165'
    if message.count(marker)!=1:raise ValueError('Unexpected derivative error format')
    pieces=message.split(marker);rows=[]
    pattern=r"\.\.\.'([^']+)' \(\u9700\u8981 (\d+) \u4e2a\uff0c\u63d0\u4f9b\u4e86 (\d+) \u4e2a\)"
    for text,kind in zip(pieces,('piecewise_constant','continuous')):
        for path,required,provided in re.findall(pattern,text):
            if not path.startswith(MODEL+'/') or int(required)<=int(provided):raise ValueError('Invalid derivative requirement')
            rows.append(dict(block_path=path,input_kind=kind,required_derivatives=int(required),provided_derivatives=int(provided)))
    if len({r['block_path'] for r in rows})!=len(rows):raise ValueError('Duplicate converter error')
    return rows


def build(repo):
    root=repo/'outputs_storage_audit';folder=root/'specific_inventory_hybrid_held_ode23tb_20260910'
    path=folder/'compiled_states_inspection.json';r=read(path);prepath=folder/'pre_simulation_inspection.json';pre=read(prepath)
    priorpath=root/'hybrid_held_ode23t_audit_20260910/held_interval_audit.json';prior=read(priorpath)
    if sha256(priorpath)!='BB1136088658C84AD15F6A369FF087C617D2F5349F1EE00B0FAEECCFED0F1C21':raise ValueError('Prior audit changed')
    for relative,digest in prior['input_sha256'].items():
        if sha256(repo/relative)!=digest:raise ValueError('Prior or frozen evidence changed')
    base=read(root/'specific_inventory_hybrid_held_ode23t_after_restart_20260910/compiled_states_inspection.json')
    if (r['inspector_commit']!=PRODUCER or r['stage']!='export_onset_observations' or not r['simulation_run']
            or r['held_solver_method']!='ode23tb' or r['simulation_error_message']!=r['error_message']
            or any(r[k] for k in ('inspection_pass','held_profiler_requested','held_split_tolerances','held_robust_reset_requested',
                'production_recovery_allowed','checkpoint_saved','c200_state_imported','failed_terminal_state_imported'))):
        raise ValueError('Undeclared failed experiment')
    expected=deepcopy(base['global_solver_configuration']);expected['Solver']='ode23tb'
    for item in (pre,r):
        if item['global_solver_configuration']!=expected or item['global_tolerances_after']!=base['global_tolerances_after']:
            raise ValueError('Other solver/tolerance changes')
    for key in ('consistency_settings_after','runtime_solver_options_after','solver_iteration_options',
                'output_sampling_settings','held_interval_contract','source_native_sha256'):
        if r[key]!=base[key]:raise ValueError('Other assembly change: '+key)
    if pre['simulation_run'] or len(r['runtime_callbacks'])!=2 or 'initial_coordinates' in r:
        raise ValueError('Unexpected runtime/initial coordinate evidence')
    for current,index in zip(r['runtime_callbacks'],(0,2)):
        expected_cb=deepcopy(base['runtime_callbacks'][index]);expected_cb['AutoScaleAbsTol']='on'
        expected_cb['global_solver_configuration']['Solver']='ode23tb'
        if current!=expected_cb:raise ValueError('Runtime callback differs beyond solver selection')
    rows=derivative_requirements(r['error_message'])
    constant=[x for x in rows if x['input_kind']=='piecewise_constant'];continuous=[x for x in rows if x['input_kind']=='continuous']
    expected_heat={f'{MODEL}/{side}/Subsystem2/ConstitutiveHeatPS_{k:02d}' for side in ('SMA','SE') for k in range(1,22)}
    if len(rows)!=60 or {x['block_path'] for x in constant}!=expected_heat or len(continuous)!=18:
        raise ValueError('Converter failure coverage differs')
    for row in rows:
        pair=(2,1) if row['block_path']==MODEL+'/SMAPressurePI_SimulinkPS' else (1,0)
        if (row['required_derivatives'],row['provided_derivatives'])!=pair:raise ValueError('Derivative requirement changed')
    raw=folder/'failed_public_observations.mat'
    with h5py.File(raw) as f:
        record=f['record']
        if any(float(record[k][0,0]) for k in ('signals_count','native_leaf_count','valid_simulation','production_recovery_allowed')):
            raise ValueError('Unexpected valid trajectory in failed export')
        if text_field(record['error_message'])!=r['error_message']:raise ValueError('Failed export error changed')
    for name in ('observations.mat','compiled_state_dataset.mat','final_operating_point.mat'):
        if (folder/name).exists():raise ValueError('Unexpected successful result or recovery state')
    analytic=root/'analytic_reset_probe_audit_20260910/analytic_reset_probe_audit.json'
    if sha256(analytic)!=r['analytic_reset_probe_sha256'] or sha256(analytic)!='848959AE2B7CE4D7D906949D7B12E63172FACA93B9B2EB6F51AADB6B2035E6B4':
        raise ValueError('Analytic prerequisite changed')
    return dict(evidence_audit_pass=True,failure_class='insufficient_Simulink_PS_input_derivatives',
        derivative_requirements=rows,piecewise_constant_converters=42,continuous_converters=18,
        exported_physical_signals=0,exported_native_leaves=0,actual_initial_coordinates_verified=False,
        finite_window_conservation_audited=False,compiled_algebraic_loops=r['algebraic_structure']['loop_count'],
        simulation_call_wall_seconds=r['simulation_wall_seconds'],production_recovery_allowed=False,
        table4_reproduction_claim=False,filter_or_derivative_repair_applied=False,
        input_sha256={str(p.relative_to(repo)):sha256(p) for p in (path,prepath,raw,priorpath,analytic,folder/'matlab_diary.log')})


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output-root',type=Path,required=True);args=parser.parse_args()
    if args.output_root.exists():raise FileExistsError('Never overwrite failure evidence')
    r=build(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'trbdf2_interface_failure_audit.json').write_text(json.dumps(r,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in r.items() if k not in ('derivative_requirements','input_sha256')},indent=2))
