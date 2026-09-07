"""Check source coverage, sign conventions and nonintrusive one-step observation."""
import argparse
from collections import Counter
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_C201Segments import audit as audit_segment
from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_SegmentedEvidence import sha256,text_field
from Audit_HeatDriveECC_ThermalConnectivity import wire_nets


def read(p):
    return json.loads(p.read_text(encoding='utf-8-sig'))


def compare_power(source,storage):
    a,b=np.asarray(source,dtype=float),np.asarray(storage,dtype=float)
    if a.shape!=(2,) or b.shape!=(2,) or not np.isfinite([a,b]).all():
        raise ValueError('Require two finite boundary samples')
    # Algebraic port-sum check only; this is not a first-law inventory tolerance.
    limit=1e-8
    residual=a-b
    return residual,bool(np.all(abs(residual)<=limit)),limit


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    repo=args.repo.resolve()
    root=repo/'outputs_storage_audit'
    probe=root/'c201_boundary_source_probe_20260907'
    baseline=root/'c201_bounded_20260907/nominal_s01'
    if args.output.exists():
        raise FileExistsError('Preserve diagnostic evidence')
    meta=read(probe/'source_restore_audit.json')
    authority=read(repo/'verification/c200_mainline_freeze_contract.json')
    if (not meta['strict_restore_pass'] or not meta['observation_complete'] or meta['error_message']
            or not meta['boundary_observation_requested'] or meta['boundary_sample_hold_diagnostic']
            or meta['full_cycle_verified'] or meta['production_recovery_allowed']
            or meta['source_operating_point_edited'] or meta['cold_start_executed']
            or not all(meta['physical_options_unchanged'].values())
            or meta['result_sha256']!=authority['result_sha256'] or meta['checkpoint_sha256']!=authority['checkpoint_sha256']
            or sha256(probe/'boundary_traces.mat')!=meta['boundary_trace_sha256']):
        raise ValueError('Boundary probe provenance failed')
    if not audit_segment(baseline)['data_audit_pass']:
        raise ValueError('Baseline segment failed its independent audit')
    comparisons=[]
    def compare(a,b,identity):
        if not np.array_equal(b['time_s'][:].reshape(-1),[2000,2000.001]):
            raise ValueError('Wrong one-step grid')
        if not np.array_equal(a['time_s'][:].reshape(-1)[:2],[2000,2000.001]):
            raise ValueError('Wrong baseline start')
        x,y=a['values'][...,:2],b['values'][:]
        if x.shape!=y.shape or not np.isfinite(y).all():
            raise ValueError('Invalid observed values')
        comparisons.append(dict(identity=identity,exact=bool(np.array_equal(x,y)),max_abs=float(abs(x-y).max())))
    with h5py.File(baseline/'segment_01.mat') as a,h5py.File(probe/'restored_step_signals.mat') as b,h5py.File(probe/'registered_states.mat') as c:
        if set(a['signals'])!=set(b['signals']) or len(a['signals'])!=161:
            raise ValueError('Physical signal coverage changed')
        for key in a['signals']:
            compare(a['signals'][key],b['signals'][key],key)
        for left,right,left_file,right_file,count in (
            (a['native'],b['native'],a,b,1240),
            (a['observation/states'],c['observation/states'],a,c,73)):
            x,y=named_rows(left_file,left),named_rows(right_file,right)
            if set(x)!=set(y) or len(x)!=count:
                raise ValueError('State identity changed')
            for key in x:
                if 'unit' in x[key] and text_field(x[key]['unit'])!=text_field(y[key]['unit']):
                    raise ValueError('Observed unit changed')
                compare(x[key],y[key],'::'.join(key))
        native=named_rows(b,b['native'])
        storage_input=np.zeros(2)
        for (_,name),row in native.items():
            if name.startswith('Phi_') or name in ('Q_H','Q'):
                storage_input+=convert(row['values'][:].reshape(-1),text_field(row['unit']),'W')
    with h5py.File(baseline/'command_profiles.mat') as a,h5py.File(probe/'command_profiles.mat') as b:
        if set(a['commands'])!=set(b['commands']) or len(a['commands'])!=5:
            raise ValueError('Command set changed')
        for key in a['commands']:
            for field in ('time_s','values'):
                if not np.array_equal(a['commands'][key][field][:],b['commands'][key][field][:]):
                    raise ValueError('Observation changed a command')
    topology_path=root/'c201_inventory_20260907_v2/thermal_connectivity.json'
    topology=read(topology_path)
    nets={p:net for net in wire_nets(topology) for p in net}
    references={b['block_path'] for b in topology['blocks'] if b['source_file']=='foundation.thermal.elements.reference'}
    flows=[]; pumps=[]; source_counts=Counter(); heat_total=np.zeros(2); pump_total=np.zeros(2)
    with h5py.File(probe/'boundary_traces.mat') as f:
        md=f['boundary_metadata']
        for flag in ('physical_model_modified','complete_cycle_verified','full_device_first_law_verified','production_recovery_allowed'):
            if bool(md[flag][0,0]):
                raise ValueError('Boundary discovery overclaims scope')
        traces=named_rows(f,f['boundary'])
        if len(traces)!=162:
            raise ValueError('Unexpected source trace inventory')
        for row in traces.values():
            if (not np.array_equal(row['time_s'][:].reshape(-1),[2000,2000.001])
                    or row['values'].shape!=(1,2) or not np.isfinite(row['values'][:]).all()):
                raise ValueError('Invalid source trace grid')
        def series(path,name,unit):
            row=traces[path,name]
            return convert(row['values'][:].reshape(-1),text_field(row['unit']),unit)
        for ref in md['blocks'][:].flat:
            block=f[ref]; path=text_field(block['block_path']); source=text_field(block['source_file'])
            source_counts[source]+=1
            if source=='foundation.thermal_liquid.sources.pressure_source':
                mode=text_field(block['parameters/power_spec'])
                if mode!='foundation.enum.power_spec.none':
                    raise ValueError('Pump energy mode changed')
                power=series(path,'power','W')
                residual=series(path,'Phi_A','W')+series(path,'Phi_B','W')+power
                hydraulic=series(path,'P','Pa')*series(path,'mdot_A','kg/s')/(
                    .5*(series(path,'rho_A','kg/m^3')+series(path,'rho_B','kg/m^3')))
                if np.any(power!=0) or abs(residual).max()>1e-10:
                    raise ValueError('Pressure-source algebraic energy balance failed')
                pumps.append(dict(block_path=path,power_spec=mode,native_power_W=power.tolist(),
                                  hydraulic_diagnostic_W=hydraulic.tolist(),hydraulic_power_not_injected_as_heat=True))
                pump_total+=power
            elif source=='foundation.thermal.sources.temperature':
                q=-series(path,'Q','W')
                flows.append(dict(block_path=path,role='external_temperature_source',power_into_network_W=q.tolist()))
                heat_total+=q
            elif source=='foundation.thermal.sources.controlled_heat_flow':
                a=nets[path+':A'];b=nets[path+':B']
                is_ref=lambda net:any(p.rsplit(':',1)[0] in references for p in net)
                if not is_ref(a) or is_ref(b):
                    raise ValueError('Cannot assign controlled heat-source direction')
                q=series(path,'Q','W')
                if not np.array_equal(q,series(path,'S','W')):
                    raise ValueError('Controlled heat source differs from its command')
                role='constitutive_source' if '/Subsystem2/' in path else 'external_load'
                flows.append(dict(block_path=path,role=role,power_into_network_W=q.tolist()))
                heat_total+=q
            else:
                raise ValueError('Unclassified boundary source')
    expected={'foundation.thermal_liquid.sources.pressure_source':3,'foundation.thermal.sources.temperature':3,
              'foundation.thermal.sources.controlled_heat_flow':43}
    if dict(source_counts)!=expected:
        raise ValueError('Incomplete source coverage')
    residual,net_match,net_limit=compare_power(heat_total+pump_total,storage_input)
    source_files=[Path('C:/Program Files/MATLAB/R2025b/toolbox/physmod/simscape/library/m/+foundation')/p
                  for p in ('+thermal/+sources/temperature.ssc','+thermal/+sources/controlled_heat_flow.ssc',
                            '+thermal_liquid/+sources/pressure_source.ssc')]
    result=dict(schema='heatdrive_ecc_boundary_probe_audit_v1',source_counts=dict(source_counts),trace_count=162,
                comparison_groups=len(comparisons),exact_comparison_groups=sum(r['exact'] for r in comparisons),
                comparisons=comparisons,source_flows=flows,pumps=pumps,
                storage_net_power_W=storage_input.tolist(),source_net_power_W=(heat_total+pump_total).tolist(),
                instantaneous_net_residual_W=residual.tolist(),
                instantaneous_port_sum_match=net_match,algebraic_port_sum_tolerance_W=net_limit,
                one_step_source_coverage_verified=True,full_cycle_boundary_observation_verified=False,
                full_device_first_law_verified=False,production_recovery_allowed=False,table4_reproduction_claim=False,
                input_sha256={str(p):sha256(p) for p in [topology_path,*source_files,probe/'boundary_traces.mat',
                    probe/'source_restore_audit.json',probe/'restored_step_signals.mat',probe/'registered_states.mat',
                    probe/'command_profiles.mat',baseline/'segment_01.mat']})
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('comparisons','input_sha256','source_flows','pumps')},indent=2))
    if not all(r['exact'] for r in comparisons) or not net_match:
        raise SystemExit(1)


if __name__=='__main__':
    main()
