"""Audit version-specific profiler getters against independently exported physics."""
import argparse
import json
from pathlib import Path
import h5py
import numpy as np
from Audit_HeatDriveECC_ColdPassivePSObserver import read, sha256, CHAMBERS, BUFFERS
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_SegmentedEvidence import text_field


PROFILE_SHA='C9C6FFA506031B9EC1FE836D4469B7A5F29BBD04C132D95E7BD89EF58163FB2A'
PHYSICS_AUDIT_SHA='C1203B39A510BFD22E3B1823CAB774EA1308668E9A215F3CB9046533678128E8'


def vector(value):
    a=np.atleast_1d(np.asarray(value,dtype=float))
    if a.ndim!=1 or not np.isfinite(a).all():raise ValueError('Expected finite scalar history')
    return a


def history(state):
    t=vector(state['time']);v=vector(state['value'])
    if not t.size or t.shape!=v.shape or np.any(np.diff(t)<0) or t[0]<0 or t[-1]>.04:
        raise ValueError('Malformed profiler state history')
    return t,v


def matching_times(t,reference):
    indices=[]
    for time in t:
        match=np.flatnonzero(np.abs(reference-time)<=1e-14)
        if len(match)!=1:raise ValueError('Missing/ambiguous physical sample; never silently interpolate')
        indices.append(int(match[0]))
    return indices


def state_identity(r,index):
    if int(index)!=index or not 1<=index<=len(r['states']):raise ValueError('Invalid profiler state index')
    index=int(index);state=r['states'][index-1];stat=r['state_stats'][index-1]
    block_index=stat['blockIdx']
    if int(block_index)!=block_index or not 1<=block_index<=len(r['block_stats']):raise ValueError('Invalid block index')
    block=r['block_stats'][int(block_index)-1]
    if (state['name']!=stat['stateName'] or state['block']!=[block['blockName']]
            or index not in np.atleast_1d(block['stateIdx'])):
        raise ValueError('Profiler state/block cross-reference failed')
    return state


def inaccurate_rows(flat,states):
    # MATLAB jsonencode flattens a cell matrix in column-major order.
    if not flat or len(flat)%4:raise ValueError('Expected four-column diagnostic cell table')
    rows=np.asarray(flat,dtype=object).reshape((4,-1)).T.tolist()
    by_name={s['name']:s for s in states}
    for lo,hi,tolerance,name in rows:
        if name not in by_name or not np.isfinite([lo,hi,tolerance]).all() or tolerance<=0:
            raise ValueError('Invalid below-absolute-tolerance row')
        state=by_name[name]
        if lo!=state['xmin'] or hi!=state['xmax']:
            raise ValueError('Below-absolute-tolerance extrema differ from state history')
    return rows


def reset_interval_defects(t,inventory,flux,resets):
    t=vector(t);inventory=vector(inventory);flux=vector(flux);resets=vector(resets)
    if t.shape!=inventory.shape or t.shape!=flux.shape or np.any(np.diff(t)<=0):
        raise ValueError('Unaligned inventory/flux grid')
    defect=np.diff(inventory)-.5*(flux[1:]+flux[:-1])*np.diff(t)
    after=np.array([np.any(abs(resets-time)<=1e-14) for time in t[:-1]])
    total=float(np.sum(abs(defect)));contribution=float(np.sum(abs(defect[after])))
    return dict(interval_count=len(defect),intervals_starting_at_reset=int(after.sum()),
        absolute_defect_sum=total,absolute_defect_sum_after_reset=contribution,
        fraction_of_absolute_defect_after_reset=contribution/total if total else None,
        signed_defect_sum=float(defect.sum()),
        max_abs_defect_after_reset=float(np.max(abs(defect[after]))) if after.any() else None,
        max_abs_defect_other_intervals=float(np.max(abs(defect[~after]))) if (~after).any() else None,
        interval_defects=defect.tolist(),reset_start_mask=after.tolist(),
        association_only_not_causal_proof=True)


