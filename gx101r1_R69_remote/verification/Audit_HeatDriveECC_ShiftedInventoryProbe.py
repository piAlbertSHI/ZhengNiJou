"""Audit isolated affine-coordinate fixtures, not the coupled cold model."""
import argparse
import json
from pathlib import Path
import h5py
import numpy as np
from Audit_HeatDriveECC_ColdPassivePSObserver import read,sha256
from Audit_HeatDriveECC_SegmentedEvidence import text_field


def undo_translation(text):
    edits=[("    mass_reference = {0.1, 'kg'}; % Constant coordinate origin\n",''),
           ("    energy_reference = {10000, 'J'}; % Constant coordinate origin\n",''),
           ("    mass_delta = {0, 'kg'}; % Increment from constant origin\n",''),
           ("    energy_delta = {0, 'J'}; % Increment from constant origin\n",''),
           ('    stored_mass == mass_reference + mass_delta;\n',''),
           ('    stored_energy == energy_reference + energy_delta;\n',''),
           ('der(mass_delta)','der(stored_mass)'),('der(energy_delta)','der(stored_energy)')]
    for old,new in edits:
        if text.count(old)!=1:raise ValueError('Unexpected affine-coordinate source')
        text=text.replace(old,new)
    return text


def balance(traces):
    t=np.asarray(traces['stored_mass']['time_s'],dtype=float)
    if t.ndim!=1 or t.size<2 or not np.isfinite(t).all() or t[0]!=0 or t[-1]!=.04 or np.any(np.diff(t)<=0):
        raise ValueError('Incomplete fixture window')
    arrays={}
    for name,row in traces.items():
        a=np.asarray(row['values'],dtype=float)
        if a.shape!=t.shape or not np.isfinite(a).all() or not np.array_equal(row['time_s'],t):
            raise ValueError('Incompatible trace sampling')
        arrays[name]=a
    flow=arrays['mdot_A']+arrays.get('mdot_B',0.)
    power=arrays['Phi_A']+arrays.get('Phi_B',0.)+arrays['Q_H']
    result={}
    for name,f,limit in [('stored_mass',flow,1e-15),('stored_energy',power,1e-8)]:
        integral=np.r_[0.,np.cumsum(.5*np.diff(t)*(f[1:]+f[:-1]))]
        maximum=float(np.max(abs(arrays[name]-arrays[name][0]-integral)))
        result[name]=dict(max_abs_residual=maximum,threshold=limit,passed=maximum<=limit)
    return result,arrays,t


