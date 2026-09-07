"""C201 native storage ledgers with explicit equation and endpoint differences."""
import argparse
from collections import Counter,defaultdict
import copy
import csv
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_C201Segments import audit as audit_segment
from Audit_HeatDriveECC_C200StateCapture import archived_source
from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_NativeResidualLocalization import component_terms,backward_euler_integrals
from Audit_HeatDriveECC_NativeWindowLedger import evaluate_component,validate_grid,EXPECTED_COUNTS
from Audit_HeatDriveECC_TLDomainInventory import resolve_domains,density_table,scalar
from Audit_HeatDriveECC_SegmentedEvidence import sha256,text_field


def load_native(root):
    combined={}
    for i in range(1,4):
        folder=root/f'nominal_s{i:02d}'
        outcome=audit_segment(folder,root/f'nominal_s{i-1:02d}' if i>1 else None)
        if not outcome['data_audit_pass']:
            raise ValueError('Unverified segment')
        with h5py.File(folder/f'segment_{i:02d}.mat') as f:
            for key,row in named_rows(f,f['native']).items():
                unit=text_field(row['unit'])
                t,y=row['time_s'][:].reshape(-1),row['values'][:]
                if y.shape!=(1,len(t)):
                    raise ValueError('Require scalar native leaves')
                if i==1:
                    combined[key]=dict(unit=unit,time_s=[t],values=[y[0]])
                else:
                    if key not in combined or unit!=combined[key]['unit']:
                        raise ValueError('Native identity/unit changed')
                    combined[key]['time_s'].append(t[1:])
                    combined[key]['values'].append(y[0,1:])
    for row in combined.values():
        row['time_s']=np.concatenate(row['time_s'])
        row['values']=np.concatenate(row['values'])
        validate_grid(row['time_s'],2000,2010,.001)
    return combined


def ledgers(block,table,nominal_mass):
    reference=evaluate_component(block,table,nominal_mass)
    leaves={r['name']:r for r in block['leaf_variables']}
    time=np.asarray(next(iter(leaves.values()))['time_s'],dtype=float)
    def series(name,unit):
        r=leaves[name]
        return convert(r['values'],r['unit'],unit)
    kind=block['mask_type']
    if kind=='Thermal Mass':
        p=block['mask_parameters']
        mass=float(convert(p['mass']['value'],p['mass']['unit'],'kg'))
        capacity=mass*float(convert(p['sp_heat']['value'],p['sp_heat']['unit'],'J/(K*kg)'))
        energy=capacity*series('T','K')
        net=series('Q','W')
        mass_values=np.full_like(time,mass)
        mass_flow=np.zeros_like(time)
        be_energy=np.diff(energy)
        be_mass=np.zeros(len(time)-1)
        pdv=np.zeros(len(time)-1)
        reference['capacity_J_K']=capacity
    else:
        ports=reference['ports'] if 'ports' in reference else sorted(n[5:] for n in leaves if n.startswith('mdot_'))
        mass_flow=sum(series('mdot_'+p,'kg/s') for p in ports)
        net=sum(series('Phi_'+p,'W') for p in ports)+series('Q_H','W')
        if kind=='Pipe (TL)':
            mass_values=np.full_like(time,nominal_mass)
            energy=mass_values*series('u_I','J/kg')
            be_energy=np.diff(energy)
            be_mass=np.zeros(len(time)-1)
            pdv=np.zeros(len(time)-1)
        else:
            _,terms,_=component_terms(block,table)
            be_energy=terms['BE_energy_accumulation_J']
            be_mass=terms['BE_mass_accumulation_kg']
            if kind=='Tank (TL)':
                mass_values=series('mass','kg')
                pdv=backward_euler_integrals(series('p_I','Pa'),series('volume','m^3'))
            else:
                p=block['mask_parameters']['volume']
                mass_values=float(convert(p['value'],p['unit'],'m^3'))*series('rho_I','kg/m^3')
                pdv=np.zeros(len(time)-1)
            energy=mass_values*series('u_I','J/kg')
    input_energy=backward_euler_integrals(net,time)
    input_mass=backward_euler_integrals(mass_flow,time)
    histories=dict(BE_energy_input_J=np.r_[0,np.cumsum(input_energy)],
                   BE_coefficient_energy_residual_J=np.r_[0,np.cumsum(input_energy-be_energy)],
                   endpoint_energy_residual_J=np.r_[0,np.cumsum(input_energy-np.diff(energy)-pdv)],
                   BE_coefficient_mass_residual_kg=np.r_[0,np.cumsum(input_mass-be_mass)],
                   endpoint_mass_residual_kg=np.r_[0,np.cumsum(input_mass-np.diff(mass_values))])
    reference.update({name+'_end':float(values[-1]) for name,values in histories.items()})
    reference.update({name+'_max_abs':float(abs(values).max()) for name,values in histories.items()})
    reference['endpoint_energy_basis']='Delta(M*u) + integral(p dV) for tanks; sensible U for thermal masses; declared nominal mass for quasisteady pipes'
    reference['mass_flow_net_mean_kg_s']=float(input_mass.sum()/(time[-1]-time[0]))
    return reference,histories


