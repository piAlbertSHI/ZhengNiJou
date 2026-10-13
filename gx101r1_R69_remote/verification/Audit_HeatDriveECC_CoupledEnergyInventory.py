"""Separate modeled latent/thermal closure from conserved but migrating inventory."""
import argparse
import json
import subprocess
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_ColdChamberCycle import source_ledger
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_ColdPumpPressureProbes import normalized_rows
from Audit_HeatDriveECC_C201BoundaryCycle import integral_summary
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from HeatDriveECC_ObservationWindow import window_indices
from Audit_HeatDriveECC_TLDomainInventory import density_table, resolve_domains


BUFFER_NAMES = ('SHEXFluidBuffer', 'SMAHotFluidBuffer', 'ColdFluidBuffer', 'HotFluidBuffer')
ROOT = 'heatdrive_ecc_coupled_se21/'
CHAMBER_NAMES=('SMA_PumpInletConnectingPipeVolume','SMA_PumpOutletConnectingPipeVolume')
ENERGY_TOL_J = 1e-8  # Existing local backward-Euler inventory audit tolerance.
MASS_TOL_KG = 1e-15
SOURCE_ROLES = {'SHEX_source_in', 'CHEX_reservoir_in', 'external_load_in',
                'HHEX_ambient_in', 'native_pump_input', 'SMA_constitutive_in', 'SE_constitutive_in'}


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def latent_decomposition(time, q_command, phase, coefficients):
    time, q_command = np.asarray(time), np.asarray(q_command)
    phase, coefficients = np.asarray(phase), np.asarray(coefficients)
    if (time.ndim != 1 or len(time) < 2 or q_command.shape != time.shape
            or phase.shape != (2, len(time)) or coefficients.shape != (2,)
            or not all(np.isfinite(v).all() for v in (time, q_command, phase, coefficients))
            or np.any(np.diff(time) <= 0) or np.any(coefficients <= 0)
            or np.any((phase < 0) | (phase > 1))):
        raise ValueError('Invalid exact coupled energy coordinates')
    latent_steps = coefficients @ np.diff(phase, axis=1)
    command_steps = q_command[1:] * np.diff(time)
    mechanical_steps = command_steps - latent_steps
    return dict(latent_source_endpoint_increment_J=float(coefficients @ (phase[:, -1]-phase[:, 0])),
                latent_storage_change_J=float(-np.sum(latent_steps)),
                command_heat_BE_J=float(np.sum(command_steps)),
                internal_mechanical_net_J=float(np.sum(mechanical_steps)),
                internal_mechanical_step_max_abs_J=float(np.max(abs(mechanical_steps))),
                internal_mechanical_cumulative_max_abs_J=float(np.max(abs(np.cumsum(mechanical_steps)))))


def system_balance(source, sensible_inventory_plus_pdv, latent):
    if set(source) != SOURCE_ROLES or not all(np.isfinite(v) for v in source.values()):
        raise ValueError('Missing, duplicate or unknown modeled source roles')
    if not np.isfinite(sensible_inventory_plus_pdv):
        raise ValueError('Invalid modeled inventory change')
    external = sum(v for k, v in source.items() if k not in ('SMA_constitutive_in', 'SE_constitutive_in'))
    native_constitutive = source['SMA_constitutive_in'] + source['SE_constitutive_in']
    latent_delta = latent['latent_storage_change_J']
    # Native inventory already includes sensible solid energy. Add latent
    # storage once; never add constitutive heat again as an external input.
    modeled_storage = sensible_inventory_plus_pdv + latent_delta
    pipeline_difference = native_constitutive - latent['command_heat_BE_J']
    residual = external - modeled_storage
    numerical_terms = latent['internal_mechanical_net_J'] + pipeline_difference
    adjusted_residual = external + numerical_terms - modeled_storage
    return dict(external_modeled_heat_BE_J=float(external),
                native_constitutive_heat_BE_J=float(native_constitutive),
                sensible_inventory_plus_pdv_J=float(sensible_inventory_plus_pdv),
                total_inventory_including_latent_plus_pdv_J=float(modeled_storage),
                command_to_native_pipeline_difference_J=float(pipeline_difference),
                external_heat_minus_total_storage_J=float(residual),
                numerical_terms_retained_residual_J=float(adjusted_residual),
                model_equation_energy_closure_pass=bool(
                    abs(residual) <= ENERGY_TOL_J and abs(adjusted_residual) <= ENERGY_TOL_J
                    and abs(pipeline_difference) <= ENERGY_TOL_J
                    and latent['internal_mechanical_cumulative_max_abs_J'] <= ENERGY_TOL_J),
                energy_tolerance_J=ENERGY_TOL_J,
                quadrature='native local backward Euler; measured absolute millisecond intervals',
                latent_heat_counted_once=True, engineering_pump_proxy_added_as_heat=False)


