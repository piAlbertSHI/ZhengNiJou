"""Same-run CV coefficient/endpoint ledgers and explicit Qian outlet windows.

The thermal numerical CV includes measured constitutive source terms; this is
not the complete thermomechanical device first law. Short transient windows
are never promoted to Qian's ten cyclic-steady-cycle performance definition.
"""
import argparse
from collections import Counter
import csv
import json
from pathlib import Path

import numpy as np
from scipy.io import loadmat

from Analyze_HeatDriveECC_CoupledCVTrajectories import geometric_value, stage_coordinates
from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_NativeWindowLedger import validate_grid
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_ThermalConnectivity import wire_nets
from Audit_HeatDriveECC_TLDomainInventory import density_table, resolve_domains
from HeatDriveECC_TraceColumns import load
from Review_HeatDriveECC_CoupledCVPacket import on_grid, verify_arm, verify_sources
from Run_HeatDriveECC_ConservativeTransport import write_json


def path_steps(coefficient,coordinate):
    c=np.asarray(coefficient);x=np.asarray(coordinate)
    if c.shape!=x.shape or c.ndim!=1 or len(x)<2 or not np.isfinite([c,x]).all():
        raise ValueError('Require finite scalar coefficient and coordinate on identical samples')
    return c[1:]*np.diff(x)


def native_sum(data,path,prefix,unit):
    rows=[r for (p,n),r in data.items() if p==path and n.startswith(prefix)]
    if not rows:raise ValueError('Missing native port quantity')
    time=rows[0]['time_s']
    if any(not np.array_equal(r['time_s'],time) or r['values'].shape!=(len(time),1) for r in rows):
        raise ValueError('Native port time/channel layout mismatch')
    return sum((convert(r['values'][:,0],r['unit'],unit) for r in rows),np.zeros_like(time))


def source_sign(path,kind,nets,reference_ports):
    by_port={p:i for i,net in enumerate(nets) for p in net}
    references={by_port[p] for p in reference_ports}
    if kind=='foundation.thermal.sources.temperature':
        if path+':A' not in by_port:raise ValueError('Temperature source has no actual thermal A face')
        return -1,'single A.Q -> *; positive Q leaves modeled thermal network'
    if kind!='foundation.thermal.sources.controlled_heat_flow':raise ValueError('Unreviewed thermal source')
    a=by_port[path+':A'] in references;b=by_port[path+':B'] in references
    if a==b:raise ValueError('Controlled source does not have exactly one reference-side face')
    return (1 if a else -1),'actual A.Q -> B.Q; reference-side face resolved by typed wire graph'


def load_case(root,case):
    folder=root/case['arm']
    read=lambda name:json.loads((folder/name).read_text(encoding='utf-8'))
    contract=read('CV_contract.json');tl=read('CV_tl_topology.json');thermal=read('CV_thermal_topology.json')
    options=loadmat(folder/'CV_options.mat',simplify_cells=True)['options']
    if (options['simscape']['local_solver_choice']!='NE_BACKWARD_EULER_ADVANCER'
            or options['simscape']['local_solver_sample_time_s']!=.001):raise ValueError('Unsupported local integration rule')
    native=load(folder/'native_CV_observations.mat');workspace=load(folder/'workspace_CV_observations.mat')
    sources=load(folder/'source_CV_observations.mat')
    boundary=loadmat(folder/'source_CV_observations.mat',simplify_cells=True)['boundary']
    model=contract['storage_paths'][0].split('/')[0];time=next(iter(native.values()))['time_s']
    assignment,_=resolve_domains(tl)
    parameters={r['block_path']:r['parameters'] for r in contract['settings_tables']}
    return dict(folder=folder,contract=contract,tl=tl,thermal=thermal,options=options,native=native,workspace=workspace,
                sources=sources,boundary=boundary,model=model,time=time,assignment=assignment,parameters=parameters,
                tables={k:energy_tables(p) for k,p in parameters.items()})


def native_value(data,path,name,unit):
    r=data['native'][path,name]
    if not np.array_equal(r['time_s'],data['time']):raise ValueError('Native storage clock mismatch')
    return convert(r['values'][:,0],r['unit'],unit)


