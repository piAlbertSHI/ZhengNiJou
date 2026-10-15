"""Check the eight isolated area trials without granting coupled-model authority."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_NativeWindowLedger import validate_grid
from Audit_HeatDriveECC_SegmentedEvidence import sha256,text_field
from Audit_HeatDriveECC_TLDomainInventory import resolve_domains


def fixture_metrics(time,temperature,mass,energy,mdot,power,heat,predicted):
    arrays=[np.asarray(x,dtype=float) for x in (time,temperature,mass,energy,mdot,power,heat,predicted)]
    time,temperature,mass,energy,mdot,power,heat,predicted=arrays
    validate_grid(time,0,1,.001)
    if any(x.shape!=time.shape for x in arrays) or not np.isfinite(arrays).all():
        raise ValueError('Require complete finite fixture traces')
    energy_residual=np.r_[0,np.cumsum((power+heat)[1:]*np.diff(time))]-(energy-energy[0])
    mass_residual=np.r_[0,np.cumsum(mdot[1:]*np.diff(time))]-(mass-mass[0])
    gates=dict(zero_mass_flow=bool(np.all(mdot==0)),zero_H_heat=bool(np.all(heat==0)),
        mass_equation=bool(abs(mass_residual).max()<=1e-15),
        energy_equation=bool(abs(energy_residual).max()<=1e-8),
        port_equation=bool(abs(predicted-power).max()<=1e-6))
    return dict(gates=gates,component_equation_pass=all(gates.values()),
        energy_change_J=float(energy[-1]-energy[0]),
        temperature_change_K=float(temperature[-1]-temperature[0]),
        max_mass_balance_residual_kg=float(abs(mass_residual).max()),
        max_energy_balance_residual_J=float(abs(energy_residual).max()),
        max_Phi_equation_error_W=float(abs(predicted-power).max()))


def audit(root,mechanism_path):
    execution=json.loads((root/'fixture_execution.json').read_text(encoding='utf-8-sig'))
    if (not execution['collection_pass'] or execution['error_message'] or len(execution['cases'])!=8 or
            execution['attempted_sim_call_count']!=8 or not execution['simulation_executed'] or
            any(execution[key] for key in ('coupled_simulation_executed','operating_point_loaded',
                'source_state_edited','production_recovery_allowed','table4_reproduction_claim'))):
        raise ValueError('Require all eight isolated cases, never coupled recovery')
    source=Path(execution['source_root'])
    mechanism=json.loads(mechanism_path.read_text(encoding='utf-8-sig'))
    if Path(mechanism['source_root']).resolve()!=source.resolve() or mechanism['total_cycles']!=62:
        raise ValueError('Source-derived port equation refers to another trajectory')
    for key,file in (('configuration','native/configuration.mat'),('observation','native/observations.mat'),
                     ('source_operating_point','native/diagnostic_complete_operating_point.mat'),
                     ('source_history','native/diagnostic_state_observation.mat')):
        if sha256(source/file)!=execution[key+'_sha256']:raise ValueError('Fixture source changed')
    metadata=json.loads((source/'native/inventory_metadata.json').read_text(encoding='utf-8-sig'))
    tables={row['block_path']:energy_tables(row['parameters']) for row in metadata['settings_tables']}
    assignment,_=resolve_domains(json.loads((source/'native/tl_connectivity.json').read_text(encoding='utf-8-sig')))
    records=[];seen=set()
    with h5py.File(source/'native/observations.mat') as native:
        original=named_rows(native,native['native'])
        for case in execution['cases']:
            name=case['source_buffer'];area=case['port_area_m2'];key=(name,area)
            if key in seen or name not in ('SHEXFluidBuffer','SMAHotFluidBuffer'):
                raise ValueError('Duplicate or unknown case')
            seen.add(key)
            areas=[.01,.001,.0001,np.pi*.0032**2/4]
            if area not in areas or case['source_time_s']!=620 or case['duration_s']!=1 or case['fixed_step_s']!=.001:
                raise ValueError('Changed isolated matrix')
            file=root/case['file']
            if file.parent.resolve()!=root.resolve() or sha256(file)!=case['sha256']:raise ValueError('Changed case data')
            block='heatdrive_ecc_coupled_se21/'+name;table=tables[assignment[block]]
            with h5py.File(file) as f:
                actual=json.loads(text_field(f['record_json']))
                if actual!={k:v for k,v in case.items() if k not in ('file','sha256')}:
                    raise ValueError('Raw case metadata changed')
                rows={text_field(f[ref]['name']):f[ref] for ref in f['traces'][:].ravel()}
                time=rows['T_I']['time_s'][:].ravel()
                def get(name,unit):
                    row=rows[name]
                    if not np.array_equal(row['time_s'][:].ravel(),time):raise ValueError('Case clocks differ')
                    return scalar_series(row,unit)
                temp=get('T_I','K');mass=get('stored_mass','kg');energy=get('stored_energy','J');p=get('p_A','Pa')
                for field,values,variable,unit,tol in (
                    ('initial_temperature_K',temp,'T_I','K',1e-9),
                    ('initial_mass_kg',mass,'stored_mass','kg',1e-15),
                    ('initial_energy_J',energy,'stored_energy','J',1e-8)):
                    reference=scalar_series(original[block,variable],unit)[-1]
                    if case[field]!=reference or abs(values[0]-reference)>tol:
                        raise ValueError('Public fixture initial condition differs from actual C62 endpoint')
                boundary=np.full_like(temp,case['boundary_temperature_K'])
                expected_boundary=303.15 if name=='SHEXFluidBuffer' else 393.15
                if case['boundary_temperature_K']!=expected_boundary:raise ValueError('Changed boundary matrix')
                G=mechanism['buffers'][name]['source_derived_G_kg_s']*np.sqrt(area/.01)
                predicted=G*(table['u'](np.column_stack((boundary,p)))-get('u_port','J/kg'))
                result=fixture_metrics(time,temp,mass,energy,get('mdot_A','kg/s'),get('Phi_A','W'),get('Q_H','W'),predicted)
                records.append(dict(source_buffer=name,port_area_m2=area,**result))
    if len(seen)!=8:raise ValueError('Incomplete matrix')
    monotone=[]
    for name in ('SHEXFluidBuffer','SMAHotFluidBuffer'):
        selected=sorted([r for r in records if r['source_buffer']==name],key=lambda r:-r['port_area_m2'])
        monotone.append(bool(np.all(np.diff([abs(r['energy_change_J']) for r in selected])<0)))
    return dict(schema='heatdrive_ecc_buffer_geometry_fixture_audit_v1',source_root=str(root),cases=records,
        isolated_component_equations_pass=all(r['component_equation_pass'] for r in records),
        zero_mass_flow_conduction_demonstrated=True,observed_area_response_monotone=all(monotone),
        geometry_selected_for_full_coupled_model=False,full_coupled_gate_evaluated=False,
        checkpoint_qualified=False,production_recovery_allowed=False,outer_solve_eligible=False,
        table4_reproduction_claim=False,input_sha256={'fixture_execution':sha256(root/'fixture_execution.json'),
            'source_derived_flux_mechanism':sha256(mechanism_path)})


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--experiment-root',type=Path,required=True)
    parser.add_argument('--flux-mechanism',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():raise FileExistsError('Never overwrite fixture evidence')
    result=audit(args.experiment_root.resolve(),args.flux_mechanism.resolve())
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps(result,indent=2))
    if not result['isolated_component_equations_pass']:raise SystemExit(1)
