"""Audit actual cold factorial data, retaining original gates and coordinate diagnostics."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdBufferCoupled import cycle_arm,port_contract
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_CoupledEnergyInventory import latent_decomposition,system_balance
from Audit_HeatDriveECC_DistributedPressureRuntime import audit_arm
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_TLDomainInventory import resolve_domains


ROOT='heatdrive_ecc_coupled_se21/'
NAMES=('baseline_legacy','baseline_tight','sma_pipe_legacy','sma_pipe_tight')


def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))


def gate_coordinates(time,port_hot,internal_hot,port_shex,internal_shex,front,solid_max,
                     route_flow,ambient,source,flow_threshold):
    arrays=[np.asarray(v,dtype=float) for v in (time,port_hot,internal_hot,port_shex,internal_shex,
                                                front,solid_max,route_flow)]
    time,port_hot,internal_hot,port_shex,internal_shex,front,solid_max,route_flow=arrays
    if any(v.shape!=time.shape for v in arrays) or not np.isfinite(arrays).all():
        raise ValueError('Invalid aligned physical coordinate diagnostic')
    hot_half=time<5;ambient_half=(time>=5)&(time<10)
    hot=front>=ambient+10;stage3=(time>=5)&(time<8.5)
    flowing=abs(route_flow)>flow_threshold
    def peak_rise(values):return float(values[hot_half].max()-values[hot_half][0])
    return dict(hot_half_HHEX_port_rise_K=peak_rise(port_hot),
        hot_half_HHEX_internal_rise_K=peak_rise(internal_hot),
        ambient_half_SHEX_port_above_source_K=float(port_shex[ambient_half].max()-source),
        ambient_half_SHEX_internal_above_source_K=float(internal_shex[ambient_half].max()-source),
        hot_front_samples=int(hot.sum()),hot_front_outside_stage3_samples=int((hot&~stage3).sum()),
        hot_front_outside_stage3_flowing_samples=int((hot&~stage3&flowing).sum()),
        max_abs_flow_at_outside_stage3_hot_front_kg_s=float(abs(route_flow[hot&~stage3]).max(initial=0)),
        hot_front_above_current_solid_plus2_samples=int((hot&(front>solid_max+2)).sum()),
        flowing_hot_front_above_current_solid_plus2_samples=int((hot&flowing&(front>solid_max+2)).sum()),
        flow_threshold_kg_s=float(flow_threshold),original_thresholds_unchanged=True,
        replacement_gate_assigned=False)


def audit(root):
    study=read(root/'factorial_execution.json')
    if (not study['collection_pass'] or len(study['cases'])!=4 or
            any(study[k] for k in ('C200_state_loaded','C62_state_loaded','source_state_edited','production_recovery_allowed')) or
            [r['name'] for r in study['cases']]!=list(NAMES) or study['command_horizon_cycles']!=1):
        raise ValueError('Require four independent completed cold trajectories')
    results={};common=None;initial={};topology_edges=None
    for row in study['cases']:
        folder=Path(row['source_root']);arm=folder/'native'
        if folder.parent.resolve()!=root or sha256(Path(row['config_path']))!=row['config_sha256'] or \
                sha256(folder/'cold_chamber_execution.json')!=row['execution_sha256']:
            raise ValueError('Changed or escaped case')
        config=read(Path(row['config_path']));execution=read(folder/'cold_chamber_execution.json')
        shared={k:v for k,v in config.items() if k not in ('output_root','diagnostic_buffer_factor_options')}
        if common is None:common=shared
        if shared!=common or not execution['requested_arm_collection_pass'] or execution['checkpoint_saved'] or \
                execution['c200_state_imported'] or execution['error_message'] or execution['start_time_s']!=0 or execution['stop_time_s']!=10:
            raise ValueError('Cold matrix common-state/command contract changed')
        factors=read(arm/'buffer_factor_contract.json')
        if (sha256(arm/'buffer_factor_contract.json')!=execution['buffer_factor_contract_sha256'] or
                factors['factor_options']!=config['diagnostic_buffer_factor_options'] or
                not factors['BE_and_time_step_unchanged'] or not factors['initial_inventory_targets_unchanged'] or
                not factors['material_constitutive_PI_unchanged'] or factors['source_state_imported']):
            raise ValueError('Wrong physical intervention scope')
        contracts={r['block_path']:r for r in read(arm/'buffer_replacement_contract.json')['buffers']}
        metadata={b['block_path']:b for b in read(arm/'inventory_metadata.json')['storage_blocks']}
        for changed in factors['buffer_geometry']:
            block=changed['block_path'];actual=changed['actual_port_area_m2']
            expected=(np.pi*.0032**2/4 if row['geometry']=='sma_pipe_matched' and
                      block.rsplit('/',1)[-1] in ('SHEXFluidBuffer','SMAHotFluidBuffer') else .01)
            if (not np.isclose(actual,expected,rtol=0,atol=1e-20) or
                    metadata[block]['mask_parameters']['port_area']['value']!=actual or
                    changed['before_inventory_parameters']!=changed['after_inventory_parameters']):
                raise ValueError('Actual port or initial inventories differ from declared factor')
            port_contract(contracts[block])
            contracts[block]=dict(contracts[block],port_area_m2=actual)
        topology=read(arm/'tl_connectivity.json');assignment,domains=resolve_domains(topology)
        edges=topology['edges']
        if topology_edges is None:topology_edges=edges
        if edges!=topology_edges or domains!=2:raise ValueError('Undeclared network topology change')
        runtime=audit_arm(arm,0,10)
        ledger=cycle_arm(arm,assignment,contracts,mass_formulation='zero_based_offset',pressure_only_density=True)
        mechanism=read(arm/'cold_mechanism_audit.json')
        if (mechanism['execution_commit']!=execution['execution_commit'] or len(mechanism['checks'])!=73 or
                sha256(arm/'cold_mechanism_observation.mat')!=mechanism['observation_sha256']):
            raise ValueError('Original mechanism evidence changed')
        local=[]
        for component in ledger['components']:
            if component['mask_type']=='Conservative Buffer (TL)':
                local.append(dict(block=component['block_path'],passed=component['component_detail']['candidate_component_pass'],
                                  detail=component['component_detail']['independent_ledger']))
            elif 'local_chamber_gate' in component:
                detail=component['local_chamber_gate']
                local.append(dict(block=component['block_path'],passed=detail['mass_closure_pass'] and detail['energy_closure_pass'],detail=detail))
        with h5py.File(arm/'observations.mat') as f,h5py.File(arm/'configuration.mat') as cfg:
            native=named_rows(f,f['native']);time=f['signals/SMA_Tx21_internal/time_s'][:].ravel()
            signal=lambda name:f['signals/'+name+'/values'][:].ravel()
            get=lambda block,name,unit:scalar_series(native[ROOT+block,name],unit)
            coordinates=gate_coordinates(time,signal('sma_hot_buffer_temp_out'),get('SMAHotFluidBuffer','T_I','K'),
                signal('shex_buffer_temp_out'),get('SHEXFluidBuffer','T_I','K'),
                signal('hhex_sma_branch_outlet_fluid_temp_out'),f['signals/SMA_Tx21_internal/values'][:].max(axis=0),
                signal('mass_flow_sma_stage3_route_kgps'),float(cfg['options/system/Thhex_K'][0,0]),
                float(cfg['options/system/Tshex_source_K'][0,0]),
                float(cfg['options/validation/min_active_flow_fraction_of_target'][0,0])*
                np.mean([float(cfg['options/branch/'+key][0,0]) for key in
                         ('m_dot_sma_shex_kg_per_s','m_dot_sma_the_kg_per_s')]))
            constitutive=f['signals/ECC_constitutive21_output/values'][:]
            phase=np.vstack([constitutive[a:b].mean(axis=0) for a,b in ((42,63),(63,84))])
            command=sum(f['signals/'+name+'/values'][:].sum(axis=0) for name in ('ECC_Q_SMA_constitutive_W','ECC_Q_SE_constitutive_W'))
            coefficients=np.array([float(cfg['options/equilibrium/'+mass][0,0])*
                float(cfg['options/material/'+material+'/Delta_h_J_per_kg'][0,0])
                for mass,material in (('m_a_kg','SMA'),('m_r_kg','SE'))])
            balance=system_balance({k:v['BE_energy_J'] for k,v in ledger['source_ledger'].items()},
                ledger['actual_endpoint_storage_plus_pdv_J'],latent_decomposition(time,command,phase,coefficients))
            initial[row['name']]={(block,var):float(scalar_series(r,unit)[0]) for (block,var),r in native.items()
                for unit in [{'T_I':'K','T':'K','stored_mass':'kg','mass_offset':'kg','stored_energy':'J'}.get(var)] if unit}
        results[row['name']]=dict(original_mechanism_pass=mechanism['mechanism_pass'],failed_original_checks=mechanism['failed_checks'],
            runtime=runtime,local_inventory=local,all_six_local_inventory_pass=len(local)==6 and all(r['passed'] for r in local),
            modeled_energy_balance=balance,gate_coordinate_diagnostics=coordinates,
            buffer_energy_changes_J={r['block_path'].rsplit('/',1)[-1]:r['energy_endpoint_change_J'] for r in ledger['components']
                if r['mask_type']=='Conservative Buffer (TL)'},performance=ledger['performance'],
            input_sha256={name:sha256(arm/name) for name in ('observations.mat','configuration.mat','inventory_metadata.json',
                'buffer_factor_contract.json','cold_mechanism_audit.json','buffer_replacement_contract.json')})
    comparisons={}
    baseline=initial['baseline_legacy']
    for name,data in initial.items():
        if set(data)!=set(baseline):raise ValueError('Initial native coordinate coverage changed')
        comparisons[name]={var:max(abs(data[k]-baseline[k]) for k in data if k[1]==var)
                           for var in ('T_I','T','stored_mass','mass_offset','stored_energy')}
    return dict(schema='heatdrive_ecc_cold_buffer_factorial_audit_v1',source_root=str(root),cases=results,
        actual_initial_coordinate_differences_from_baseline=comparisons,
        common_model_control_recipe_verified=True,only_declared_geometry_precision_changed=True,
        original_gates_preserved=True,coordinate_review_is_not_a_gate_relaxation=True,
        candidate_seed_selected=False,production_recovery_allowed=False,outer_solve_eligible=False,
        table4_reproduction_claim=False,input_sha256={'factorial_execution':sha256(root/'factorial_execution.json')})


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--experiment-root',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():raise FileExistsError('Never overwrite factorial evidence')
    result=audit(args.experiment_root.resolve())
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({name:{k:row[k] for k in ('original_mechanism_pass','failed_original_checks',
        'all_six_local_inventory_pass','modeled_energy_balance','gate_coordinate_diagnostics','buffer_energy_changes_J','performance')}
        for name,row in result['cases'].items()},indent=2))