def signal(data,name):
    return on_grid(data['workspace'][data['model'],name],data['time'])


def storage(data):
    time=data['time'];dt=np.diff(time);rows=[]
    for b in data['contract']['storage_blocks']:
        path=b['block_path'];kind=b['mask_type'];p=b['mask_parameters']
        pdV=np.zeros_like(dt)
        v=lambda name,unit:native_value(data,path,name,unit)
        if kind=='Thermal Mass':
            mass=float(convert(p['mass']['value'],p['mass']['unit'],'kg'))
            cp=float(convert(p['sp_heat']['value'],p['sp_heat']['unit'],'J/(K*kg)'))
            temperature=v('T','K');U=mass*cp*temperature;M=np.zeros_like(time)
            dE=np.diff(U);dM=np.zeros_like(dt);power=v('Q','W');mdot=np.zeros_like(time)
            basis='fixed thermal mass; sensible only; latent/mechanical heat remains in measured sources'
        else:
            temperature=v('T_I','K');pressure=v('p_I','Pa');rho=v('rho_I','kg/m^3');u=v('u_I','J/kg');h=v('h_I','J/kg')
            power=native_sum(data['native'],path,'Phi_','W')+v('Q_H','W')
            mdot=native_sum(data['native'],path,'mdot_','kg/s')
            table=data['tables'][data['assignment'][path]];coords=np.column_stack((temperature,pressure))
            if (np.max(abs(table['rho'](coords)-rho))>1e-7 or np.max(abs(table['u'](coords)-u))>1e-6):
                raise ValueError('Native state does not match actual property domain')
            if kind=='Pipe (TL)':
                mode=b['model_modes']
                if mode['dynamic_compressibility']!='false':raise ValueError('Unsupported pipe accumulation')
                nominal=[float(convert(float(mode['T_nominal']),mode['T_nominal_unit'],'K')),
                         float(convert(float(mode['p_nominal']),mode['p_nominal_unit'],'Pa'))]
                density=float(density_table(data['parameters'][data['assignment'][path]])([nominal])[0])
                mass=density*geometric_value(p['area'],'m^2')*geometric_value(p['length'],'m')
                M=np.full_like(time,mass);U=M*u;dE=np.diff(U);dM=np.zeros_like(dt)
                basis='fixed nominal rho*V; delta(M*u), NOT delta(rho(T,p)*V*u)'
            elif kind=='Tank (TL)':
                if np.ptp(pressure)>1e-6:raise ValueError('Only observed constant-pressure tank supported')
                M=v('mass','kg');U=M*u
                dM=np.diff(M);dE=path_steps(M*table['cp'](coords),temperature)+path_steps(h,M)
                pdV=path_steps(pressure,v('volume','m^3'))
                basis='right-endpoint M*cp*dT + h*dM; variable mass endpoint U reported separately'
            elif kind=='Constant Volume Chamber (TL)':
                volume=float(convert(p['volume']['value'],p['volume']['unit'],'m^3'))
                M=rho*volume;U=M*u;cp=table['cp'](coords);alpha=table['alpha'](coords);beta=table['beta'](coords)
                dE=path_steps((rho*h/beta-temperature*alpha)*volume,pressure)+path_steps((cp-h*alpha)*M,temperature)
                dM=path_steps(M/beta,pressure)-path_steps(alpha*M,temperature)
                basis='right-endpoint native dUdp*dp+dUdT*dT; endpoint rho*V*u separate'
            else:raise ValueError('Unknown native storage type')
        rows.append(dict(path=path,kind=kind,basis=basis,U=U,M=M,dE=dE,dM=dM,power=power,mdot=mdot,pdV=pdV))
    if {r['path'] for r in rows}!=set(data['contract']['storage_paths']):raise ValueError('Incomplete accumulation set')
    return rows