def build(repo):
    root=repo/'outputs_storage_audit';inputs=[];reports=[]
    for mode in ('closed','flow'):
        folder=root/f'shifted_inventory_{mode}_fixture_20260910'
        path=folder/'shifted_inventory_probe.json';record=read(path);inputs.append(path)
        if (not record['collection_pass'] or record['error_message'] or len(record['cases'])!=8
                or any(record[k] for k in ('production_recovery_allowed','main_model_run','cold_main_targets_verified',
                                          'checkpoint_loaded','checkpoint_saved'))):
            raise ValueError('Wrong fixture scope or incomplete collection')
        for variant in record['variants']:
            original=Path(variant['source']);generated=Path(variant['generated_source']);inputs.extend([original,generated])
            if sha256(original)!=variant['source_sha256'] or sha256(generated)!=variant['generated_sha256']:
                raise ValueError('Component provenance changed')
            if undo_translation(generated.read_text())!=original.read_text():raise ValueError('Physical equations changed')
        summaries=[]
        for i,c in enumerate(record['cases']):
            expected_kind='chamber' if i<4 else 'buffer';expected_shifted=bool(i%2);direction=1 if i%4<2 else -1
            heat=direction if mode=='closed' else 0.;flow=direction*1e-6 if mode=='flow' else 0.
            if (c['kind']!=expected_kind or c['shifted']!=expected_shifted or c['heat_W']!=heat
                    or c.get('flow_kg_s',0)!=flow):raise ValueError('Undeclared case')
            raw=folder/c['file'];inputs.append(raw);traces={x['name']:x for x in c['traces']}
            expected_units={'stored_mass':'kg','stored_energy':'J','T_I':'K','p_I':'Pa',
                'rho_I':'kg/m^3','u_I':'J/kg','mdot_A':'kg/s','Phi_A':'W','Q_H':'W'}
            if expected_kind=='chamber':expected_units.update(mdot_B='kg/s',Phi_B='W')
            if expected_shifted:expected_units.update(mass_delta='kg',energy_delta='J')
            if len(traces)!=len(c['traces']) or {n:x['unit'] for n,x in traces.items()}!=expected_units:
                raise ValueError('Trace units or coverage changed')
            with h5py.File(raw) as f:
                raw_rows={}
                for ref in f['traces'][()].flat:
                    row=f[ref];name=text_field(row['name']);raw_rows[name]=row
                if set(raw_rows)!=set(traces):raise ValueError('JSON/MAT trace coverage mismatch')
                for name,row in raw_rows.items():
                    if (text_field(row['unit'])!=traces[name]['unit'] or any(not np.array_equal(
                        row[k][()].ravel(),traces[name][k]) for k in ('time_s','values'))):
                        raise ValueError('JSON/MAT data mismatch')
            b,a,t=balance(traces)
            actual_flow=a['mdot_A']+a.get('mdot_B',0.)
            if np.max(abs(actual_flow-flow))>1e-18 or np.max(abs(a['Q_H']-heat))>1e-12:
                raise ValueError('Physical boundary differs from command')
            initial_errors={}
            if expected_shifted:
                base={x['name']:x for x in record['cases'][i-1]['traces']}
                for name,tol in [('stored_mass',1e-15),('stored_energy',1e-8),('T_I',1e-9),('p_I',1e-4)]:
                    error=abs(a[name][0]-base[name]['values'][0]);initial_errors[name]=float(error)
                    if error>tol:raise ValueError('Paired initial physical state changed')
                for name,delta,origin in [('stored_mass','mass_delta',c['origin_kg_J'][0]),
                                          ('stored_energy','energy_delta',c['origin_kg_J'][1])]:
                    if not np.allclose(a[name],origin+a[delta],rtol=0,atol=4*np.spacing(abs(origin))):
                        raise ValueError('Physical-coordinate reconstruction changed')
            summaries.append(dict(kind=c['kind'],shifted=expected_shifted,heat_W=heat,flow_kg_s=flow,
                samples=len(t),balance=b,initial_pair_errors=initial_errors,
                saved_energy_delta=any(s.endswith('.energy_delta') for s in c['state_names']),
                saved_mass_delta=any(s.endswith('.mass_delta') for s in c['state_names'])))
        reports.append(dict(mode=mode,cases=summaries))
    candidates=[c for r in reports for c in r['cases'] if c['shifted']]
    all_cases=[c for r in reports for c in r['cases']]
    return dict(evidence_audit_pass=True,fixtures=reports,affine_source_equivalence_verified=True,
        passing_local_balances=sum(all(v['passed'] for v in c['balance'].values()) for c in all_cases),
        fixture_case_count=len(all_cases),saved_energy_delta_cases=sum(c['saved_energy_delta'] for c in candidates),
        saved_mass_delta_cases=sum(c['saved_mass_delta'] for c in candidates),
        mass_coordinate_retention_pass=all(c['saved_mass_delta'] for c in candidates),
        coupled_replacement_qualified=False,production_recovery_allowed=False,table4_reproduction_claim=False,
        limitation='Saved-state names do not prove all internal solver coordinates; mass translation not established.',
        input_sha256={str(p.relative_to(repo)):sha256(p) for p in inputs})


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output-root',type=Path,required=True);args=parser.parse_args()
    if args.output_root.exists():raise FileExistsError('Never overwrite evidence')
    report=build(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'shifted_inventory_probe_audit.json').write_text(json.dumps(report,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k not in ('fixtures','input_sha256')},indent=2))
