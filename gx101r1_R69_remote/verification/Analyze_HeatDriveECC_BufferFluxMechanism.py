"""Resolve saved buffer storage into transport and smoothed-port conduction bounds."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_ConservativeBufferTrial import inventory
from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_NativeWindowLedger import validate_grid
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_TLDomainInventory import resolve_domains
from Audit_HeatDriveECC_TLDomainInventory import literal_vector
from Analyze_HeatDriveECC_BufferPerformanceImpact import BUFFER_SIGNALS
from HeatDriveECC_ObservationWindow import window_indices


def convection_bounds(mdot, pressure, u_in, u_out, power, rho_min, rho_max):
    mdot,pressure,u_in,u_out,power=[np.asarray(x,dtype=float) for x in
                                   (mdot,pressure,u_in,u_out,power)]
    if (mdot.ndim!=1 or any(x.shape!=mdot.shape for x in (pressure,u_in,u_out,power)) or
            not np.isfinite([mdot,pressure,u_in,u_out,power]).all() or np.any(pressure<=0) or
            not np.isfinite([rho_min,rho_max]).all() or not 0<rho_min<=rho_max):
        raise ValueError('Invalid actual port traces or density bounds')
    advection=np.maximum(mdot,0)*u_in+np.minimum(mdot,0)*u_out
    work_a=mdot*pressure/rho_min;work_b=mdot*pressure/rho_max
    work_low=np.minimum(work_a,work_b);work_high=np.maximum(work_a,work_b)
    return dict(advection_W=advection,flow_work_low_W=work_low,flow_work_high_W=work_high,
                smoothing_low_W=power-advection-work_high,
                smoothing_high_W=power-advection-work_low)


def symmetric_inventory_split(energy, temp, mass):
    temp,mass=np.asarray(temp,dtype=float),np.asarray(mass,dtype=float)
    if temp.shape!=(2,) or mass.shape!=(2,) or not np.isfinite([temp,mass]).all() or np.any(mass<=0):
        raise ValueError('Require two actual inventory endpoints')
    e00,e10,e01,e11=energy(np.array([temp[0],temp[1],temp[0],temp[1]]),
                           np.array([mass[0],mass[0],mass[1],mass[1]]))
    return dict(temperature_change_energy_J=float(((e10-e00)+(e11-e01))/2),
                mass_change_energy_J=float(((e01-e00)+(e11-e10))/2),
                total_change_J=float(e11-e00))


def interval_partition(time):
    time=np.asarray(time,dtype=float)
    if time.ndim!=1 or time.size<2 or not np.isfinite(time).all() or np.any(np.diff(time)<=0):
        raise ValueError('Invalid physical time grid')
    phase=np.remainder((time[:-1]+time[1:])/2,10)
    return np.searchsorted([3.5,5.,8.5],phase,side='right')+1


def source_conductivity(builder,domain,temperatures):
    name='k_water_mW_per_mK' if domain.endswith('/SMA_ThermalLiquidSettings') else 'k_se_mW_per_mK'
    matches=re.findall(r'\b'+name+r'\s*=\s*(\[[^\]]+\])\s*;',builder)
    if len(matches)!=1:raise ValueError('Ambiguous producer conductivity vector')
    values=literal_vector(matches[0].replace('...',''))*.001
    if values.shape!=temperatures.shape or np.any(values<=0):
        raise ValueError('Conductivity vector does not match saved domain')
    return float(np.interp(293.15,temperatures,values))


def upwind_temperature(table,pressure,specific_energy):
    temperatures=table['u'].grid[0]
    count=pressure.size
    nodes=table['u'](np.column_stack((np.repeat(temperatures,count),np.tile(pressure,temperatures.size))))
    nodes=nodes.reshape(temperatures.size,count)
    if np.any(np.diff(nodes,axis=0)<=0) or np.any(specific_energy<nodes[0]) or np.any(specific_energy>nodes[-1]):
        raise ValueError('Require a monotone in-domain internal-energy interpolation')
    index=np.minimum((nodes<=specific_energy).sum(axis=0)-1,temperatures.size-2)
    columns=np.arange(count);low=nodes[index,columns];high=nodes[index+1,columns]
    return temperatures[index]+(specific_energy-low)/(high-low)*(temperatures[index+1]-temperatures[index])


def smoothing_power(mdot,delta_u,conductance):
    if not np.isfinite(conductance) or conductance<=0:raise ValueError('Positive conduction parameter required')
    return 2*conductance**2/(np.sqrt(mdot*mdot+4*conductance**2)+abs(mdot))*delta_u


def analyze(root,physics_path,library_source):
    physics=json.loads(physics_path.read_text(encoding='utf-8-sig'))
    execution=json.loads((root/'cold_chamber_execution.json').read_text(encoding='utf-8-sig'))
    if (physics['producer']!=execution['execution_commit'] or
            physics['cycles_run']!=execution['cycle_count'] or not physics['mechanism_subset_pass'] or
            [r['arm'] for r in physics['arms']]!=['native'] or
            not execution['requested_arm_collection_pass'] or execution['error_message'] or
            not physics['pressure_only_density_storage_declared']):
        raise ValueError('Require a completed unchanged-storage-model diagnostic')
    for relative in ('cold_chamber_execution.json','native/observations.mat','native/configuration.mat',
                     'native/inventory_metadata.json','native/tl_connectivity.json',
                     'native/buffer_replacement_contract.json'):
        expected={key.replace('\\','/'):value for key,value in physics['input_sha256'].items()}[relative]
        if sha256(root/relative)!=expected:raise ValueError('Changed physical evidence: '+relative)
    source=library_source.read_text(encoding='utf-8-sig')
    if not all(x in source for x in ('mdot_abs = sqrt(mdot^2 + 4*G^2)',
            'Phi/mdot_abs == step_pos*u_in - step_neg*u_out + pv',
            'pv = mdot/mdot_abs * port.p/rho')):
        raise ValueError('The installed convection equation changed')
    workspace=Path(__file__).resolve().parents[2]
    builder_bytes=subprocess.check_output(['git','show',execution['execution_commit']+
        ':gx101r1_R69_remote/Build_HeatDriveECC_EighthRound_Simulink_Model.m'],cwd=workspace)
    builder=builder_bytes.decode('utf-8-sig')
    if "'p_atm', '0.5'" not in builder:raise ValueError('Producer property reference changed')
    metadata=json.loads((root/'native/inventory_metadata.json').read_text(encoding='utf-8-sig'))
    tables={r['block_path']:energy_tables(r['parameters']) for r in metadata['settings_tables']}
    assignment,_=resolve_domains(json.loads((root/'native/tl_connectivity.json').read_text(encoding='utf-8-sig')))
    contracts=json.loads((root/'native/buffer_replacement_contract.json').read_text(encoding='utf-8-sig'))
    contracts={r['block_path'].rsplit('/',1)[-1]:r for r in contracts['buffers']}
    stop=execution['stop_time_s'];start=stop-20;buffers={}
    with h5py.File(root/'native/observations.mat') as f:
        native=named_rows(f,f['native'])
        for name,signal in BUFFER_SIGNALS.items():
            c=contracts[name];block=c['block_path'];table=tables[assignment[block]]
            raw_time=native[block,'T_I']['time_s'][:].ravel()
            selection=window_indices(raw_time,start,stop)
            time=raw_time[selection];validate_grid(time,start,stop,.001)
            def get(variable,unit):
                row=native[block,variable]
                if not np.array_equal(row['time_s'][:].ravel(),raw_time):raise ValueError('Mismatched native clocks')
                return scalar_series(row,unit)[selection]
            temp=get('T_I','K');mass=get('stored_mass','kg');stored=get('stored_energy','J')
            mdot=get('mdot_A','kg/s');power=get('Phi_A','W');heat=get('Q_H','W');pressure=get('p_A','Pa')
            public=f['signals/'+signal]
            port_temp=public['values'][:].ravel()[window_indices(public['time_s'][:],start,stop)]
            u_in=table['u'](np.column_stack((port_temp,pressure)));u_out=get('u_port','J/kg')
            rho_min=float(table['rho'].values.min());rho_max=float(table['rho'].values.max())
            bounds=convection_bounds(mdot,pressure,u_in,u_out,power,rho_min,rho_max)
            k_cv=source_conductivity(builder,assignment[block],table['u'].grid[0])/float(table['cp']([[293.15,5e5]])[0])
            G=k_cv*c['port_area_m2']/np.sqrt(4*c['port_area_m2']/np.pi)
            smoothed=np.sqrt(mdot*mdot+4*G*G)
            u_mix=.5*(1+mdot/smoothed)*u_in+.5*(1-mdot/smoothed)*u_out
            mixed_temperature=upwind_temperature(table,pressure,u_mix)
            rho_mix=table['rho'](np.column_stack((mixed_temperature,pressure)))
            exact_work=mdot*pressure/rho_mix
            exact_smoothing=smoothing_power(mdot,u_in-u_out,G)
            predicted=bounds['advection_W']+exact_work+exact_smoothing
            prediction_error=float(abs(predicted-power).max())
            if prediction_error>1e-6:raise ValueError('Source-derived port model does not reproduce actual Phi')
            bounds.update(exact_flow_work_W=exact_work,exact_smoothing_W=exact_smoothing)
            energy=lambda T,M:inventory(table,T,M,c['p_environment_Pa'],c['tank_area_m2'],
                c['gravity_m_s2'],c['reference_temperature_K'],c['auxiliary_depth_m'])['total']
            parts=[]
            for offset,cycle in ((0,execution['cycle_count']-1),(10000,execution['cycle_count'])):
                end=offset+10000;t=time[offset:end+1];dt=np.diff(t);stage=interval_partition(t)
                integrals={key.removesuffix('_W')+'_J':values[offset+1:end+1]*dt for key,values in bounds.items()}
                integrals['actual_port_energy_J']=power[offset+1:end+1]*dt
                integrals['thermal_port_energy_J']=heat[offset+1:end+1]*dt
                integrals['mass_into_buffer_kg']=mdot[offset+1:end+1]*dt
                rows=[dict(stage=k,**{key:float(values[stage==k].sum()) for key,values in integrals.items()})
                      for k in range(1,5)]
                total={key:float(values.sum()) for key,values in integrals.items()}
                split=symmetric_inventory_split(energy,temp[[offset,end]],mass[[offset,end]])
                de=float(stored[end]-stored[offset]);dm=float(mass[end]-mass[offset])
                if abs(split['total_change_J']-de)>1e-8:
                    raise ValueError('Inventory expression differs from the native energy state')
                sweeps=[]
                for area in (c['port_area_m2'],.001,.0001,np.pi*.0032**2/4):
                    hypothetical_G=G*np.sqrt(area/c['port_area_m2'])
                    flux=smoothing_power(mdot,u_in-u_out,hypothetical_G)
                    sweeps.append(dict(port_area_m2=float(area),
                        frozen_boundary_smoothing_J=float(np.sum(flux[offset+1:end+1]*dt))))
                parts.append(dict(global_cycle=cycle,actual_window_s=[float(t[0]),float(t[-1])],
                    internal_temperature_endpoint_K=[float(temp[offset]),float(temp[end])],
                    mass_endpoint_kg=[float(mass[offset]),float(mass[end])],
                    stored_energy_change_J=de,stored_mass_change_kg=dm,
                    mass_balance_residual_kg=total['mass_into_buffer_kg']-dm,
                    energy_balance_residual_J=total['actual_port_energy_J']+total['thermal_port_energy_J']-de,
                    symmetric_inventory_split=split,port_terms=total,stages=rows,
                    frozen_input_port_area_sweep=sweeps))
            buffers[name]=dict(port_area_m2=c['port_area_m2'],tank_area_m2=c['tank_area_m2'],
                port_to_tank_area_ratio=c['port_area_m2']/c['tank_area_m2'],
                equivalent_port_diameter_m=float(np.sqrt(4*c['port_area_m2']/np.pi)),
                property_density_bounds_kg_m3=[rho_min,rho_max],source_derived_G_kg_s=G,
                actual_Phi_reconstruction_max_error_W=prediction_error,cycles=parts)
    return dict(schema='heatdrive_ecc_saved_buffer_flux_mechanism_v2',source_root=str(root),
        total_cycles=execution['cycle_count'],actual_window_s=[start,stop],buffers=buffers,
        port_equation_basis='Phi=hard-upwind internal-energy advection + smoothed conduction + mdot*p/rho',
        conduction_bounds_basis='Exact native Phi minus actual-port upwind advection; flow work bounded by positive domain density extrema',
        gauge_dependence='Transport and open inventory mass terms depend on internal-energy datum; smoothing remainder does not',
        inventory_split_basis='Symmetric two-order endpoint decomposition, including pV/gravity/auxiliary energy; no derivative approximation',
        thermal_port_is_not_only_energy_path=True,conduction_coefficient_fitted=False,
        property_conductivity_basis='Exact execution-producer builder literal and saved thermodynamic property table, k(293.15K)/cp(293.15K,0.5MPa)',
        frozen_input_sweep_is_not_a_coupled_performance_prediction=True,
        trajectory_counterfactual_executed=False,parameter_causality_proven=False,
        simulation_executed=False,operating_point_loaded=False,source_state_edited=False,
        periodic_gate_assigned=False,production_recovery_allowed=False,outer_solve_eligible=False,
        table4_reproduction_claim=False,input_sha256={'physics_audit':sha256(physics_path),
            'installed_port_convection_source':sha256(library_source),
            'producer_builder_git_blob':hashlib.sha256(builder_bytes).hexdigest().upper()})


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--experiment-root',type=Path,required=True)
    parser.add_argument('--physics-audit',type=Path,required=True)
    parser.add_argument('--port-convection-source',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():raise FileExistsError('Never overwrite physical attribution evidence')
    result=analyze(args.experiment_root.resolve(),args.physics_audit.resolve(),args.port_convection_source.resolve())
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({name:row['cycles'][-1] for name,row in result['buffers'].items()},indent=2))