def sources(data):
    nets=wire_nets(data['thermal'])
    reference_paths={b['block_path'] for b in data['thermal']['blocks'] if b['source_file']=='foundation.thermal.elements.reference'}
    reference_ports={v['key'] for v in data['thermal']['vertices'] if v['block_path'] in reference_paths}
    rows=[]
    for b in data['boundary']['blocks']:
        path=b['block_path'];kind=b['source_file']
        name='power' if kind=='foundation.thermal_liquid.sources.pressure_source' else 'Q'
        trace=data['sources'][path,name];values=on_grid(trace,data['time'])[:,0]
        values=convert(values,trace['unit'],'W')
        if name=='power':
            if b['parameters']['power_spec']!='foundation.enum.power_spec.none':raise ValueError('Review pump thermal mode')
            sign=1;rule='native Phi_A+Phi_B+power=0; engineering pump work is separate'
            role='native_pressure_source_thermal_input'
        else:
            sign,rule=source_sign(path,kind,nets,reference_ports)
            if kind.endswith('.temperature'):role='external_fixed_temperature'
            elif '/SMA/Subsystem2/' in path or '/SE/Subsystem2/' in path:role='constitutive_to_thermal_solver_NOT_device_external_heat'
            else:role='external_controlled_load'
        rows.append(dict(path=path,kind=kind,sign=sign,rule=rule,role=role,power=sign*values))
    if len(rows)!=49 or len({r['path'] for r in rows})!=49:raise ValueError('Source coverage differs')
    if Counter(r['role'] for r in rows)!=Counter({'external_fixed_temperature':3,'external_controlled_load':1,
            'constitutive_to_thermal_solver_NOT_device_external_heat':42,'native_pressure_source_thermal_input':3}):
        raise ValueError('Unclassified thermal source ownership')
    return rows


def balance_window(data,components,boundary,start,stop):
    time=data['time'];a=round(start/.001);b=round(stop/.001);sl=slice(a+1,b+1);steps=slice(a,b)
    validate_grid(time[a:b+1],start,stop,.001);dt=np.diff(time)[steps]
    incoming=sum((r['power'] for r in boundary),np.zeros_like(time))
    native_rate=sum((r['power'] for r in components),np.zeros_like(time))
    native_mass=sum((r['mdot'] for r in components),np.zeros_like(time))
    coefficient=sum((r['dE'][steps] for r in components),np.zeros_like(dt))
    mass_coefficient=sum((r['dM'][steps] for r in components),np.zeros_like(dt))
    rows=[]
    for r in components:
        flow=float(np.dot(dt,r['power'][sl]));acc=float(r['dE'][steps].sum())
        rows.append(dict(block_path=r['path'],mask_type=r['kind'],basis=r['basis'],
                         BE_port_energy_J=flow,BE_coefficient_accumulation_J=acc,BE_coefficient_residual_J=flow-acc,
                         endpoint_energy_change_J=float(r['U'][b]-r['U'][a]),
                         BE_tank_pressure_volume_work_out_J=float(r.get('pdV',np.zeros(len(time)-1))[steps].sum()),
                         BE_coefficient_mass_kg=float(r['dM'][steps].sum()),
                         BE_port_mass_kg=float(np.dot(dt,r['mdot'][sl])),endpoint_mass_change_kg=float(r['M'][b]-r['M'][a])))
    return dict(start_s=start,stop_s=stop,sample_count=b-a+1,quadrature='native right endpoint BE, no interpolation',
                source_component_identity_max_abs_W=float(abs(incoming[a:b+1]-native_rate[a:b+1]).max()),
                closed_fluid_port_mass_sum_max_abs_kg_s=float(abs(native_mass[a:b+1]).max()),
                source_terms=[dict(block_path=r['path'],source_file=r['kind'],role=r['role'],sign=r['sign'],sign_rule=r['rule'],
                                   BE_net_input_J=float(np.dot(dt,r['power'][sl]))) for r in boundary],
                source_net_input_J=float(np.dot(dt,incoming[sl])),native_port_net_input_J=float(np.dot(dt,native_rate[sl])),
                native_fluid_mass_start_kg=sum(float(r['M'][a]) for r in components),
                native_fluid_mass_end_kg=sum(float(r['M'][b]) for r in components),
                gross_source_absolute_energy_J=sum(float(np.dot(dt,abs(r['power'][sl]))) for r in boundary),
                BE_coefficient_accumulation_J=float(coefficient.sum()),
                BE_coefficient_residual_J=float(np.dot(dt,incoming[sl])-coefficient.sum()),
                BE_coefficient_mass_kg=float(mass_coefficient.sum()),
                endpoint_energy_change_J=sum(r['endpoint_energy_change_J'] for r in rows),
                BE_tank_pressure_volume_work_out_J=sum(r['BE_tank_pressure_volume_work_out_J'] for r in rows),
                endpoint_fluid_mass_change_kg=sum(r['endpoint_mass_change_kg'] for r in rows),components=rows,
                full_device_first_law_verified=False,constitutive_heat_is_not_external_system_heat=True)


