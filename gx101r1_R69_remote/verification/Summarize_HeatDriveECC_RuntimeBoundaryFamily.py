"""Quantify actual model-family equivalence and boundary changes without inventing new gates."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Close_HeatDriveECC_SplitObservation import read,validate_gate
from Analyze_HeatDriveECC_CoolingBoundaryReconciliation import stage_ids,integrals


def delta(a,b):
    a,b=np.asarray(a),np.asarray(b)
    if a.shape!=b.shape or not np.isfinite(a).all() or not np.isfinite(b).all():
        raise ValueError('Incomplete observed coordinate')
    return dict(max_abs_difference=float(abs(a-b).max()),rms_difference=float(np.sqrt(np.mean((a-b)**2))),
                bitwise_equal=bool(np.array_equal(a.view(np.uint64),b.view(np.uint64))),physical_threshold_imposed=False)


def cold_metrics(family,reference,output):
    if output.exists():raise FileExistsError('Never overwrite the cold metric comparison')
    records=[]
    for root in (reference,family/'cold_C002'):
        with h5py.File(root/'native/observations.mat') as f,h5py.File(root/'native/configuration.mat') as cfg:
            t=f['signals/SMA_Tx21_internal/time_s'][:].ravel();o=cfg['options']
            if len(t)!=20001 or abs(t[0])>1e-9 or abs(t[-1]-20)>1e-9:raise ValueError('Different cold metric window')
            s=stage_ids(t,float(o['cycle_count'][0,0]),o['schedule/stage_start_s'][:].ravel(),o['schedule/stage_end_s'][:].ravel())
            signal=lambda name:f['signals/'+name+'/values'][:].sum(axis=0)
            cp=float(o['system/cp_fluid_J_per_kgK'][0,0])
            q=abs(signal('mass_flow_v4_hot_inlet_kgps'))*(s==4)*cp*(
                signal('cold_hx_inlet_fluid_temp_out')-signal('cold_hx_outlet_fluid_temp_out'))
            lift=signal('hot_hx_inlet_fluid_temp_out')-signal('cold_hx_inlet_fluid_temp_out')
            records.append(dict(observation_sha256=sha256(root/'native/observations.mat'),
                lift_K=integrals(t,lift)['trapz_J']/20,cooling_W=integrals(t,q)['trapz_J']/20))
    record=dict(schema='heatdrive_ecc_runtime_boundary_cold_metric_comparison_v1',window_s=[0,20],
        compiletime=records[0],runtime=records[1],lift_difference_K=records[1]['lift_K']-records[0]['lift_K'],
        cooling_difference_W=records[1]['cooling_W']-records[0]['cooling_W'],
        common_absolute_stage_mask=True,quadrature='trapz_both_endpoints',
        interpretation='Two-cycle cold comparison, not a ten-cycle steady endpoint or validation',
        outer_solve_eligible=False,table4_reproduction_claim=False)
    output.write_text(json.dumps(record,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    return record


def summarize(family,reference,reference_audit,recipe,output):
    if output.exists():raise FileExistsError('Never overwrite family evidence')
    result=read(family/'runtime_boundary_family.json');proof=read(reference_audit);configuration=read(recipe)
    cold=family/'cold_C002';gate=read(cold/'packet_gate.json');validate_gate(gate)
    if (not result['experiment_completed'] or not result['same_family_parameter_compatible'] or
            not result['cold_baseline_all_original_gates_pass'] or result['old_complete_state_imported']):
        raise ValueError('Require completed, physically gated family and source')
    if (not proof['full_mechanism_pass'] or not proof['modeled_energy_balance']['model_equation_energy_closure_pass'] or
            Path(proof['source_root']).resolve()!=reference.resolve()):
        raise ValueError('The old cold reference is not independently qualified')
    old,new=reference/'native/observations.mat',cold/'native/observations.mat'
    if sha256(old)!=proof['runtime_mechanism_subset']['observation_sha256']:
        raise ValueError('Old cold observation changed')
    if (configuration['reference_configuration_sha256']!=sha256(reference/'native/configuration.mat') or
            configuration['candidate_configuration_sha256']!=sha256(cold/'native/configuration.mat')):
        raise ValueError('Recipe comparison is not bound to these observations')
    manifest=read(cold/'packet_manifest.json')
    for row in manifest['input_files']:
        if sha256(cold/row['path'])!=row['sha256']:raise ValueError('Changed cold evidence')
    if sha256(Path(result['baseline_complete_OP_path']))!=result['baseline_complete_OP_sha256']:
        raise ValueError('Baseline OP changed')
    trajectories=[]
    with h5py.File(old) as a,h5py.File(new) as b:
        x,y=named_rows(a,a['native']),named_rows(b,b['native'])
        if set(x)!=set(y) or len(x)!=1262:raise ValueError('Missing native identities')
        for key in x:
            variable=key[1]
            if variable not in ('T','T_I','stored_mass','stored_energy'):continue
            unit='K' if variable in ('T','T_I') else 'kg' if variable=='stored_mass' else 'J'
            ta,tb=x[key]['time_s'][:].ravel(),y[key]['time_s'][:].ravel()
            if len(ta)!=20001 or len(tb)!=20001 or np.max(abs(ta-tb))>16*np.spacing(20.):raise ValueError('Native clocks changed')
            trajectories.append(dict(block_path=key[0],variable=variable,unit=unit,
                **delta(scalar_series(x[key],unit),scalar_series(y[key],unit))))
        public=[]
        for name in ('SMA_Tx21_internal','SE_Tx21_internal','ECC_constitutive21_output'):
            va,vb=a['signals/'+name+'/values'][:],b['signals/'+name+'/values'][:]
            if name=='ECC_constitutive21_output':va,vb=va[42:84],vb[42:84]
            public.append(dict(signal=name,unit='1' if name.startswith('ECC_') else 'K',**delta(va,vb)))
    perturbation=family/'runtime_Tc_candidate/measured_probe.mat'
    impacts=[]
    with h5py.File(new) as a,h5py.File(perturbation) as b:
        x,y=named_rows(a,a['native']),named_rows(b,b['native'])
        for key in x:
            if key[1] not in ('T','T_I','stored_mass','stored_energy'):continue
            unit='K' if key[1] in ('T','T_I') else 'kg' if key[1]=='stored_mass' else 'J'
            impacts.append(dict(block_path=key[0],variable=key[1],unit=unit,
                **delta(scalar_series(x[key],unit)[-1:],scalar_series(y[key],unit)[:1])))
        fixed=next(key[0] for key in x if key[0].endswith('/ColdSinkMass'))
        temperature_before=float(scalar_series(x[fixed,'T'],'K')[-1]);temperature_after=float(scalar_series(y[fixed,'T'],'K')[0])
        q=float(scalar_series(y[fixed,'Q'],'W')[0])
    meta=read(cold/'native/inventory_metadata.json')
    block=next(row for row in meta['storage_blocks'] if row['block_path']==fixed)
    parameters=block['mask_parameters']
    if parameters['mass']['unit']!='kg' or parameters['sp_heat']['unit'] not in ('J/(K*kg)','J/(kg*K)'):
        raise ValueError('Thermal mass capacity units changed')
    capacity=parameters['mass']['value']*parameters['sp_heat']['value']
    jump=capacity*(temperature_after-temperature_before)
    record=dict(schema='heatdrive_ecc_runtime_boundary_family_measurements_v1',source_producer=result['producer'],
        source_family=str(family),actual_baseline_window_s=[0,20],cold_baseline_all_original_gates_pass=True,
        same_family_boundary_parameter_compatible=True,recipe_comparison=configuration,
        baseline_trajectory_comparison=trajectories,baseline_public_comparison=public,
        candidate_initial_coordinate_changes=impacts,
        imposed_CHEX_storage_jump=dict(capacity_J_per_K=capacity,delta_temperature_K=temperature_after-temperature_before,
            stored_energy_jump_J=jump,first_native_mass_heat_W=q,first_BE_step_product_J=q*.001,
            source_heat_impulse_directly_measured=False,
            interpretation='Prescribed-temperature boundary action, not a manual reset. Keep the transition outside the steady analysis window.'),
        all_four_retained_memories_initial_bitwise_equal=result['cases'][1]['retained_memories_initial_bitwise_equal'],
        input_sha256=dict(family=sha256(family/'runtime_boundary_family.json'),reference_audit=sha256(reference_audit),
            reference_observation=sha256(old),runtime_observation=sha256(new),perturbation=sha256(perturbation),recipe=sha256(recipe)),
        physical_tolerances_changed=False,old_model_OP_migration_performed=False,
        periodic_steady_state_claim=False,production_recovery_allowed=False,outer_solve_eligible=False,table4_reproduction_claim=False)
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(record,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    maxima={unit:max(row['max_abs_difference'] for row in trajectories if row['unit']==unit) for unit in ('K','kg','J')}
    return dict(baseline_coordinate_count=len(trajectories),maximum_baseline_differences=maxima,
        public=public,only_declared_recipe_change=configuration['only_declared_change'],boundary_energy_jump_J=jump)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('family','reference','reference-audit','recipe','output'):
        parser.add_argument('--'+name,required=True,type=Path)
    parser.add_argument('--metrics-only',action='store_true');args=vars(parser.parse_args());metrics=args.pop('metrics_only')
    print(json.dumps(cold_metrics(args['family'],args['reference'],args['output']) if metrics else summarize(**args),indent=2))