def audit(repo):
    root=repo/'outputs_storage_audit'
    raw=root/'hybrid_held_profiler_diagnostics_20260910/profiler_diagnostics.json';r=read(raw)
    prior_path=root/'hybrid_held_profiler_sdi_audit_20260910/profiler_sdi_audit.json';prior=read(prior_path)
    if sha256(prior_path)!=PHYSICS_AUDIT_SHA:raise ValueError('Qualified physics audit changed')
    for path,digest in prior['input_sha256'].items():
        if sha256(repo/path)!=digest:raise ValueError('Qualified physical source changed')
    for dependency in r['adapter_dependencies']:
        if sha256(Path(dependency['file']))!=dependency['sha256']:raise ValueError('MATLAB internal implementation changed')
    exporter=repo/'verification/Export_HeatDriveECC_ProfilerDiagnosticsR2025b.m'
    if sha256(exporter)!=r['extractor_sha256']:raise ValueError('Extractor changed after evidence export')
    if (r['adapter_release']!='2025b' or r['source_sha256']!=PROFILE_SHA
            or not r['source_unchanged'] or not r['sdi_run_ids_unchanged']
            or any(r[k] for k in ('simulation_run','model_loaded','production_recovery_allowed',
                'all_model_state_coverage_verified','actual_error_weights_verified','full_iteration_matrices_analyzed'))):
        raise ValueError('Wrong read-only diagnostic scope')
    if len(r['states'])!=827 or r['state_count']!=827 or len(r['state_stats'])!=827:
        raise ValueError('Profiler state coverage changed')
    coverage=[]
    for index in range(1,828):
        state=state_identity(r,index);t,v=history(state)
        coverage.append(dict(index=index,name=state['name'],sample_count=len(t),start_s=float(t[0]),
            end_s=float(t[-1]),duplicate_time_count=int(np.count_nonzero(np.diff(t)==0))))
        if v.min()!=state['xmin'] or v.max()!=state['xmax']:raise ValueError('State extrema mismatch')
    j=r['jacobian'];updates=vector(j['update_times_s']);analysis=vector(j['analysis_times_s'])
    cond=vector(j['reported_condition_numbers']);stiff=vector(j['reported_stiffness'])
    table=np.asarray(j['limiting_state_table'],dtype=float)
    if (len(updates)!=40 or len(analysis)!=36 or table.shape!=(36,2) or cond.shape!=analysis.shape
            or stiff.shape!=analysis.shape or not np.array_equal(table[:,0],analysis)
            or np.any(cond<=0) or np.any(stiff<=0) or len(set(updates))!=40 or len(set(analysis))!=36):
        raise ValueError('Incomplete Jacobian analysis metadata')
    locations=matching_times(analysis,updates)
    if not np.array_equal(updates,np.asarray(r['reset_times_s'])):raise ValueError('Event grids differ')
    limiters=[state_identity(r,index) for index in table[:,1]]
    names=set(s['name'] for s in limiters)
    if len(names)!=1 or j['ranked_table']!=[36,limiters[0]['name']]:raise ValueError('Limiting-state ranking mismatch')
    resets=[]
    for item in r['reset_block_stats']:
        times=vector(item['allResets']['eventTime'])
        if not times.size:continue
        idx=item['blockIdx'];block=r['block_stats'][idx-1]['blockName']
        discrete=vector(item['discreteDerivative']['eventTime'])
        if not np.array_equal(times,discrete):raise ValueError('Unexpected reset attribution')
        matching_times(times,updates)
        resets.append(dict(block_path=block,event_count=len(times),event_times_s=times.tolist(),
                           reported_category='discreteDerivative'))
    profile_root=root/'specific_inventory_hybrid_held_sdi_profiler_20260910'
    manifest=read(profile_root/'compiled_states_inspection.json')
    nominals=manifest['runtime_callbacks'][0]['chamber_nominals']
    candidates=[s for s in r['states'] if s['block'][0].split('/')[-1] in CHAMBERS|BUFFERS
                and s['name'].split('.')[-1] in ('stored_mass','stored_energy')]
    if len(candidates)!=12:raise ValueError('Expected twelve explicit inventory states')
    matches=[];reset_defects=[]
    with h5py.File(profile_root/'sdi_scalar_observations.mat') as f:
        signals={}
        for ref in f['signals'][:].flat:
            row=f[ref];key=(text_field(row['full_block_path']),text_field(row['name']))
            if key in signals:raise ValueError('Ambiguous physical signal identity')
            signals[key]=row
        for state in candidates+[limiters[0]]:
            key=(state['block'][0],state['name']);physical=signals[key]
            t,v=history(state);pt=physical['time_s'][:].ravel();idx=matching_times(t,pt)
            variable=state['name'].split('.')[-1];component=key[0].split('/')[-1]
            if component in CHAMBERS:
                nominal=[n for n in nominals if n['block_path']==key[0] and n['state_name']==variable]
                if len(nominal)!=1 or nominal[0]['specify']!='on':raise ValueError('Missing declared chamber scaling')
                scale=float(nominal[0]['value']);unit=nominal[0]['unit'];basis='recorded_explicit_nominal'
            else:
                scale=1.;unit=text_field(physical['unit']);basis='numerical_identity_in_exported_physical_unit'
            pv=scalar_series(physical,unit)[idx];expected=pv/scale
            error=float(np.max(np.abs(v-expected)));allowance=32*np.finfo(float).eps*np.maximum(1,np.abs(expected))
            if not np.all(abs(v-expected)<=allowance):raise ValueError('Profiler/physical state representation differs: '+state['name'])
            matches.append(dict(name=state['name'],block_path=key[0],unit=unit,scale=scale,scale_basis=basis,
                sample_count=len(t),start_s=float(t[0]),end_s=float(t[-1]),maximum_representation_error=error,
                tolerance='32*eps*max(1,abs(physical/scale)); representation only, not scientific gate'))
        for name in sorted(CHAMBERS|BUFFERS):
            block=r['model']+'/'+name;prefix=r['model']+'.'+name
            get=lambda var,unit:scalar_series(signals[block,prefix+'.'+var],unit)
            t=signals[block,prefix+'.stored_mass']['time_s'][:].ravel()
            mdot=get('mdot_A','kg/s');power=get('Phi_A','W')+get('Q_H','W')
            if name in CHAMBERS:mdot+=get('mdot_B','kg/s');power+=get('Phi_B','W')
            reset_defects.append(dict(block_path=block,
                mass=reset_interval_defects(t,get('stored_mass','kg'),mdot,updates),
                energy=reset_interval_defects(t,get('stored_energy','J'),power,updates)))
    incorrect=inaccurate_rows(r['inaccurate_state_table'],r['states'])
    return dict(evidence_audit_pass=True,simulation_run=False,profiler_state_record_count=827,
        state_coverage=coverage,physical_state_representation_checks=matches,reset_attribution=resets,
        interval_defects_by_reset=reset_defects,
        jacobian_update_count=40,jacobian_analysis_count=36,
        updates_without_analysis_s=[float(t) for k,t in enumerate(updates) if k not in locations],
        limiting_state=limiters[0]['name'],limiting_block_path=limiters[0]['block'][0],
        reported_condition_range=[float(cond.min()),float(cond.max())],
        reported_stiffness_range=[float(stiff.min()),float(stiff.max())],
        below_absolute_tolerance_table_rows=len(incorrect),
        unique_singularity_root_cause_proven=False,full_iteration_matrices_analyzed=False,
        actual_error_weights_verified=False,all_model_state_coverage_verified=False,
        local_balance_gate=prior['local_balance_gate'],passing_local_balances=prior['passing_local_balances'],
        production_recovery_allowed=False,table4_reproduction_claim=False,
        input_sha256={str(p.relative_to(repo)):sha256(p) for p in (raw,prior_path,exporter)})


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output-root',type=Path,required=True);args=parser.parse_args()
    if args.output_root.exists():raise FileExistsError('Never overwrite audit evidence')
    r=audit(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'profiler_diagnostics_audit.json').write_text(json.dumps(r,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in r.items() if k not in ('state_coverage','input_sha256','reset_attribution','physical_state_representation_checks','interval_defects_by_reset')},indent=2))