def engineering_pumps(data,start,stop):
    time=data['time'];a=round(start/.001);b=round(stop/.001);dt=np.diff(time)[a:b];rows=[]
    for source in data['boundary']['blocks']:
        if source['source_file']!='foundation.thermal_liquid.sources.pressure_source':continue
        path=source['block_path'];name=path[len(data['model'])+1:]
        probes={p['source_port_name']:p for p in data['contract']['pump_pressure_contract']['probes'] if p['source_block']==name}
        if set(probes)!={'A','B'}:raise ValueError('Need both actual pressure-source faces')
        pressure={face:convert(signal(data,p['workspace_variable'])[:,0],p['unit'],'Pa') for face,p in probes.items()}
        q=data['sources'][path,'q_A']
        if q['unit']!='m^3/s':raise ValueError('Unreviewed pump volumetric-flow unit')
        q=on_grid(q,time)[:,0];work_rate=(pressure['B']-pressure['A'])*q
        native=data['sources'][path,'power'];native=convert(on_grid(native,time)[:,0],native['unit'],'W')
        rows.append(dict(source_path=path,formula='(p_B-p_A)*q_A; q_A positive into source A',
                         hydraulic_work_signed_J=float(np.dot(dt,work_rate[a+1:b+1])),
                         hydraulic_work_positive_J=float(np.dot(dt,np.maximum(work_rate[a+1:b+1],0))),
                         native_source_thermal_energy_J=float(np.dot(dt,native[a+1:b+1])),
                         electrical_efficiency_or_dissipation_heat_injection_assumed=False))
    if len(rows)!=3:raise ValueError('Incomplete engineering pump boundary')
    return rows


def oriented_faces(mdot,mask):
    active=np.asarray(mdot)[mask]
    if active.size==0 or not np.isfinite(active).all() or np.median(active)==0:raise ValueError('No resolved active route')
    return ('b','a') if np.median(active)>0 else ('a','b')


def cooling_decomposition(cp_power,advected,wall_stage,wall_all,sensor):
    terms={'declared_cp_minus_native_enthalpy_W':cp_power-advected,
           'advected_minus_wall_stage_storage_W':advected-wall_stage,
           'exclude_non_stage4_wall_W':wall_stage-wall_all,
           'wall_minus_sensor_W':wall_all-sensor}
    return dict(terms,Eq10_minus_sensor_W=cp_power-sensor,
                algebraic_decomposition_roundoff_W=(cp_power-sensor)-sum(terms.values()),
                identity_is_not_a_physical_validation_gate=True)


