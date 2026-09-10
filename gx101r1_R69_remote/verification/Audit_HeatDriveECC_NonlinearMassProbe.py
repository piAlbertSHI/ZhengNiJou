"""Verify exact mass-coordinate substitution in bounded component fixtures."""
import argparse
import json
from pathlib import Path
import re
import h5py
import numpy as np
from Audit_HeatDriveECC_ColdPassivePSObserver import read,sha256
from Audit_HeatDriveECC_SegmentedEvidence import text_field
from Audit_HeatDriveECC_ShiftedInventoryProbe import balance


def reverse_source(candidate,original,kind,nonlinear):
    """Undo only the declared substitutions and require byte-equivalent normalized source."""
    def once(text,old,new=''):
        if text.count(old)!=1:raise ValueError('Unexpected component structure')
        return text.replace(old,new)
    table=[]
    for name in ('rho_I','u_I'):
        lines=re.findall(r'^    '+name+r' == tablelookup[^\n]*\n',original,re.M)
        if len(lines)!=1:raise ValueError('Table contract changed')
        table.append(lines[0])
    pattern=r'^variables\n(.*?)^end\n'
    ov=re.search(pattern,original,re.M|re.S);cv=re.search(pattern,candidate,re.M|re.S)
    retained=re.sub(r'^    (stored_mass|stored_energy|rho_I|u_I) = [^\n]*\n','',ov[1],flags=re.M)
    priority="{value = {0, '%s'}, priority = priority.high}" if kind=='buffer' else "{0, '%s'}"
    mass_decl=("    mass_coordinate = "+priority%'1'+"; % Invertible sinh mass coordinate\n") if nonlinear else (
        "    mass_delta = "+priority%'kg'+"; % Increment from constant origin\n")
    expected=mass_decl+"    energy_delta = "+priority%'J'+"; % Increment from constant origin\n"+retained
    if cv is None or cv[1]!=expected:raise ValueError('Variable/initial-priority changes beyond contract')
    candidate=once(candidate,cv[0],ov[0])
    intermediates='intermediates (ExternalAccess = observe)\n'
    if nonlinear:
        intermediates+='    mass_delta = mass_scale*sinh(mass_coordinate);\n'
        intermediates+='    stored_mass = mass_reference + mass_scale*sinh(mass_coordinate);\n'
        candidate=once(candidate,"    mass_scale = {0.1, 'kg'}; % Positive coordinate scale\n")
        candidate=once(candidate,'    assert(mass_scale > 0)\n')
    else:intermediates+='    stored_mass = mass_reference + mass_delta;\n'
    intermediates+='    stored_energy = energy_reference + energy_delta;\n'
    intermediates+=''.join(line.replace(' == ',' = ') for line in table)+'end\n\n'
    candidate=once(candidate,intermediates)
    for line in ("    mass_reference = {0.1, 'kg'}; % Constant coordinate origin\n",
                 "    energy_reference = {10000, 'J'}; % Constant coordinate origin\n"):
        candidate=once(candidate,line)
    anchor='    H.T == T_I;\n' if kind=='chamber' else '    p_I == p_environment;\n'
    candidate=once(candidate,anchor,anchor+''.join(table))
    derivative='mass_scale*cosh(mass_coordinate)*der(mass_coordinate)' if nonlinear else 'der(mass_delta)'
    candidate=once(candidate,derivative,'der(stored_mass)')
    candidate=once(candidate,'der(energy_delta)','der(stored_energy)')
    if candidate!=original:raise ValueError('Physical component changed beyond exact coordinate transformation')
    return True


def scalar_state_match(case,traces,name):
    matches=[s for s in case['state_values'] if s['name']=='ecc_shifted_inventory_probe.Inventory.'+name]
    if len(matches)!=1 or matches[0]['label']!='CSTATE':raise ValueError('Required saved continuous coordinate absent')
    s=matches[0];values=np.asarray(s['data']);t=np.asarray(s['time_s'])
    if not np.array_equal(t,traces[name]['time_s']) or not np.array_equal(values,traces[name]['values']):
        raise ValueError('Saved coordinate and physical log are not identical')
    return dict(name=name,samples=len(t),first=float(values[0]),last=float(values[-1]),
                max_abs=float(np.max(abs(values))),saved_unit=s['unit'],numeric_identity_verified=True)