def buffer_cycle_rows(time, arrays, cycle_period=10):
    rows = []
    time=np.asarray(time)
    if cycle_period!=10 or time.ndim!=1 or time.size!=20001:
        raise ValueError('Require the original two-cycle, 1 ms inventory window')
    if set(arrays) != set(BUFFER_NAMES):
        raise ValueError('Require the four physical buffers')
    for name, data in arrays.items():
        for field in ('mass', 'energy', 'temperature', 'mass_flow'):
            values = np.asarray(data[field])
            if values.shape != time.shape or not np.isfinite(values).all():
                raise ValueError('Incomplete physical buffer trace')
        if np.any(data['mass'] <= 0):
            raise ValueError('Nonpositive actual buffer inventory')
        for k in range(2):
            start, stop = time[0]+k*cycle_period, time[0]+(k+1)*cycle_period
            selected = window_indices(time,start,stop)
            m, e, temp = (data[n][selected] for n in ('mass','energy','temperature'))
            transported = integral_summary(data['mass_flow'][selected],time[selected])['BE_energy_J']
            delta = float(m[-1]-m[0])
            stages=[]
            for stage,(begin,end) in enumerate(zip((0,3.5,5,8.5),(3.5,5,8.5,10)),1):
                stage_indices=window_indices(time,start+begin,start+end)
                stages.append(dict(stage=stage,
                    delta_mass_kg=float(data['mass'][stage_indices[-1]]-data['mass'][stage_indices[0]]),
                    transported_mass_BE_kg=integral_summary(
                        data['mass_flow'][stage_indices],time[stage_indices])['BE_energy_J']))
            rows.append(dict(buffer=name, global_cycle=round(stop/cycle_period),
                             absolute_window_s=[float(start),float(stop)],
                             mass_start_kg=float(m[0]),mass_end_kg=float(m[-1]),
                             mass_change_kg=delta,relative_mass_change=delta/float(m[0]),
                             energy_change_J=float(e[-1]-e[0]),
                             temperature_change_K=float(temp[-1]-temp[0]),
                             transported_mass_BE_kg=float(transported),
                             mass_equation_residual_kg=float(transported-delta),
                             local_mass_conservation_pass=abs(transported-delta)<=MASS_TOL_KG,
                             resolved_nonzero_mass_change=abs(delta)>100*MASS_TOL_KG,
                             stages=stages))
    return rows


def chamber_inventory_projection(time, buffers, chambers):
    if set(chambers)!=set(CHAMBER_NAMES):
        raise ValueError('Require both shared connecting chambers')
    rows=[];stage_closure=[]
    for name,data in chambers.items():
        for field in ('mass','temperature','pressure','density'):
            if np.shape(data[field])!=time.shape or not np.isfinite(data[field]).all():
                raise ValueError('Incomplete connecting-chamber trace')
        volume=data['volume_m3']
        if volume<=0 or np.max(abs(data['mass']-data['density']*volume))>MASS_TOL_KG:
            raise ValueError('Connecting chamber mass is not its actual fixed volume times density')
        for k in range(2):
            indices=window_indices(time,time[0]+10*k,time[0]+10*(k+1))
            begin,hot,end=indices[[0,5000,-1]]
            t0,p0=data['temperature'][begin],data['pressure'][begin]
            th,ph=data['temperature'][hot],data['pressure'][hot]
            rho=data['density_table'](np.array([[t0,p0],[th,p0],[th,ph]]))
            dm_T=float(volume*(rho[1]-rho[0]));dm_P=float(volume*(rho[2]-rho[1]))
            dm_actual=float(data['mass'][hot]-data['mass'][begin])
            if abs(dm_T+dm_P-dm_actual)>MASS_TOL_KG:
                raise ValueError('Temperature/pressure density decomposition changed actual mass')
            rows.append(dict(chamber=name,global_cycle=round(time[end]/10),
                volume_m3=float(volume),phase_times_s=time[[begin,hot,end]].tolist(),
                mass_at_phase_points_kg=data['mass'][[begin,hot,end]].tolist(),
                temperature_at_phase_points_K=data['temperature'][[begin,hot,end]].tolist(),
                hot_half_mass_change_kg=dm_actual,
                cooling_half_mass_change_kg=float(data['mass'][end]-data['mass'][hot]),
                full_cycle_mass_change_kg=float(data['mass'][end]-data['mass'][begin]),
                hot_half_mass_change_from_T_at_initial_P_kg=dm_T,
                hot_half_mass_change_from_P_at_final_T_kg=dm_P,
                density_decomposition_exact=True))
    for k in range(2):
        for stage,(a,b) in enumerate(zip((0,3.5,5,8.5),(3.5,5,8.5,10)),1):
            indices=window_indices(time,time[0]+10*k+a,time[0]+10*k+b)
            begin,end=indices[[0,-1]]
            buffer_change=sum(float(x['mass'][end]-x['mass'][begin]) for x in buffers.values())
            chamber_change=sum(float(x['mass'][end]-x['mass'][begin]) for x in chambers.values())
            residual=buffer_change+chamber_change
            stage_closure.append(dict(global_cycle=round((time[0]+10*(k+1))/10),stage=stage,
                buffer_mass_change_kg=buffer_change,chamber_mass_change_kg=chamber_change,
                mass_residual_kg=residual,numerical_closure_pass=abs(residual)<=MASS_TOL_KG))
    return dict(chamber_cycles=rows,stage_mass_exchange=stage_closure,
                buffer_plus_chamber_stage_mass_closure_pass=all(r['numerical_closure_pass'] for r in stage_closure),
                simulation_executed=False,
                interpretation='Actual switched chambers expand/contract their fluid inventory. '
                'The density table separates temperature and pressure contributions without changing the model.')