def mechanical_bridge(data,boundary,start,stop):
    time=data['time'];a=round(start/.001);b=round(stop/.001);idx=slice(a,b+1);steps=slice(a,b)
    c=signal(data,'ECC_constitutive21_output');o=data['options'];g=o['geometry'];v=o['validation'];N=o['node_count']
    if N!=21 or c.shape!=(len(time),12*N):raise ValueError('Unsupported constitutive layout')
    sa=c[:,4*N:5*N];sr=c[:,5*N:6*N];ea=c[:,6*N:7*N];er=c[:,7*N:8*N]
    force=sa.mean(1)*g['S_a_m2']-sr.mean(1)*g['S_r_m2']
    displacement=ea.mean(1)*g['L_a_m']-er.mean(1)*g['L_r_m']
    scaled_force=abs(force)/np.maximum(abs(sr.mean(1)*g['S_r_m2']),1e-9)
    scaled_displacement=abs(displacement)/np.maximum(abs(er.mean(1)*g['L_r_m']),1e-9)
    blocks={r['block_path']:r for r in data['contract']['storage_blocks']};latent=np.zeros_like(time)
    masses={}
    for j,part in enumerate(('SMA','SE')):
        masses[part]=np.array([float(convert(blocks[f'{data["model"]}/{part}/Subsystem2/NodeMass_{k:02}']['mask_parameters']['mass']['value'],
                    blocks[f'{data["model"]}/{part}/Subsystem2/NodeMass_{k:02}']['mask_parameters']['mass']['unit'],'kg')) for k in range(1,N+1)])
        latent+=(c[:,(2+j)*N:(3+j)*N]*masses[part]*o['material'][part]['Delta_h_J_per_kg']).sum(1)
    q=sum((r['power'] for r in boundary if r['role'].startswith('constitutive_')),np.zeros_like(time))
    heat=float(np.dot(np.diff(time)[steps],q[a+1:b+1]));latent_change=float(latent[b]-latent[a])
    workA=float(np.sum(sa[a+1:b+1]*np.diff(ea[idx],axis=0))*g['S_a_m2']*g['L_a_m']/N)
    workR=float(np.sum(sr[a+1:b+1]*np.diff(er[idx],axis=0))*g['S_r_m2']*g['L_r_m']/N)
    dxR=np.diff(c[:,3*N:4*N],axis=0)[steps]
    phase_work=float(np.sum(-masses['SE']*(o['constitutive']['se_loading_work_J_per_kg']*np.maximum(dxR,0)+
                      o['constitutive']['se_unloading_work_J_per_kg']*np.minimum(dxR,0))))
    return dict(start_s=start,stop_s=stop,force_residual_max_N=float(abs(force[idx]).max()),
                displacement_residual_max_m=float(abs(displacement[idx]).max()),
                normalized_force_residual_max=float(scaled_force[idx].max()),
                normalized_displacement_residual_max=float(scaled_displacement[idx].max()),
                force_limit=v['max_eq6_scaled'],displacement_limit=v['max_eq7_scaled'],
                force_and_displacement_checks_pass=bool(np.max(scaled_force[idx])<=v['max_eq6_scaled'] and np.max(scaled_displacement[idx])<=v['max_eq7_scaled']),
                native_vs_observed_constitutive_heat_sum_max_abs_W=float(abs(q[idx]-c[idx,:2*N].sum(1)).max()),
                native_constitutive_heat_BE_J=heat,solid_mL_delta_phase_J=latent_change,
                declared_additional_phase_work_J=phase_work,
                coarse_common_stress_net_internal_mechanical_work_J=-workA+workR,
                coarse_work_not_claimed_equal_to_each_bed_32_substep_work=True,
                heat_minus_latent_and_declared_phase_work_J=heat-latent_change-phase_work,
                solid_chemical_energy_sign='U_chemical=-sum(m*Delta_h*xM); do not count latent heat twice',
                material_law_or_full_device_validation_granted=False)