def build(repo):
    root=repo/'outputs_storage_audit';inputs=[];experiments=[]
    for folder,nonlinear in [('increment_inventory_flow_scalartext_20260910',False),('nonlinear_mass_flow_fixture_20260910',True)]:
        path=root/folder/'shifted_inventory_probe.json';r=read(path);inputs.append(path)
        if (not r['collection_pass'] or r['error_message'] or len(r['cases'])!=8 or r['fixture_kind']!='flow'
                or r['formulation']!=('nonlinear_mass' if nonlinear else 'intermediates')
                or any(r[k] for k in ('production_recovery_allowed','main_model_run','cold_main_targets_verified','checkpoint_loaded','checkpoint_saved'))):
            raise ValueError('Unexpected fixture scope')
        for v in r['variants']:
            original=Path(v['source']);generated=Path(v['generated_source']);inputs.extend([original,generated])
            protected={'chamber':'AFCA0E54FE8A28BB7769DA29E003273A987A43A11B718B66C68C79807BD20539',
                       'buffer':'533335CDC7F826B5200C805E462E95B149609E3503BCE64EA42D3AD5431CF5AC'}
            if v['source_sha256']!=protected[v['kind']]:raise ValueError('Original physical source changed')
            if sha256(original)!=v['source_sha256'] or sha256(generated)!=v['generated_sha256']:raise ValueError('Source hash mismatch')
            reverse_source(generated.read_text(),original.read_text(),v['kind'],nonlinear)
        rows=[]
        for i,c in enumerate(r['cases']):
            kind='chamber' if i<4 else 'buffer';shifted=bool(i%2);flow=1e-6 if i%4<2 else -1e-6
            if (c['kind']!=kind or c['shifted']!=shifted or c['flow_kg_s']!=flow or c['heat_W']!=0
                    or c['solver']!='ode23t' or c['rel_tol']!=1e-6 or c['abs_tol']!=1e-8
                    or c['max_step_s']!=.00025 or c['local_solver']!='off'):
                raise ValueError('Case settings differ')
            traces={x['name']:x for x in c['traces']};raw=root/folder/c['file'];inputs.append(raw)
            expected={'stored_mass':'kg','stored_energy':'J','T_I':'K','p_I':'Pa','rho_I':'kg/m^3',
                      'u_I':'J/kg','mdot_A':'kg/s','Phi_A':'W','Q_H':'W'}
            if kind=='chamber':expected.update(mdot_B='kg/s',Phi_B='W')
            if shifted:expected.update(mass_delta='kg',energy_delta='J')
            if shifted and nonlinear:expected['mass_coordinate']='1'
            if len(traces)!=len(c['traces']) or {n:x['unit'] for n,x in traces.items()}!=expected:raise ValueError('Trace contract differs')
            with h5py.File(raw) as f:
                raw_rows=[f[ref] for ref in f['traces'][()].flat]
                if len(raw_rows)!=len(traces):raise ValueError('MAT coverage differs')
                for row in raw_rows:
                    name=text_field(row['name'])
                    if (text_field(row['unit'])!=traces[name]['unit'] or any(not np.array_equal(row[k][()].ravel(),traces[name][k])
                                                                          for k in ('time_s','values'))):raise ValueError('MAT/JSON mismatch')
            b,a,t=balance(traces);actual_flow=a['mdot_A']+a.get('mdot_B',0.)
            if np.max(abs(actual_flow-flow))>1e-18 or np.max(abs(a['Q_H']))>1e-12:raise ValueError('Physical boundary differs')
            states=[];initial={};coordinate_residual=None
            if shifted:
                base={x['name']:x for x in r['cases'][i-1]['traces']}
                for name,tol in [('stored_mass',1e-15),('stored_energy',1e-8),('T_I',1e-9),('p_I',1e-4)]:
                    initial[name]=float(abs(a[name][0]-base[name]['values'][0]))
                    if initial[name]>tol:raise ValueError('Initial physical target changed')
                if kind=='buffer' and c['origin_kg_J']!=[.1,10000]:raise ValueError('High target translation invalid')
                if c['origin_kg_J']!=r['cases'][i-1]['origin_kg_J']:raise ValueError('Origin differs from paired baseline')
                states.append(scalar_state_match(c,traces,'energy_delta'))
                if nonlinear:
                    states.append(scalar_state_match(c,traces,'mass_coordinate'))
                    scale=c['origin_kg_J'][0];delta=scale*np.sinh(a['mass_coordinate'])
                    if not np.allclose(delta,a['mass_delta'],rtol=5e-16,atol=1e-30):raise ValueError('Nonlinear reconstruction differs')
                    reconstructed=scale+delta
                    if not np.array_equal(reconstructed,a['stored_mass']):raise ValueError('Absolute inventory differs')
                    coordinate_residual=float(np.max(abs(delta-delta[0]-flow*t)))
                    if coordinate_residual>1e-15:raise ValueError('Increment coordinate fails original mass limit')
            rows.append(dict(kind=kind,shifted=shifted,flow_kg_s=flow,balance=b,initial_pair_errors=initial,
                saved_coordinates=states,mass_increment_analytic_residual_kg=coordinate_residual,
                saved_mass_delta=any(s.endswith('.mass_delta') for s in c['state_names'])))
        experiments.append(dict(formulation=r['formulation'],cases=rows))
    candidates=[c for c in experiments[1]['cases'] if c['shifted']]
    failed=root/'increment_inventory_flow_fixture_20260910/shifted_inventory_probe.json';failure=read(failed)
    if (failure['collection_pass'] or failure['cases'] or failure['production_recovery_allowed']
            or 'Unexpected source structure' not in failure['error_message']):raise ValueError('Pre-simulation failure evidence changed')
    inputs.append(failed)
    folders=['shifted_fixture_state_values_20260910','increment_inventory_flow_fixture_20260910',
             'increment_inventory_flow_scalartext_20260910','nonlinear_mass_flow_fixture_20260910',
             'nonlinear_mass_flow_audit_20260910']
    manifest=[]
    for folder in folders:
        for p in sorted((root/folder).rglob('*')):
            if p.is_file():manifest.append(dict(path=str(p.relative_to(repo)),bytes=p.stat().st_size,sha256=sha256(p)))
    frozen=root/'nonlinear_mass_qualification_package_20260910/nonlinear_mass_probe_audit.json'
    if frozen.exists():
        if sha256(frozen)!='137768091C382BEF495FB9A948F8350800819C25342F2D7AAC6489985BC5EC1C':
            raise ValueError('Frozen qualification manifest changed')
        if read(frozen)['files']!=manifest:raise ValueError('Qualification files changed')
    return dict(evidence_audit_pass=True,physical_equivalence_verified=True,experiments=experiments,
        nonlinear_flow_fixture_pass=all(all(v['passed'] for v in c['balance'].values()) for c in candidates),
        mass_coordinate_numeric_identity_cases=len(candidates),mass_coordinate_near_origin_verified=True,
        compiled_independent_differential_vector_fully_identified=False,
        coupled_model_pass=False,production_recovery_allowed=False,table4_reproduction_claim=False,
        evidence_file_count=len(manifest),evidence_bytes=sum(f['bytes'] for f in manifest),
        files=manifest,deleted_files=0,large_raw_or_checkpoint_duplicated=False,
        next_gate='Validate cold full-model target translation and effective error scales before any cycle continuation.',
        input_sha256={str(p.relative_to(repo)):sha256(p) for p in inputs})


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output-root',type=Path,required=True);args=parser.parse_args()
    if args.output_root.exists():raise FileExistsError('Never overwrite coordinate evidence')
    r=build(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'nonlinear_mass_probe_audit.json').write_text(json.dumps(r,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in r.items() if k not in ('experiments','input_sha256','files')},indent=2))
