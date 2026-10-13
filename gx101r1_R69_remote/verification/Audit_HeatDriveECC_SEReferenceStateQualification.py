"""Bind paired C2 checkpoints, full mechanism checks and all-cycle SE mass transport."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Analyze_HeatDriveECC_SECommutationInventory import partition
from Analyze_HeatDriveECC_SEReferenceCounterfactual import controller_contract
from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_CoupledEnergyInventory import ROOT,latent_decomposition,system_balance
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def read(path):return json.loads(path.read_text(encoding='utf-8'))


def verified_case(folder,physics_path,manifest_case):
    execution=read(folder/'cold_chamber_execution.json');physics=read(physics_path)
    if (sha256(folder/'cold_chamber_execution.json')!=manifest_case['execution_sha256'] or
            not execution['checkpoint_saved'] or not execution['state_restore_preflight_pass'] or
            execution['error_message'] or execution['start_time_s']!=0 or execution['stop_time_s']!=20 or
            not physics['mechanism_subset_pass'] or physics['producer']!=execution['execution_commit']):
        raise ValueError('Require complete and source-bound C2 physics/state evidence')
    for relative,expected in physics['input_sha256'].items():
        path=(folder/relative.replace('\\','/')).resolve()
        if not path.is_relative_to(folder) or sha256(path)!=expected:
            raise ValueError('Changed or escaped physics input')
    arm=folder/'native';mechanism=read(arm/'cold_mechanism_audit.json')
    if (not mechanism['mechanism_pass'] or len(mechanism['checks'])!=73 or not all(mechanism['checks'].values()) or
            sha256(arm/'cold_mechanism_observation.mat')!=mechanism['observation_sha256']):
        raise ValueError('Original full 73-check mechanism audit is not passing/bound')
    capture=read(arm/'diagnostic_state_capture.json');restore=read(arm/'state_restore_preflight.json')
    if (not restore['same_model_restore_preflight_pass'] or restore['checksum_policy']!='error/error' or
            restore['source_state_edited'] or restore['partial_state_restore_used'] or
            restore['complete_cycle_resume_verified'] or capture['snapshot_time_s']!=20 or
            sha256(arm/'diagnostic_complete_operating_point.mat')!=capture['operating_point_sha256'] or
            sha256(arm/'diagnostic_state_observation.mat')!=capture['history_sha256']):
        raise ValueError('Intact strict same-model disk restore is missing or overstated')
    time=np.arange(20001)*.001
    with h5py.File(arm/'observations.mat') as f,h5py.File(arm/'configuration.mat') as cfg:
        rows=named_rows(f,f['native']);budgets={}
        for name in ('ColdFluidBuffer','HotFluidBuffer','SMAHotFluidBuffer','SHEXFluidBuffer'):
            mass=scalar_series(rows[ROOT+name,'stored_mass'],'kg')
            flow=scalar_series(rows[ROOT+name,'mdot_A'],'kg/s')
            budgets[name]=partition(time,mass,flow,float(cfg['options/branch/stage_command_ramp_s'][0,0]))
        state=f['signals/ECC_constitutive21_output/values'][:]
        phase=np.vstack([state[a:b].mean(axis=0) for a,b in ((42,63),(63,84))])
        command=sum(f['signals/'+name+'/values'][:].sum(axis=0)
            for name in ('ECC_Q_SMA_constitutive_W','ECC_Q_SE_constitutive_W'))
        coefficients=np.array([float(cfg['options/equilibrium/'+mass][0,0])*
            float(cfg['options/material/'+material+'/Delta_h_J_per_kg'][0,0])
            for mass,material in (('m_a_kg','SMA'),('m_r_kg','SE'))])
        latent=latent_decomposition(time,command,phase,coefficients)
        names=('distributed_pressure_envelope','distributed_target_flow_kg_s','stage4_target_flow_command',
            'stage4_integrator_output_gate','stage4_integrator_state')
        signals={name:f['signals/'+name+'/values'][:].ravel() for name in names}
        controller=(controller_contract(time,signals,read(arm/'se_reference_contract.json'))
                    if (arm/'se_reference_contract.json').exists() else None)
    ledger=physics['arms'][0]['inventory_ledger']
    balance=system_balance({name:data['BE_energy_J'] for name,data in ledger['source_ledger'].items()},
        ledger['actual_endpoint_storage_plus_pdv_J'],latent)
    summary=[]
    for name,stages in budgets.items():
        for cycle in (1,2):
            selected=[row for row in stages if row['global_cycle']==cycle]
            summary.append(dict(buffer=name,cycle=cycle,
                total_mass_change_kg=sum(row['endpoint_mass_change_kg'] for row in selected),
                nominal_active_stage_mass_change_kg=sum(row['endpoint_mass_change_kg'] for row in selected if row['stage'] in (2,4)),
                nominal_inactive_stage_mass_change_kg=sum(row['endpoint_mass_change_kg'] for row in selected if row['stage'] in (1,3))))
    return dict(physical_input_hashes_verified=True,mechanism_checks_passed=73,
        mechanism_audit_sha256=sha256(arm/'cold_mechanism_audit.json'),
        physics_sha256=sha256(physics_path),OP_sha256=capture['operating_point_sha256'],
        history_sha256=capture['history_sha256'],source_observation_sha256=sha256(arm/'observations.mat'),
        state_restore_sha256=sha256(arm/'state_restore_preflight.json'),
        state_restore_comparison_counts=dict(states=len(restore['state_comparisons']),signals=len(restore['signal_comparisons'])),
        modeled_energy_balance=balance,full_mechanism_pass=True,mechanism_subset_pass=True,
        mass_summaries=summary,stage_mass_partitions=budgets,controller_equations=controller,
        complete_cycle_restore_verified=False,periodic_steady_state=False,production_recovery_allowed=False,
        temperature_drift=physics['arms'][0]['storage_drift']['worst_temperature_endpoint_K'])


def audit(root,baseline_physics,coherent_physics):
    manifest=read(root/'state_qualification_execution.json')
    if manifest['status']!='collected_requires_physical_and_complete_cycle_restore_audit' or manifest['existing_OP_imported']:
        raise ValueError('Incomplete or incorrectly initialized qualification study')
    folders=[Path(path).resolve() for path in manifest['case_roots']]
    if len(folders)!=2:raise ValueError('Missing paired C2 chains')
    if read(folders[0]/'native/inventory_metadata.json')!=read(folders[1]/'native/inventory_metadata.json'):
        raise ValueError('Geometry, property or initial targets changed')
    cases=[verified_case(folder,path,record) for folder,path,record in
        zip(folders,(baseline_physics,coherent_physics),manifest['cases'])]
    values=[next(row['total_mass_change_kg'] for row in case['mass_summaries']
        if row['buffer']=='ColdFluidBuffer' and row['cycle']==2) for case in cases]
    return dict(schema='heatdrive_ecc_se_reference_state_qualification_audit_v1',
        source_root=str(root),manifest_sha256=sha256(root/'state_qualification_execution.json'),
        cases=cases,C2_Cold_mass_change_kg=values,
        C2_Cold_mass_imbalance_reduction_fraction=1-abs(values[1]/values[0]),
        OP20_is_intact_diagnostic_checkpoint=True,complete_cycle_restore_verified=False,
        diagnostic_warmup_continuation_allowed=False,production_recovery_allowed=False,outer_solve_eligible=False,
        periodic_steady_state=False,table4_reproduction_claim=False,
        interpretation='Both tails are included in cycle2. Same-model one-step restore does not '
        'grant rebuilt ten-second cycle recovery. The residual mass drift and SMA migration still require work.')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--study-root',type=Path,required=True)
    parser.add_argument('--baseline-physics',type=Path,required=True)
    parser.add_argument('--coherent-physics',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():raise FileExistsError('Never overwrite a state qualification audit')
    result=audit(args.study_root.resolve(),args.baseline_physics.resolve(),args.coherent_physics.resolve())
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({'C2_Cold_mass_change_kg':result['C2_Cold_mass_change_kg'],
        'reduction_fraction':result['C2_Cold_mass_imbalance_reduction_fraction'],
        'energy_closure':[case['modeled_energy_balance']['model_equation_energy_closure_pass'] for case in result['cases']],
        'mechanism_counts':[case['mechanism_checks_passed'] for case in result['cases']],
        'checkpoint_hashes':[case['OP_sha256'] for case in result['cases']],
        'complete_cycle_restore_verified':False,'outer_solve_eligible':False}))