def exchanger_metrics(data,start,stop):
    time=data['time'];options=data['options'];cycle,stage,elapsed=stage_coordinates(time,options)
    idx=(time>=start)&(time<=stop);duration=stop-start
    average=lambda x:float(np.trapezoid(np.asarray(x)[idx],time[idx])/duration)
    channels={};records=data['contract']['hex_channel_records']
    se_guard=options['validation']['se_settled_guard_s']+options['simulation']['fixed_step_s']
    for r in records:
        tag=r['tag'];path=r['block_path'];m=native_value(data,path,'mdot_A','kg/s')
        s=2 if tag=='hhex_se' else 4 if tag=='chex' else 1 if tag=='shex' else 3
        guard=1. if tag in ('shex','hhex_sma') else se_guard
        active=(stage==s)&(elapsed>=guard)
        out_face,in_face=oriented_faces(m,active)
        T={f:signal(data,'cv_'+tag+'_'+f+'_T_K')[:,0] for f in ('a','b')}
        channels[tag]=dict(path=path,mdot_A=m,temperature=T,outlet=out_face,inlet=in_face,guard=guard,
                           native_port_energy=native_sum(data['native'],path,'Phi_','W'),wall=native_value(data,path,'Q_H','W'))
    cold=channels['chex'];hot=channels['hhex_se'];cp=options['system']['cp_fluid_J_per_kgK']
    stage4=(stage==4).astype(float)
    cp_power=stage4*cold['mdot_A']*cp*(cold['temperature']['b']-cold['temperature']['a'])
    native_enthalpy=-stage4*cold['native_port_energy']
    sensor=signal(data,'Qdot_cold_sink_mass_to_hx_pipe_W')[:,0]
    mass_options=options['equilibrium']['m_r_kg']
    actual=sum(float(convert(b['mask_parameters']['mass']['value'],b['mask_parameters']['mass']['unit'],'kg'))
               for b in data['contract']['storage_blocks'] if '/SE/Subsystem2/NodeMass_' in b['block_path'])
    if not np.isclose(actual,mass_options,rtol=1e-12,atol=1e-15):raise ValueError('Active SE solid mass differs from compiled masses')
    lift=hot['temperature'][hot['outlet']]-cold['temperature'][cold['outlet']]
    observed={}
    for tag,c in channels.items():
        mask=idx&(stage==(2 if tag=='hhex_se' else 4 if tag=='chex' else 1 if tag=='shex' else 3))&(elapsed>=c['guard'])
        intended=1 if c['outlet']=='b' else -1
        observed[tag]=dict(pipe=c['path'],positive_mdot_A_means='A inlet, B outlet',intended_outlet_face=c['outlet'].upper(),
                           intended_inlet_face=c['inlet'].upper(),settled_route_direction_pass=bool(np.all(intended*c['mdot_A'][mask]>0)),
                           settled_guard_s=c['guard'],
                           mass_flow_A_min_max_kg_s=[float(c['mdot_A'][idx].min()),float(c['mdot_A'][idx].max())])
    aliases={}
    for name,tag in (('hot_hx_inlet_fluid_temp_out','hhex_se'),('hot_hx_outlet_fluid_temp_out','hhex_se'),
                     ('cold_hx_inlet_fluid_temp_out','chex'),('cold_hx_outlet_fluid_temp_out','chex')):
        x=signal(data,name)[:,0]
        aliases[name]={f:float(abs(x-channels[tag]['temperature'][f]).max()) for f in ('a','b')}
    upstream=abs(signal(data,'mass_flow_v4_hot_inlet_kgps')[:,0])*cp*stage4*(cold['temperature'][cold['outlet']]-cold['temperature'][cold['inlet']])
    return dict(start_s=start,stop_s=stop,cycles=duration/options['schedule']['tau_cycle_s'],
                quadrature='trapezoid on actually recorded 1 ms samples; both endpoints retained',
                paper_requirement='Qian2019 p885 Eq9/Eq10: TEN cycles after cyclic steady state',
                is_paper_ten_steady_cycle_window=False,performance_qualified=False,
                outlet_convention='actual settled route fixes geometric downstream face; face retained during no-flow intervals, NOT an inferred advective outlet',
                channels=observed,declared_glycol_cp_J_kgK=cp,active_SE_solid_mass_kg=actual,
                historical_probe_vs_actual_face_max_abs_K=aliases,
                historical_probe_comparison_scope='entire same-run record, not just this window',
                Eq10_historical_upstream_flow_W=average(upstream),
                Eq10_upstream_minus_actual_HEX_flow_W=average(upstream-cp_power),
                active_SE_solid_mass_g=actual*1000,scp_excludes='SMA, fluid, buffers, pipe and reservoir masses',
                Eq9_fixed_downstream_port_lift_K=average(lift),
                Eq9_stage4_contribution_K=average(stage4*lift),Eq9_non_stage4_contribution_K=average((1-stage4)*lift),
                Eq9_SE_both_routes_scheduled_inactive_contribution_K=average(np.isin(stage,[1,3])*lift),
                Eq10_measured_pipe_flow_declared_cp_W=average(cp_power),Eq10_diagnostic_W_per_g=average(cp_power)/(actual*1000),
                stage4_native_enthalpy_out_minus_in_W=average(native_enthalpy),
                stage4_native_CHEX_wall_heat_W=average(stage4*cold['wall']),all_cycle_native_CHEX_wall_heat_W=average(cold['wall']),
                all_cycle_CHEX_sensor_W=average(sensor),stage4_CHEX_sensor_W=average(stage4*sensor),
                CHEX_sensor_minus_native_wall_max_abs_W=float(abs(sensor-cold['wall'])[idx].max()),
                declared_cp_minus_native_enthalpy_stage4_W=average(cp_power-native_enthalpy),
                wall_minus_advected_energy_stage4_W=average(stage4*cold['wall']-native_enthalpy),
                Eq10_sensor_difference_decomposition=cooling_decomposition(average(cp_power),average(native_enthalpy),
                    average(stage4*cold['wall']),average(cold['wall']),average(sensor)),
                mass_basis_is_compiled_SE_solid=True,steady_cooling_load_equals_Eq10_claim=False)


