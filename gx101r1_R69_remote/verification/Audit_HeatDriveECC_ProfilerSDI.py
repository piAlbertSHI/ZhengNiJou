"""Map exported SDI physics by full block identity and audit original balances."""
import argparse
import csv
import json
from pathlib import Path
import h5py
import numpy as np
from Audit_HeatDriveECC_ColdPassivePSObserver import read, sha256, CHAMBERS, BUFFERS, summarize_coordinates
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series, compare_initial
from Audit_HeatDriveECC_SegmentedEvidence import text_field
from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_HeldIntervalBalance import balance
from Audit_HeatDriveECC_HeldProfilerFailure import check_callbacks
from Audit_HeatDriveECC_HeldProfilerReference import check_summary

MODEL='heatdrive_ecc_coupled_se21'
PRODUCER='99be5bfe92920800b851de9bd2c1a893cddefa31'
BASE_SHA='BB1136088658C84AD15F6A369FF087C617D2F5349F1EE00B0FAEECCFED0F1C21'


def resolve_namespace(catalog, block_path, state_names):
    names={s['name'] for s in catalog if s['full_block_path']==block_path}
    first=sorted(state_names)[0];suffix='.'+first
    candidates={name[:-len(suffix)] for name in names if name.endswith(suffix)}
    qualified=[prefix for prefix in candidates if all(prefix+'.'+state in names for state in state_names)]
    if len(qualified)!=1:raise ValueError('Missing or ambiguous complete block namespace: '+block_path)
    return qualified[0]


def select_signal(catalog, block_path, state_name, namespace=None):
    selected=[s for s in catalog if s['full_block_path']==block_path and
              (s['name']==namespace+'.'+state_name if namespace is not None else s['name'].endswith('.'+state_name))]
    if len(selected)!=1:
        raise ValueError(f'Missing or ambiguous SDI identity: {block_path}::{state_name} ({len(selected)})')
    return selected[0]


def check_run_ownership(sdi):
    before=set(sdi['prior_run_ids']);after=set(sdi['after_run_ids'])
    if not before<=after or not sdi['prior_runs_preserved'] or not sdi['export_pass']:
        raise ValueError('Prior runs lost or export failed')
    owned=[]
    for run in sdi['runs']:
        if run['run_id'] in before or run['run_id'] not in after:
            raise ValueError('Run is not new to this profiler call')
        if not run['ownership_verified']:
            if run['exported']:raise ValueError('Foreign run exported')
            continue
        if (run['model']!=MODEL or not run['exported'] or run['unreadable_signals']
                or any(s['model'] not in ('',MODEL) for s in run['signal_metadata'])
                or run['signal_count']!=len(run['signal_metadata'])
                or run['scalar_count']+run['non_scalar_or_empty_count']!=run['signal_count']):
            raise ValueError('Invalid owned run coverage')
        owned.append(run)
    if len(owned)!=sdi['owned_run_count'] or sum(s['scalar_count'] for s in owned)!=sdi['scalar_signal_count']:
        raise ValueError('Scalar/run manifest mismatch')
    return owned


def check_history(row):
    t=row['time_s'][:].ravel();v=row['values'][:].ravel()
    if t.size<2 or t[0]!=0 or t[-1]!=.04 or np.any(np.diff(t)<=0) or t.shape!=v.shape or not np.isfinite([t,v]).all():
        raise ValueError('Incomplete finite physics history')
    return t


def kelvin_difference_alias(native, target, source, variable):
    if native!='deltaK':return False
    if target!='K' or source!='foundation.thermal.sources.controlled_heat_flow' or variable!='T':
        raise ValueError('Undeclared relative/absolute temperature alias')
    # Native component declares Conversion=relative and T == A.T - B.T in K.
    return True


