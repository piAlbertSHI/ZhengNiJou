"""Complete C201 source ledger, separated from endpoint first-law qualification."""
import argparse
from collections import defaultdict
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_C201Segments import audit as audit_segment
from Audit_HeatDriveECC_C201Cycle import metrics
from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_SegmentedEvidence import sha256,text_field


FOLDERS=('s01','s02_recovered_20260908','s03')


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def parameter_dict(node):
    if isinstance(node,h5py.Group):
        return {k:text_field(v) for k,v in node.items()}
    if (node.attrs.get('MATLAB_class')==b'struct' and node.attrs.get('MATLAB_empty')==1
            and np.array_equal(node[:],[1,1])):
        return {}
    raise ValueError('Unrecognized MATLAB parameter structure')


def integral_summary(values,time):
    values,time=np.asarray(values),np.asarray(time)
    if values.ndim!=1 or values.size<2 or values.shape!=time.shape or not np.isfinite([values,time]).all() or np.any(np.diff(time)<=0):
        raise ValueError('Invalid complete-window integral')
    be=float(np.sum(values[1:]*np.diff(time)))
    tr=float(np.trapezoid(values,time))
    return dict(BE_energy_J=be,trapezoid_energy_J=tr,BE_mean_W=be/(time[-1]-time[0]),
                trapezoid_mean_W=tr/(time[-1]-time[0]),min_W=float(values.min()),max_W=float(values.max()))