def figure_differences(arms,path):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig,axes=plt.subplots(1,2,figsize=(11,4.6),layout='constrained')
    for j,arm in enumerate(arms):
        q=arm['Eq9_Eq10_diagnostics'][1];d=q['Eq10_sensor_difference_decomposition']
        color='#666666' if arm['arm']=='dual' else '#007A78';x=np.arange(4)+(j-.5)*.32
        axes[0].bar(x,[q['Eq10_measured_pipe_flow_declared_cp_W'],q['stage4_native_enthalpy_out_minus_in_W'],
                      q['stage4_native_CHEX_wall_heat_W'],q['all_cycle_CHEX_sensor_W']],.3,color=color,label=arm['arm'])
        axes[1].bar(x,[d['declared_cp_minus_native_enthalpy_W'],d['advected_minus_wall_stage_storage_W'],
                      d['exclude_non_stage4_wall_W'],d['Eq10_minus_sensor_W']],.3,color=color,label=arm['arm'])
    axes[0].set_xticks(np.arange(4),['Declared cp','Native\nenthalpy','Wall\n(stage 4)','Sensor\n(full cycle)'])
    axes[1].set_xticks(np.arange(4),['cp minus\nenthalpy','Flow minus wall\n(storage)','Off-stage\ncorrection','Total\ngap'])
    for ax,title in zip(axes,('(a) Different CHEX power definitions','(b) Eq.10 minus sensor decomposition')):
        ax.set(title=title,ylabel='Power averaged over full cycle (W)')
        ax.spines[['top','right']].set_visible(False);ax.axhline(0,color='#555555',lw=.6);ax.legend(frameon=False)
        ax.tick_params(axis='x',labelsize=9)
    axes[0].set_ylim(0,12.5);axes[1].set_ylim(-.1,1.0)
    fig.suptitle('Cold C2 (10-20 s): diagnostic, not cyclic-steady performance',fontsize=11)
    fig.savefig(path,dpi=200);plt.close(fig)