def audit(repo):
    root=repo/'outputs_storage_audit/specific_inventory_hybrid_held_sdi_profiler_20260910'
    path=root/'compiled_states_inspection.json';r=read(path);p=r['profiler'];sdi=p['sdi']
    bp=repo/'outputs_storage_audit/hybrid_held_ode23t_audit_20260910/held_interval_audit.json';base=read(bp)
    if sha256(bp)!=BASE_SHA:raise ValueError('Qualified original trace audit changed')
    for relative,expected in base['input_sha256'].items():
        if sha256(repo/relative)!=expected:raise ValueError('Original trace or C200 changed')
    if (r['inspector_commit']!=PRODUCER or not r['held_profiler_requested'] or not r['profiler_capture_pass']
            or not p['api_returned'] or not p['capture_pass'] or r['stage']!='profiler_capture_complete'
            or any(r[k] for k in ('inspection_pass','held_split_tolerances','c200_state_imported',
                'failed_terminal_state_imported','production_recovery_allowed','checkpoint_saved'))):
        raise ValueError('Wrong SDI profiling experiment')
    reference_root=repo/'outputs_storage_audit/specific_inventory_hybrid_held_ode23t_after_restart_20260910'
    reference=read(reference_root/'compiled_states_inspection.json')
    check_callbacks(r['runtime_callbacks'],reference['runtime_callbacks']);check_summary(p['api_result']['summary'])
    for k in ('source_native_sha256','global_tolerances_after','global_solver_configuration','consistency_settings_after',
              'runtime_solver_options_after','passive_ps_observer_contract','ps_initial_actuation_contract','held_interval_contract'):
        if r[k]!=reference[k]:raise ValueError('Unexpected physical/numerical change: '+k)
    owned=check_run_ownership(sdi);files=[path,bp,root/'pre_simulation_inspection.json',root/'matlab_diary.log']
    for run in owned:
        archive=root/Path(run['archive_file']).name
        if sha256(archive)!=run['archive_sha256'] or archive.stat().st_size!=run['archive_bytes']:
            raise ValueError('SDI archive changed')
        files.append(archive)
    raw=root/'sdi_scalar_observations.mat';profile=root/'solver_profile.mat'
    if sha256(raw)!=sdi['scalar_sha256'] or sha256(profile)!=p['data_sha256']:
        raise ValueError('Scalar/profiler file changed')
    files.extend([raw,profile]);results=[];comparisons=[];matches=[]
    tp=repo/'outputs_storage_audit/conservative_buffer_coupled_cycle_20260909/conservative/public_inventory_targets.json'
    targets=read(tp)['targets'];files.append(tp)
    with h5py.File(raw) as f,h5py.File(reference_root/'observations.mat') as prior:
        catalog=[];seen=set()
        for ref in f['signals'][:].flat:
            row=f[ref];rid=text_field(row['run_id']);index=int(row['index'][0,0]);key=(rid,index)
            if key in seen:raise ValueError('Duplicate SDI scalar index')
            seen.add(key)
            meta=next(run['signal_metadata'][index-1] for run in owned if run['run_id']==rid)
            # Description is an opaque MATLAB string object, not a physical identity field.
            for field in ('name','model','full_block_path','unit'):
                if text_field(row[field])!=meta[field]:raise ValueError('Scalar metadata differs from manifest')
            catalog.append(dict(name=meta['name'],full_block_path=meta['full_block_path'],row=row,index=index))
        if len(catalog)!=sdi['scalar_signal_count']:raise ValueError('Scalar count differs')
        reference_sets={dataset:named_rows(prior,prior[dataset]) for dataset in ('native','source_traces')}
        source_types={text_field(prior[ref]['block_path']):text_field(prior[ref]['source_file'])
                      for ref in prior['boundary_metadata/blocks'][:].flat}
        needed={}
        for rows in reference_sets.values():
            for block,state in rows:needed.setdefault(block,set()).add(state)
        namespaces={block:resolve_namespace(catalog,block,states) for block,states in needed.items()}
        mapped={};grid=None
        for dataset,count in (('native',1258),('source_traces',162)):
            old=reference_sets[dataset]
            if len(old)!=count:raise ValueError('Reference coverage changed')
            for key,oldrow in old.items():
                selected=select_signal(catalog,*key,namespaces[key[0]]);row=selected['row'];t=check_history(row)
                if grid is None:grid=t
                elif not np.array_equal(grid,t):raise ValueError('Unaligned physical signals')
                oldt=oldrow['time_s'][:].ravel()
                if not np.array_equal(t,oldt):raise ValueError('Reference timing differs; do not interpolate silently')
                alias=kelvin_difference_alias(text_field(row['unit']),text_field(oldrow['unit']),
                    source_types.get(key[0],'') if dataset=='source_traces' else '',key[1])
                v=row['values'][:].ravel() if alias else scalar_series(row,text_field(oldrow['unit']))
                oldv=oldrow['values'][:].ravel()
                difference=float(np.max(abs(v-oldv)))
                matches.append(dict(dataset=dataset,block_path=key[0],state_name=key[1],sdi_index=selected['index'],
                    reference_unit=text_field(oldrow['unit']),relative_kelvin_alias=alias,
                    maximum_abs_difference_from_reference=difference))
                mapped[key]=row
        for target in targets:
            actual=scalar_series(mapped[target['block_path'],target['state_name']],target['unit'])[0]
            comparisons.append(dict(path=target['path'],priority=target['priority'],unit=target['unit'],
                                    **compare_initial(actual,target['value'])))
        for name in sorted(CHAMBERS|BUFFERS):
            path_=MODEL+'/'+name;get=lambda n,u:scalar_series(mapped[path_,n],u)
            mf=get('mdot_A','kg/s');power=get('Phi_A','W')+get('Q_H','W')
            if name in CHAMBERS:mf=mf+get('mdot_B','kg/s');power=power+get('Phi_B','W')
            results.append(dict(block_path=path_,**balance(grid,get('stored_mass','kg'),get('stored_energy','J'),mf,power)))
    initial=summarize_coordinates(comparisons)
    if len(targets)!=204 or not initial['strict_initial_coordinate_gate']:raise ValueError('Public cold initial values failed')
    passed=sum(x['mass_closure_pass'] and x['energy_closure_pass'] for x in results)
    return dict(evidence_audit_pass=True,sdi_owned_run_count=len(owned),sdi_scalar_signal_count=len(catalog),
        mapped_native_leaf_count=1258,mapped_source_leaf_count=162,physics_sample_count=len(grid),
        initial_coordinate_audit=initial,local_balances=results,passing_local_balances=passed,local_balance_gate=passed==6,
        all_reference_physics_arrays_exactly_equal=all(m['maximum_abs_difference_from_reference']==0 for m in matches),
        mapping=matches,resolved_block_namespaces=namespaces,profiler_summary=p['api_result']['summary'],
        annotation_string_payload_compared=False,
        all_model_states_verified=False,individual_jacobian_matrices_analyzed=False,
        full_system_first_law_verified=False,production_recovery_allowed=False,table4_reproduction_claim=False,
        input_sha256={str(x.relative_to(repo)):sha256(x) for x in files}),comparisons


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output-root',type=Path,required=True);args=parser.parse_args()
    if args.output_root.exists():raise FileExistsError('Never overwrite evidence')
    report,rows=audit(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'profiler_sdi_audit.json').write_text(json.dumps(report,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    with (args.output_root/'initial_coordinates.csv').open('x',newline='',encoding='utf-8') as stream:
        writer=csv.DictWriter(stream,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
    print(json.dumps({k:v for k,v in report.items() if k not in ('mapping','resolved_block_namespaces','local_balances','input_sha256')},indent=2))