def compute(repo):
    root=repo/'outputs_storage_audit/c201_boundary_full_20260907'
    old=repo/'outputs_storage_audit/c201_bounded_20260907'
    probe=read(repo/'outputs_storage_audit/c201_boundary_source_probe_20260907/independent_boundary_audit_v2.json')
    if not probe['instantaneous_port_sum_match'] or probe['exact_comparison_groups']!=1474:
        raise ValueError('Unverified source signs and observation contract')
    for path,digest in probe['input_sha256'].items():
        if sha256(Path(path))!=digest:
            raise ValueError('Source discovery input changed')
    inventory_path=repo/'outputs_storage_audit/c201_inventory_20260907_v2/native_inventory_v2.json'
    inventory=read(inventory_path)
    for path,digest in inventory['input_sha256'].items():
        if sha256(repo/path)!=digest:
            raise ValueError('Frozen inventory input changed')
    source_parts=defaultdict(list);physical_parts=defaultdict(list)
    storage_parts=[];comparisons=[];inputs={};prior=None
    expected_sources=None;units={}
    with h5py.File(repo/'outputs_storage_audit/c201_boundary_source_probe_20260907/boundary_traces.mat') as f:
        expected_sources={k:text_field(r['unit']) for k,r in named_rows(f,f['boundary']).items()}
        expected_parameters={text_field(f[ref]['block_path']):parameter_dict(f[ref]['parameters'])
                             for ref in f['boundary_metadata/blocks'][:].flat}
    for i,name in enumerate(FOLDERS,1):
        folder=root/name
        result=audit_segment(folder,prior)
        if not result['data_audit_pass'] or not result['diagnostic_continuation_eligible']:
            raise ValueError('Segment not independently verified')
        prior=folder
        path=folder/f'segment_{i:02d}.mat'
        baseline=old/f'nominal_s{i:02d}'/f'segment_{i:02d}.mat'
        inputs[str(path)]=sha256(path);inputs[str(baseline)]=sha256(baseline)
        with h5py.File(path) as f,h5py.File(baseline) as b:
            groups=[('signals',dict(f['signals']),dict(b['signals'])),
                    ('native',named_rows(f,f['native']),named_rows(b,b['native'])),
                    ('state',named_rows(f,f['observation/states']),named_rows(b,b['observation/states']))]
            exact=0;largest=0.
            for prefix,current,reference in groups:
                if set(current)!=set(reference):
                    raise ValueError('Old observation identities changed')
                for key,row in current.items():
                    a=reference[key]
                    x,y=a['values'][:],row['values'][:]
                    if x.shape!=y.shape or not np.array_equal(a['time_s'][:],row['time_s'][:]):
                        raise ValueError('Old observation time or dimensions changed')
                    if 'unit' in a and text_field(a['unit'])!=text_field(row['unit']):
                        raise ValueError('Old observation units changed')
                    exact+=int(np.array_equal(x,y));largest=max(largest,float(abs(x-y).max()))
                    if prefix=='signals':
                        physical_parts[key].append(y if i==1 else y[:,1:])
            comparisons.append(dict(segment=i,exact_groups=exact,expected_groups=1474,max_abs_difference=largest))
            # Reuse the independently audited inventory only after proving its
            # complete underlying trajectory is exactly the newly observed one.
            if exact!=1474:
                raise ValueError(f'Segment {i}: source observation changed the existing trajectory; maximum difference {largest}')
            source=named_rows(f,f['source_traces'])
            if {k:text_field(v['unit']) for k,v in source.items()}!=expected_sources:
                raise ValueError('Complete-cycle source identities or units differ from the sign audit')
            for ref in f['boundary_metadata/blocks'][:].flat:
                block=f[ref];block_path=text_field(block['block_path'])
                if parameter_dict(block['parameters'])!=expected_parameters[block_path]:
                    raise ValueError('A source parameter changed')
            for key,row in source.items():
                values=row['values'][:].reshape(-1)
                if len(values)!=result['segments'][0]['sample_count']:
                    raise ValueError('Require complete scalar source leaves')
                source_parts[key].append(values if i==1 else values[1:])
                units[key]=text_field(row['unit'])
            storage=np.zeros(result['segments'][0]['sample_count'])
            for (_,leaf),row in groups[1][1].items():
                if leaf.startswith('Phi_') or leaf in ('Q_H','Q'):
                    storage+=convert(row['values'][:].reshape(-1),text_field(row['unit']),'W')
            storage_parts.append(storage if i==1 else storage[1:])
    traces={k:np.concatenate(v) for k,v in source_parts.items()}
    signals={k:np.concatenate(v,axis=1) for k,v in physical_parts.items()}
    time=2000+np.arange(10001)*.001
    storage=np.concatenate(storage_parts)
    if storage.shape!=time.shape or any(v.shape!=time.shape for v in traces.values()):
        raise ValueError('Incomplete combined cycle')
    def series(path,name,unit):
        return convert(traces[path,name],units[path,name],unit)
    rates=defaultdict(lambda:np.zeros(10001));source_rows=[]
    for row in probe['source_flows']:
        path=row['block_path'];q=series(path,'Q','W')
        if row['role']=='external_temperature_source':
            q=-q
            role='SHEX_source_in' if '/SHEX/' in path else ('CHEX_reservoir_in' if 'CHEXFixedReservoir' in path else 'HHEX_ambient_in')
        elif row['role']=='constitutive_source':
            role='SMA_constitutive_in' if '/SMA/' in path else 'SE_constitutive_in'
            if not np.array_equal(q,series(path,'S','W')):
                raise ValueError('Constitutive source command mismatch')
        else:
            role='external_load_in'
        rates[role]+=q
        source_rows.append(dict(block_path=path,role=role,**integral_summary(q,time)))
    pumps=[]
    for row in probe['pumps']:
        path=row['block_path'];power=series(path,'power','W')
        if np.any(power!=0) or abs(series(path,'Phi_A','W')+series(path,'Phi_B','W')+power).max()>1e-8:
            raise ValueError('Pressure-source power contract changed')
        hydraulic=series(path,'P','Pa')*series(path,'mdot_A','kg/s')/(.5*(series(path,'rho_A','kg/m^3')+series(path,'rho_B','kg/m^3')))
        role='SMA_hydraulic_estimate' if path.endswith('/SMA Pressure Source (TL)') else 'SE_hydraulic_estimate'
        rates[role]+=np.maximum(hydraulic,0)
        rates['native_pump_input']+=power
        pumps.append(dict(block_path=path,power_spec='none',native=integral_summary(power,time),
                          signed_hydraulic=integral_summary(hydraulic,time),positive_hydraulic=integral_summary(np.maximum(hydraulic,0),time)))
    balance_keys=['SHEX_source_in','CHEX_reservoir_in','HHEX_ambient_in','external_load_in',
                  'SMA_constitutive_in','SE_constitutive_in','native_pump_input']
    net=sum(rates[k] for k in balance_keys)
    residual=net-storage
    allowance=1e-8
    ledger={k:integral_summary(v,time) for k,v in rates.items()}
    with h5py.File(root/FOLDERS[0]/'diagnostic_options.mat') as f:
        performance,solid,flows=metrics(signals,f['options'],time)
    source_positive=float(np.trapezoid(np.maximum(rates['SHEX_source_in'],0),time)/10)
    if source_positive<=0:
        raise ValueError('No positive SHEX source heat')
    endpoint_storage=sum(r['energy_endpoint_change_J']+r.get('pressure_volume_work_J',0) for r in inventory['components'])
    source_energy=integral_summary(net,time)['BE_energy_J']
    stages=[]
    for a,b in zip([0,3500,5000,8500],[3500,5000,8500,10000]):
        stages.append(dict(start_phase_s=a*.001,stop_phase_s=b*.001,
                           energy_J={k:float(np.sum(v[a+1:b+1]*np.diff(time[a:b+1]))) for k,v in rates.items()}))
    for key in rates:
        if not np.isclose(sum(s['energy_J'][key] for s in stages),ledger[key]['BE_energy_J'],atol=1e-9,rtol=1e-11):
            raise ValueError('Stage partition lost an interval')
    inputs[str(inventory_path)]=sha256(inventory_path)
    inputs[str(repo/'outputs_storage_audit/c201_boundary_source_probe_20260907/independent_boundary_audit_v2.json')]=sha256(repo/'outputs_storage_audit/c201_boundary_source_probe_20260907/independent_boundary_audit_v2.json')
    result=dict(schema='heatdrive_ecc_c201_boundary_cycle_v1',window_start_s=2000,window_stop_s=2010,samples=10001,
                complete_cycle_source_observation=True,source_count=49,source_trace_count=162,intervals_omitted=0,
                original_trajectory_comparisons=comparisons,source_rows=source_rows,pumps=pumps,ledger=ledger,stages=stages,
                instantaneous_port_sum_max_abs_W=float(abs(residual).max()),algebraic_port_sum_tolerance_W=allowance,
                all_samples_port_sum_match=bool(np.all(abs(residual)<=allowance)),
                BE_source_net_energy_J=source_energy,endpoint_storage_plus_pdv_J=endpoint_storage,
                source_minus_endpoint_storage_J=source_energy-endpoint_storage,
                inventory_basis='Frozen independent 119-component ledger, with all original native samples proven exactly equal',
                performance=performance,selected_solid_balances=solid,selected_flow_gates=flows,
                positive_SHEX_heat_mean_W=source_positive,
                diagnostic_heat_driven_COP=performance['cooling_power_W']/source_positive,
                COP_scope='Single-cycle Eq10 cooling / positive SHEX heat; excludes pump electric power; not qualified system COP',
                all_mechanism_gates_evaluated=False,ten_new_steady_cycles_verified=False,
                full_device_first_law_verified=False,production_recovery_allowed=False,table4_reproduction_claim=False,
                input_sha256=inputs)
    return result,time,dict(rates),residual


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite scientific evidence')
    result,_,_,_=compute(args.repo.resolve())
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('source_rows','input_sha256','pumps','selected_solid_balances','selected_flow_gates','stages')},indent=2))
    if not result['all_samples_port_sum_match']:
        raise SystemExit(1)


if __name__=='__main__':
    main()