def stage_totals(histories):
    ends=[0,3500,5000,8500,10000]
    rows=[]
    for a,b in zip(ends[:-1],ends[1:]):
        rows.append(dict(start_phase_s=a*.001,stop_phase_s=b*.001,
                         **{key:float(values[b]-values[a]) for key,values in histories.items()}))
    for key,values in histories.items():
        if not np.isclose(sum(r[key] for r in rows),values[-1]-values[0],atol=1e-11,rtol=1e-11):
            raise ValueError('Stage partition omitted or duplicated intervals')
    return rows


def compute(repo):
    root=repo/'outputs_storage_audit/c201_inventory_20260907_v2'
    raw=repo/'outputs_storage_audit/c201_bounded_20260907'
    meta=json.loads((root/'inventory_metadata.json').read_text(encoding='utf-8-sig'))
    topology=json.loads((root/'tl_connectivity.json').read_text(encoding='utf-8-sig'))
    source=archived_source(repo/'outputs_storage_audit/c200_source_compatibility_20260907')
    if (meta['schema']!='heatdrive_ecc_c200_inventory_metadata_v1' or not meta['collection_pass']
            or meta['simulation_run'] or meta['checkpoint_saved'] or meta['production_recovery_allowed']
            or meta['matlab_release']!='2025b'):
        raise ValueError('Invalid actual model metadata')
    if sha256(raw/'nominal_s01/diagnostic_options.mat')!=meta['options_sha256']:
        raise ValueError('Actual options differ from inventory')
    with h5py.File(raw/'nominal_s01/diagnostic_options.mat') as f:
        p=f['options/simscape']
        solver=dict(enabled=bool(p['local_solver_enabled'][0,0]),
                    choice=text_field(p['local_solver_choice']),
                    sample_time_s=float(p['local_solver_sample_time_s'][0,0]))
        if not solver['enabled'] or solver['choice']!='NE_BACKWARD_EULER_ADVANCER' or solver['sample_time_s']!=.001:
            raise ValueError('BE ledger requires the recorded local BE solver and native sample time')
    authority=json.loads((repo/'verification/c200_mainline_freeze_contract.json').read_text(encoding='utf-8-sig'))
    restored=json.loads((raw/'nominal_s01/source_restore_audit.json').read_text(encoding='utf-8-sig'))
    if (meta['source_code_commit']!=authority['source_code_commit']
            or meta['archived_model_sha256']!=restored['archived_model_sha256']
            or meta['source_result_sha256']!=authority['result_sha256']
            or meta['source_checkpoint_sha256']!=authority['checkpoint_sha256']):
        raise ValueError('Inventory has a different authority')
    assignment,count=resolve_domains(topology)
    if count!=2 or dict(Counter(r['mask_type'] for r in meta['storage_blocks']))!=EXPECTED_COUNTS:
        raise ValueError('Unexpected domain or storage coverage')
    native=load_native(raw)
    settings={r['block_path']:r['parameters'] for r in meta['settings_tables']}
    if set(settings)!=set(assignment.values()):
        raise ValueError('Fluid domain assignment differs from tables')
    tables={k:energy_tables(v) for k,v in settings.items()}
    densities={k:density_table(v) for k,v in settings.items()}
    rows=[]
    histories={}
    consumed=set()
    for original in meta['storage_blocks']:
        block=copy.deepcopy(original)
        path=block['block_path']
        block['leaf_variables']=[]
        for key,trace in native.items():
            if key[0]==path:
                block['leaf_variables'].append(dict(name=key[1],**trace))
                consumed.add(key)
        if not block['leaf_variables']:
            raise ValueError('Missing component native traces')
        nominal=None
        table=None
        if block['mask_type']!='Thermal Mass':
            settings_path=assignment[path]
            table=tables[settings_path]
            if block['mask_type']=='Pipe (TL)':
                mode=block['model_modes']
                temp=scalar(mode['T_nominal'],mode['T_nominal_unit'],'K')
                pressure=scalar(mode['p_nominal'],mode['p_nominal_unit'],'Pa')
                p=block['mask_parameters']
                if p['area']['unit']!='m^2' or p['length']['unit']!='m':
                    raise ValueError('Unexpected pipe geometry units')
                nominal=float(densities[settings_path]([[temp,pressure]])[0])*p['area']['value']*p['length']['value']
        row,history=ledgers(block,table,nominal)
        row['settings_path']=assignment.get(path,'')
        row['stages']=stage_totals(history)
        rows.append(row)
        histories[path]=history
    if consumed!=set(native) or len(consumed)!=1240:
        raise ValueError('Some native traces were omitted')
    totals={key:sum(h[key] for h in histories.values()) for key in next(iter(histories.values()))}
    grouped=defaultdict(list)
    for row in rows:
        grouped[row['mask_type']].append(row)
    groups={kind:dict(component_count=len(items),
                     endpoint_energy_residual_J=sum(r['endpoint_energy_residual_J_end'] for r in items),
                     coefficient_energy_residual_J=sum(r['BE_coefficient_energy_residual_J_end'] for r in items),
                     endpoint_mass_residual_kg=sum(r['endpoint_mass_residual_kg_end'] for r in items)) for kind,items in grouped.items()}
    inputs=[root/n for n in ('inventory_metadata.json','tl_connectivity.json','thermal_connectivity.json')]
    inputs.append(repo/'verification/c200_mainline_freeze_contract.json')
    for i in range(1,4):
        folder=raw/f'nominal_s{i:02d}'
        inputs.extend(folder/n for n in (f'segment_{i:02d}.mat','diagnostic_options.mat',
                      'source_restore_audit.json','cycle_observation_audit.json','independent_segment_audit.json',
                      'command_profiles.mat','DO_NOT_RESUME_FOR_PRODUCTION.mat','final_observation_tail.mat'))
    thermal=json.loads((root/'thermal_connectivity.json').read_text(encoding='utf-8-sig'))
    thermal_paths=sorted({v['block_path'] for v in thermal['vertices']})
    boundary_candidates=[p for p in thermal_paths if p.endswith(('AmbientTempSource',
        'CHEXFixedReservoirTemperatureSource','ColdLoadHeatSource'))]
    result=dict(schema='heatdrive_ecc_c201_native_inventory_v2',computation_complete=True,source=source,solver=solver,
                component_count=119,native_trace_count=1240,hydraulic_domains=2,window_start_s=2000,window_stop_s=2010,
                sample_count=10001,intervals_omitted=0,component_groups=groups,components=rows,
                totals={key:dict(end=float(values[-1]),max_abs=float(abs(values).max())) for key,values in totals.items()},
                equation_diagnostics_are_not_endpoint_conservation=True,external_boundaries_fully_observed=False,
                full_device_first_law_verified=False,production_recovery_allowed=False,table4_reproduction_claim=False,
                storage_residual_is_not_independent_external_balance=True,
                boundary_coverage=dict(thermal_source_candidates=boundary_candidates,
                    source_candidates_are_not_complete_boundary_inventory=True,
                    missing_independent_measurements=['SHEX heat source and ambient branch',
                        'HHEX ambient rejection','CHEX fixed reservoir exchange','pump work and losses'],
                    chex_internal_sensor_is_not_complete_external_balance=True),
                input_sha256={str(p.relative_to(repo)):sha256(p) for p in inputs})
    return result,histories


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists() or args.output.with_suffix('.csv').exists():
        raise FileExistsError('Do not overwrite native ledger evidence')
    result,_=compute(args.repo)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    fields=['block_path','mask_type','settings_path','endpoint_energy_basis',
            'BE_coefficient_energy_residual_J_end','endpoint_energy_residual_J_end','endpoint_energy_residual_J_max_abs',
            'BE_coefficient_mass_residual_kg_end','endpoint_mass_residual_kg_end','endpoint_mass_residual_kg_max_abs']
    with args.output.with_suffix('.csv').open('w',encoding='utf-8-sig',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=fields,extrasaction='ignore')
        writer.writeheader(); writer.writerows(result['components'])
    print(json.dumps({k:v for k,v in result.items() if k not in ('components','input_sha256')},indent=2))


if __name__=='__main__':
    main()