def analyze(root,output):
    e=json.loads((root/'coupled_CV_execution.json').read_text(encoding='utf-8'))
    if not e['collection_complete'] or e['checkpoint_loaded_or_saved'] or e['stop_time_s']!=20:
        raise ValueError('Require complete continuous diagnostic C2; never infer hidden restored states')
    verify_sources(e);arms=[]
    for case in e['completed_arms']:
        coverage=verify_arm(root,case,20);data=load_case(root,case);components=storage(data);boundary=sources(data)
        windows=[]
        for a,b in ((0,10),(10,20),(0,20)):
            row=balance_window(data,components,boundary,a,b);bridge=mechanical_bridge(data,boundary,a,b)
            row['two_bed_mechanical_latent_bridge']=bridge
            constitutive=bridge['native_constitutive_heat_BE_J'];latent=bridge['solid_mL_delta_phase_J']
            row['true_external_boundary_heat_J']=row['source_net_input_J']-constitutive
            row['endpoint_sensible_fluid_plus_solid_chemical_change_J']=row['endpoint_energy_change_J']-latent
            row['external_minus_corrected_endpoint_energy_J']=row['true_external_boundary_heat_J']-row['endpoint_sensible_fluid_plus_solid_chemical_change_J']
            row['external_minus_corrected_endpoint_plus_tank_pressure_work_J']=row['external_minus_corrected_endpoint_energy_J']-row['BE_tank_pressure_volume_work_out_J']
            row['engineering_pumps']=engineering_pumps(data,a,b)
            windows.append(row)
        chex_sensor=data['options']['validation']['cold_boundary_audit']['heat_flow_sensor_path']
        shex_sensor=data['model']+'/SHEX/SHEXSourceToSinkHeatFlowSensor'
        sensor_paths={r['block_path'] for r in data['thermal']['blocks'] if r['source_file']=='foundation.thermal.sensors.heat_flow'}
        if not {chex_sensor,shex_sensor}<=sensor_paths:raise ValueError('Named sensor boundary is not an actual heat-flow sensor')
        arms.append(dict(arm=case['arm'],coverage=coverage,
                         measurement_interfaces=dict(CHEX_sensor_path=chex_sensor,
                             CHEX_sensor_signal='Qdot_cold_sink_mass_to_hx_pipe_W',
                             SHEX_sensor_path=shex_sensor,
                             SHEX_sensor_signal='shex_source_heat_flow_W',zero_sensor_storage=True),
                         windows=windows,
                         Eq9_Eq10_diagnostics=[exchanger_metrics(data,a,b) for a,b in ((0,10),(10,20),(0,20))]))
    output.mkdir(parents=True,exist_ok=False)
    report=dict(schema='heatdrive_ecc_coupled_CV_balance_v1',execution_sha256=sha256(root/'coupled_CV_execution.json'),
                producer_commit=e['execution_commit'],reader_sha256=sha256(Path(__file__)),arms=arms,
                reference_equations=dict(Qian2019='Energy 182 (2019), p885, PDF page5, Eqs9/10; ten steady cycles',
                    Tank_TL='https://www.mathworks.com/help/releases/R2025b/hydro/ref/tanktl.html',
                    tank_coefficient_scope='documented constant-pressure M*cp*dT+h*dM; residual is diagnostic, not a physical rejection gate',
                    hidden_state_and_nonlinear_solver_coordinate_effects_not_excluded=True),
                no_new_simulation=True,production_recovery_allowed=False,Table4_reproduction_claim=False)
    with (output/'control_volume_table.csv').open('w',encoding='utf-8',newline='') as f:
        writer=csv.writer(f);writer.writerow(['arm','physical_path','CV_class','mass_boundary','energy_boundary','scope'])
        for arm in arms:
            for row in arm['windows'][0]['components']:
                writer.writerow([arm['arm'],row['block_path'],row['mask_type'],'positive native mdot into fluid CV; solids closed',row['basis'],
                                 'numerical thermal inventory; thermomechanical first law not granted'])
            for row in arm['windows'][0]['source_terms']:
                writer.writerow([arm['arm'],row['block_path'],row['role'],'no external mass',row['sign_rule'],
                                 'constitutive heat explicitly separate from true external boundary'])
            interface=arm['measurement_interfaces']
            for tag in ('CHEX','SHEX'):
                writer.writerow([arm['arm'],interface[tag+'_sensor_path'],tag+' thermal sensor','no mass; no storage',
                                 interface[tag+'_sensor_signal'], 'boundary measurement, not an extra energy source'])
            for row in arm['windows'][0]['engineering_pumps']:
                writer.writerow([arm['arm'],row['source_path'],'hydraulic work proxy','through-mass conserved; no accumulation',
                                 row['formula'],'NOT electrical input; NOT extra thermal input in native power_spec=none mode'])
    figure_differences(arms,output/'CHEX_power_definition_differences.png')
    report['control_volume_table_sha256']=sha256(output/'control_volume_table.csv')
    report['figure_sha256']=sha256(output/'CHEX_power_definition_differences.png')
    write_json(output/'coupled_CV_balance.json',report)
    print(json.dumps({'output':str(output),'arms':len(arms),'new_simulation':False,'Table4_claim':False}))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True);a=parser.parse_args();analyze(a.root.resolve(),a.output.resolve())