def audit(root, mechanism_path):
    physics_path=root/'v31_completed_warmup_physics.json'
    execution_path=root/'cold_chamber_execution.json'
    raw_path=root/'native/observations.mat';config_path=root/'native/configuration.mat'
    execution,physics,mechanism=map(read,(execution_path,physics_path,mechanism_path))
    hashes={name:sha256(p) for name,p in dict(execution=execution_path,physics=physics_path,
             mechanism=mechanism_path,observations=raw_path,configuration=config_path).items()}
    if (not execution['requested_arm_collection_pass'] or execution['error_message']
            or physics['producer']!=execution['execution_commit'] or not physics['mechanism_subset_pass']
            or not mechanism['mechanism_pass'] or len(mechanism['checks'])!=73
            or not all(mechanism['checks'].values())
            or mechanism['source_execution_sha256']!=hashes['execution']
            or mechanism['source_observation_sha256']!=hashes['observations']
            or mechanism['source_configuration_sha256']!=hashes['configuration']):
        raise ValueError('Require complete, jointly bound mechanism-passing evidence')
    for relative,expected in physics['input_sha256'].items():
        path=(root/relative.replace('\\','/')).resolve()
        if not path.is_relative_to(root) or sha256(path)!=expected:
            raise ValueError('Changed or escaped ledger input: '+relative)
    ledger=physics['arms'][0]['inventory_ledger']
    if ledger['storage_count']!=119 or ledger['source_count']!=49 or ledger['samples']!=20001:
        raise ValueError('Incomplete modeled component coverage')
    components=ledger['components']
    if len(components)!=119 or len({r['block_path'] for r in components})!=119:
        raise ValueError('Missing or duplicated inventory')
    stop=float(execution['stop_time_s']);start=stop-20
    with h5py.File(config_path) as c:
        coefficients=np.array([float(c['options/equilibrium/'+mass][0,0])*
            float(c['options/material/'+material+'/Delta_h_J_per_kg'][0,0])
            for mass,material in (('m_a_kg','SMA'),('m_r_kg','SE'))])
        if float(c['options/schedule/tau_cycle_s'][0,0])!=10:
            raise ValueError('Unsupported schedule')
    with h5py.File(raw_path) as f:
        signal=f['signals/ECC_constitutive21_output']
        selected=window_indices(signal['time_s'][:],start,stop)
        time=signal['time_s'][:].ravel()[selected]
        phase=np.vstack([signal['values'][a:b,selected[0]:selected[-1]+1].mean(axis=0)
                         for a,b in ((42,63),(63,84))])
        command=np.zeros_like(time)
        for name in ('ECC_Q_SMA_constitutive_W','ECC_Q_SE_constitutive_W'):
            heat=f['signals/'+name]
            heat_indices=window_indices(heat['time_s'][:],start,stop)
            if not np.array_equal(heat['time_s'][:].ravel()[heat_indices],time):
                raise ValueError('Constitutive heat and phase clocks differ')
            command+=heat['values'][:,heat_indices[0]:heat_indices[-1]+1].sum(axis=0)
        latent=latent_decomposition(time,command,phase,coefficients)
        # Independently reevaluate source signs/topology and pressure-source
        # power_spec=none from raw traces rather than trusting source totals.
        thermal_path=root/'native/thermal_connectivity.json'
        rates,sources,pumps=source_ledger(f,read(thermal_path),time,allow_leading_warmup=True)
        if len(sources)+len(pumps)!=49:
            raise ValueError('Incomplete raw source/port coverage')
        source={name:integral_summary(values,time)['BE_energy_J'] for name,values in rates.items()}
        native=normalized_rows(f,'native',start,stop,True)
        arrays={name:{field:scalar_series(native[ROOT+name,key],unit)
                for field,key,unit in (('mass','stored_mass','kg'),('energy','stored_energy','J'),
                    ('temperature','T_I','K'),('mass_flow','mdot_A','kg/s'))}
                for name in BUFFER_NAMES}
        buffers=buffer_cycle_rows(time,arrays)
        meta=read(root/'native/inventory_metadata.json')
        assignment,domains=resolve_domains(read(root/'native/tl_connectivity.json'))
        if domains!=2: raise ValueError('Changed hydraulic domain contract')
        densities={r['block_path']:density_table(r['parameters']) for r in meta['settings_tables']}
        storage={r['block_path']:r for r in meta['storage_blocks']}
        chambers={}
        for name in CHAMBER_NAMES:
            path=ROOT+name
            volume=storage[path]['mask_parameters']['volume']
            if volume['unit']!='m^3': raise ValueError('Unsupported chamber volume unit')
            data={field:scalar_series(native[path,key],unit) for field,key,unit in (
                ('mass','stored_mass','kg'),('temperature','T_I','K'),
                ('pressure','p_I','Pa'),('density','rho_I','kg/m^3'))}
            data.update(volume_m3=volume['value'],density_table=densities[assignment[path]])
            chambers[name]=data
        chamber_projection=chamber_inventory_projection(time,arrays,chambers)
    stock=sum(r['energy_endpoint_change_J']+r.get('pressure_volume_work_J',0) for r in components)
    balance=system_balance(source,stock,latent)
    groups={}
    for r in components:
        groups.setdefault(r['mask_type'],0)
        groups[r['mask_type']]+=r['energy_endpoint_change_J']+r.get('pressure_volume_work_J',0)
    return dict(schema='heatdrive_ecc_coupled_energy_inventory_v1',source_root=str(root),
                total_cycles=execution['cycle_count'],absolute_window_s=[start,stop],
                input_sha256=hashes,source_execution_commit=execution['execution_commit'],
                storage_count=119,source_count=49,source_port_contract_recomputed=True,
                latent_decomposition=latent,modeled_energy_balance=balance,
                source_energy_BE_J=source,storage_group_change_plus_pdv_J=groups,
                raw_pressure_source_work=pumps,buffer_cycles=buffers,
                shared_chamber_inventory=chamber_projection,
                buffer_local_mass_conservation_pass=all(r['local_mass_conservation_pass'] for r in buffers),
                buffer_inventory_migration_observed=any(r['resolved_nonzero_mass_change'] for r in buffers),
                all_physical_inventory_periodic_tolerances_declared=False,
                model_equation_energy_closure_pass=balance['model_equation_energy_closure_pass'],
                full_device_first_law_verified=False,complete_internal_state_periodicity_verified=False,
                simulation_executed=False,operating_point_loaded=False,source_state_edited=False,
                audit_source_sha256=sha256(Path(__file__)),
                audit_execution_commit=subprocess.check_output(
                    ['git','-C',str(Path(__file__).resolve().parent),'rev-parse','HEAD']).decode().strip(),
                production_recovery_allowed=False,outer_solve_eligible=False,table4_reproduction_claim=False,
                interpretation='Modeled thermal+latent equation closure, not experimental validation or real '
                'pump/electrical closure. Local mass conservation is separate from per-buffer cycle stationarity.')


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--experiment-root',type=Path,required=True)
    p.add_argument('--mechanism-audit',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    args=p.parse_args()
    if args.output.exists():
        raise FileExistsError('Never overwrite coupled boundary evidence')
    result=audit(args.experiment_root.resolve(),args.mechanism_audit.resolve())
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({key:result[key] for key in ('total_cycles','model_equation_energy_closure_pass',
        'buffer_local_mass_conservation_pass','buffer_inventory_migration_observed','outer_solve_eligible')}))
