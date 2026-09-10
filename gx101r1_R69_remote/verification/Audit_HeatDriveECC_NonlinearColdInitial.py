"""Audit physical t=0 targets and coordinate scaling, not a finite-window pass."""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import re
import h5py
import numpy as np
from Audit_HeatDriveECC_ColdPassivePSObserver import read,sha256,CHAMBERS,BUFFERS
from Audit_HeatDriveECC_ColdCoordinateSmoke import compare_initial,scalar_series
from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_NonlinearMassProbe import reverse_source


def unchanged_runtime_context(actual,reference):
    expected=deepcopy(reference);current=deepcopy(actual)
    expected['AutoScaleAbsTol']='on'
    expected['pressure_converter']['StopTime']='0'
    expected['pressure_converter']['derivative_source']='heatdrive_ecc_coupled_se21/ColdInitialPressureDerivativeOnly'
    expected.pop('held_interval_contract',None)
    for row in (expected,current):
        for key in ('targets','buffer_nominals','chamber_nominals'):row.pop(key)
    if current!=expected:raise ValueError('Controller, solver, or noninventory runtime context changed')


def target_translation(physical,runtime,components):
    if len(physical)!=204 or len(runtime)!=204 or len(components)!=6:raise ValueError('Incomplete target mapping')
    runtime_by_path={t['path']:t for t in runtime};by_block={c['block_path']:c for c in components}
    if len(runtime_by_path)!=204 or len(by_block)!=6 or len({t['path'] for t in physical})!=204:
        raise ValueError('Duplicate target or component')
    translated=0;expected_paths=set()
    for t in physical:
        expected=deepcopy(t)
        if t['state_name'] in ('stored_mass','stored_energy'):
            if t['block_path'] not in by_block or t['priority']!='High':raise ValueError('Invalid physical inventory target')
            c=by_block[t['block_path']];mass=t['state_name']=='stored_mass'
            name='mass_coordinate' if mass else 'energy_delta';unit='1' if mass else 'J'
            origin=c['mass_reference_kg' if mass else 'energy_reference_J']
            if t['value']!=origin or t['unit']!=('kg' if mass else 'J'):raise ValueError('Coordinate origin changes physical target')
            expected.update(path=t['path'].rsplit('/',1)[0]+'/'+name,state_name=name,unit=unit,value=0)
            translated+=1
        expected_paths.add(expected['path'])
        if runtime_by_path.get(expected['path'])!=expected:raise ValueError('Runtime target differs from exact physical translation')
    if translated!=12 or expected_paths!=set(runtime_by_path):raise ValueError('Incomplete inventory translation')
    for c in components:
        if c['kind'] not in ('buffer','chamber'):raise ValueError('Unknown inventory kind')
        scale=c['mass_scale_kg'];mass_nom=c['mass_nominal_kg'];energy_nom=c['energy_nominal_J'];z_nom=c['mass_coordinate_nominal']
        if not np.isfinite([scale,mass_nom,energy_nom,z_nom]).all() or min(scale,mass_nom,energy_nom,z_nom)<=0:
            raise ValueError('Invalid coordinate scale')
        if scale!=c['mass_reference_kg'] or abs(scale*z_nom-mass_nom)>5e-16*mass_nom:
            raise ValueError('Initial physical nominal scale changed')
        if c['kind']=='buffer' and (mass_nom!=1 or energy_nom!=1):raise ValueError('Buffer original nominal changed')
        if c['kind']=='chamber' and (mass_nom!=scale or energy_nom!=c['energy_reference_J']):raise ValueError('Chamber original nominal changed')
    return dict(translated=translated,unchanged=204-translated,initial_nominal_jacobian_match=True,
                full_solver_error_weights_verified=False)


def build(repo):
    root=repo/'outputs_storage_audit';folder=root/'nonlinear_inventory_cold_initial_20260910'
    path=folder/'compiled_states_inspection.json';r=read(path);contract=r['nonlinear_inventory_contract']
    if (not r['inspection_pass'] or r['stage']!='complete' or r['simulation_error_message'] or not r['initialization_only']
            or r['diagnostic_stop_time_s']!=0 or not r['nonlinear_inventory_requested'] or r['held_interval_requested']
            or not r['simulation_run'] or any(r[k] for k in ('production_recovery_allowed','checkpoint_saved','c200_state_imported','failed_terminal_state_imported'))):
        raise ValueError('Unexpected nonlinear cold experiment scope')
    if r['inspector_commit']!='e132f0bc58a201e2264fb0cc0ab08f9daff7d4ae':raise ValueError('Unknown initialization producer')
    if (r['global_solver_configuration']!={'Solver':'ode23t','SolverType':'Variable-step','MaxStep':'0.00025000000000000001','InitialStep':'auto'}
            or r['global_tolerances_after']!={'RelTol':'1e-6','AbsTol':'1e-8'}):
        raise ValueError('Wrong initial solver controls')
    qualification=root/'nonlinear_mass_qualification_package_20260910/nonlinear_mass_probe_audit.json'
    if sha256(qualification)!=contract['qualification_sha256'] or contract['qualification_sha256']!='137768091C382BEF495FB9A948F8350800819C25342F2D7AAC6489985BC5EC1C':
        raise ValueError('Fixture prerequisite changed')
    expected_path=root/'conservative_buffer_coupled_cycle_20260909/conservative/public_inventory_targets.json'
    if sha256(expected_path)!='372E3A69B621943EA0696964F034A3E303AE3FDA66B29DB0A402EADC967258B2':raise ValueError('Physical target source changed')
    expected=read(expected_path)['targets'];physical=contract['physical_targets'];runtime=contract['runtime_targets'];components=contract['components']
    if {t['path']:t for t in expected}!={t['path']:t for t in physical}:raise ValueError('Original 204 targets changed')
    names={c['block_path'] for c in components}
    if names!={'heatdrive_ecc_coupled_se21/'+name for name in CHAMBERS|BUFFERS}:raise ValueError('Wrong six physical components')
    mapping=target_translation(physical,runtime,components)
    if (not contract['typed_nets_preserved'] or len(contract['net_signatures'])!=2
            or contract['private_state_imported'] or contract['production_recovery_allowed'] or contract['source_time_s']!=0):
        raise ValueError('Connection or cold-only contract differs')
    inputs=[path,expected_path,qualification,folder/'pre_simulation_inspection.json',folder/'matlab_diary.log',
            folder/'compiled_initial_state_dataset.mat']
    reference_path=root/'specific_inventory_hybrid_held_ode23t_after_restart_20260910/compiled_states_inspection.json'
    if sha256(reference_path)!='32E1A6091A04A3150CBF6E23C101C65429E0D4B98181321A3EFA5ED29CFF352F':
        raise ValueError('Qualified held baseline changed')
    reference=read(reference_path);inputs.append(reference_path)
    for v in contract['variants']:
        original=Path(v['source']);generated=Path(v['generated_source']);library=Path(v['library_path']);inputs.extend([original,generated,library])
        if (sha256(original)!=v['source_sha256'] or sha256(generated)!=v['generated_sha256']
                or sha256(library)!=v['library_sha256']):raise ValueError('Component or library changed')
        reverse_source(generated.read_text(),original.read_text(),v['kind'],True)
    expected_runtime={t['path']:{k:t[k] for k in ('path','unit','value','priority')} for t in runtime}
    if [c['stage'] for c in r['runtime_callbacks']]!=['InitFcn','StartFcn','StopFcn']:raise ValueError('Missing runtime callback')
    expected_nominals={}
    for c in components:
        expected_nominals[c['block_path'],'mass_coordinate']=(c['mass_coordinate_nominal'],'1')
        expected_nominals[c['block_path'],'energy_delta']=(c['energy_nominal_J'],'J')
    for c,prior in zip(r['runtime_callbacks'],reference['runtime_callbacks']):
        unchanged_runtime_context(c,prior)
        if (len(c['targets'])!=204 or {t['path']:t for t in c['targets']}!=expected_runtime or c['has_private_data']
                or c['LoadInitialState']!='off' or c['AutoScaleAbsTol']!='on'
                or c['global_solver_configuration']!=r['global_solver_configuration']):raise ValueError('Runtime target or solver changed')
        rows=c['buffer_nominals']+c['chamber_nominals']
        if len(rows)!=12 or len({(n['block_path'],n['state_name']) for n in rows})!=12:raise ValueError('Incomplete nominal capture')
        for n in rows:
            expected_value,unit=expected_nominals[n['block_path'],n['state_name']]
            if n['specify']!='on' or n['unit']!=unit or float(n['value'])!=expected_value:raise ValueError('Runtime nominal changed')
    if [p['phase'] for p in r['cached_phase_targets']]!=['Prestart','Start'] or r['cached_extraction_added_callbacks']:
        raise ValueError('Cached phases not independently captured')
    for phase in r['cached_phase_targets']:
        if len(phase['public_targets'])!=204:raise ValueError('Incomplete cached target coverage')
        for t in phase['public_targets']:
            e=expected_runtime[t['path']]
            if t['unit']!=e['unit'] or t['priority']!=e['priority'] or not compare_initial(t['value'],e['value'])['within_strict_comparison']:
                raise ValueError('Cached coordinate changed')
    raw=folder/'observations.mat';inputs.append(raw)
    if sha256(raw)!=r['observations_sha256']:raise ValueError('Observation hash differs')
    base=root/'specific_inventory_hybrid_held_ode23t_after_restart_20260910/observations.mat';inputs.append(base)
    if sha256(base)!='DBEC8A09EB8534692C4C680536877B67E555F9D15DB1E1791BFC2B2CBEA31210':raise ValueError('Base inventory changed')
    comparisons=[];state_matches=[]
    with h5py.File(raw) as f,h5py.File(base) as b:
        native=named_rows(f,f['native']);sources=named_rows(f,f['source_traces']);old=named_rows(b,b['native'])
        expected_new={(name,var) for name in names for var in ('mass_delta','energy_delta','mass_coordinate')}
        if set(native)!=set(old)|expected_new or len(native)!=1276 or len(sources)!=162:
            raise ValueError('Physical inventory coverage differs')
        if set(sources)!=set(named_rows(b,b['source_traces'])):raise ValueError('Boundary source coverage differs')
        for row in list(native.values())+list(sources.values()):
            if not np.array_equal(row['time_s'][()].ravel(),[0.]) or row['values'].size!=1 or not np.isfinite(row['values'][()]).all():
                raise ValueError('Not a finite t=0-only dataset')
        reported={x['path']:x for x in r['initial_coordinates']}
        if len(reported)!=204:raise ValueError('Incomplete initial coordinate report')
        for t in physical:
            actual=float(scalar_series(native[t['block_path'],t['state_name']],t['unit'])[0]);rr=reported[t['path']]
            if (rr['expected']!=t['value'] or rr['actual']!=actual or rr['priority']!=t['priority']
                    or rr['unit']!=t['unit'] or rr['source_time_s']!=0):raise ValueError('MAT/JSON initial coordinate mismatch')
            comparisons.append(dict(path=t['path'],priority=t['priority'],unit=t['unit'],**compare_initial(actual,t['value'])))
        saved=r['nonlinear_coordinate_states']
        if len(saved)!=12:raise ValueError('Not all six mass/energy coordinates are saved')
        for c in components:
            for name,unit,nominal in [('mass_coordinate','1',c['mass_coordinate_nominal']),('energy_delta','J',c['energy_nominal_J'])]:
                full=c['block_path'].replace('/','.')+'.'+name;matches=[s for s in saved if s['name']==full]
                if len(matches)!=1 or matches[0]['label']!='CSTATE':raise ValueError('Missing saved coordinate identity')
                state=matches[0];actual=float(scalar_series(native[c['block_path'],name],unit)[0]);data=float(state['data'])
                if state['time_s']!=0 or not np.isclose(data*nominal,actual,rtol=1e-12,atol=1e-300):raise ValueError('Saved normalized coordinate differs from log')
                state_matches.append(dict(block_path=c['block_path'],name=name,physical_value=actual,
                    saved_normalized_value=data,nominal=nominal,numeric_identity_verified=True))
    frozen_path=repo/'verification/c200_mainline_freeze_contract.json';frozen=read(frozen_path);inputs.append(frozen_path)
    for kind in ('result','checkpoint'):
        p=repo/frozen[kind+'_relative_path'];inputs.append(p)
        if sha256(p)!=frozen[kind+'_sha256']:raise ValueError('Frozen C200 changed')
    passed=all(c['within_strict_comparison'] for c in comparisons)
    files=[]
    for directory in ('nonlinear_inventory_cold_initial_20260910','nonlinear_cold_initial_audit_20260910',
                      'nonlinear_cold_initial_strict_audit_20260910'):
        for p in sorted((root/directory).rglob('*')):
            if p.is_file():files.append(dict(path=str(p.relative_to(repo)),bytes=p.stat().st_size,sha256=sha256(p)))
    index=repo.parent/'项目文档/研究笔记/2026-09-03_Qian本地文献精确定位与模型映射.md'
    pdfs=sorted(set(re.findall(r'C:\\[^`\r\n]+\.pdf',index.read_text(encoding='utf-8'))))
    if len(pdfs)!=10:raise ValueError('Literature location coverage changed')
    references=[];literature_root=(repo.parents[1]/'冷凝文献').resolve()
    for name in pdfs:
        p=Path(name).resolve();p.relative_to(literature_root)
        references.append(dict(path=str(p),bytes=p.stat().st_size,sha256=sha256(p)))
    return dict(evidence_audit_pass=True,strict_initial_coordinate_gate=passed,
        primary_count=sum(c['priority']=='High' for c in comparisons),auxiliary_count=sum(c['priority']=='Low' for c in comparisons),
        strict_matching_count=sum(c['within_strict_comparison'] for c in comparisons),comparisons=comparisons,
        target_translation=mapping,coordinate_state_matches=state_matches,native_leaf_count=1276,boundary_leaf_count=162,
        compiled_algebraic_loops=r['algebraic_structure']['loop_count'],typed_nets_preserved=True,
        simulation_call_wall_seconds=r['simulation_wall_seconds'],source_time_s=0,stop_time_s=0,
        bounded_held_trial_eligible=passed and r['algebraic_structure']['loop_count']==0,
        finite_window_conservation_audited=False,periodic_state_audited=False,production_recovery_allowed=False,
        table4_reproduction_claim=False,full_solver_error_weights_verified=False,
        files=files,evidence_file_count=len(files),evidence_bytes=sum(p['bytes'] for p in files),
        deleted_files=0,large_raw_or_checkpoint_duplicated=False,
        reference_locations=references,reference_index=dict(path=str(index),sha256=sha256(index),
            scope='File existence and hashes checked; page/figure mappings inherited, not re-reviewed in this run.'),
        input_sha256={str(p.relative_to(repo)):sha256(p) for p in inputs})


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output-root',type=Path,required=True);args=parser.parse_args()
    if args.output_root.exists():raise FileExistsError('Never overwrite initial evidence')
    r=build(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'nonlinear_cold_initial_audit.json').write_text(json.dumps(r,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in r.items() if k not in ('comparisons','coordinate_state_matches','input_sha256','files','reference_locations')},indent=2))
