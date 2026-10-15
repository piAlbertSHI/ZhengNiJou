"""Preserve legacy outcomes while correcting two physically mismatched gate coordinates."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_BufferColdFactorial import read,ROOT
from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def corrected_checks(stage,hot_internal,shex_internal,front,solid_max,route_flow,ambient,source,
                     flow_threshold,hot_rise_limit,shex_excess_limit):
    arrays=[np.asarray(v) for v in (stage,hot_internal,shex_internal,front,solid_max,route_flow)]
    stage,hot_internal,shex_internal,front,solid_max,route_flow=arrays
    if (stage.ndim!=1 or any(v.shape!=stage.shape for v in arrays) or
            not np.isfinite(arrays).all() or not np.isin(stage,[1,2,3,4]).all() or
            not np.isfinite([ambient,source,flow_threshold,hot_rise_limit,shex_excess_limit]).all() or
            flow_threshold<=0 or min(hot_rise_limit,shex_excess_limit)<0):
        raise ValueError('Require complete physical coordinates and unchanged positive limits')
    hot_half=np.isin(stage,[1,2]);ambient_half=np.isin(stage,[3,4])
    if not hot_half.any() or not ambient_half.any():raise ValueError('Incomplete half-cycle coverage')
    rise=float(hot_internal[hot_half].max()-hot_internal[hot_half][0])
    excess=float(shex_internal[ambient_half].max()-source)
    active=abs(route_flow)>flow_threshold
    flowing_hot=(front>=ambient+10)&active
    return dict(SMA_buffer_cross_contamination=bool(rise<=hot_rise_limit and excess<=shex_excess_limit),
        SMA_stage3_HHEX_hot_front_physical=bool(flowing_hot.any() and np.all(stage[flowing_hot]==3) and
                                              np.all(front[flowing_hot]<=solid_max[flowing_hot]+2))), \
        dict(actual_internal_hot_half_rise_K=rise,actual_internal_shex_excess_K=excess,
             hot_rise_limit_K=float(hot_rise_limit),shex_excess_limit_K=float(shex_excess_limit),
             existing_flow_activity_threshold_kg_s=float(flow_threshold),
             flowing_hot_front_samples=int(flowing_hot.sum()),
             inactive_hot_front_samples=int(((front>=ambient+10)&~active).sum()))


def review(audit_path):
    audited=read(audit_path);root=Path(audited['source_root']);study=read(root/'factorial_execution.json')
    if sha256(root/'factorial_execution.json')!=audited['input_sha256']['factorial_execution']:
        raise ValueError('Changed physical matrix')
    results={}
    for entry in study['cases']:
        name=entry['name'];folder=Path(entry['source_root'])/'native';evidence=audited['cases'][name]
        for file,expected in evidence['input_sha256'].items():
            if sha256(folder/file)!=expected:raise ValueError('Changed physical evidence: '+name+'/'+file)
        original=read(folder/'cold_mechanism_audit.json')
        with h5py.File(folder/'cold_mechanism_observation.mat') as view,h5py.File(folder/'observations.mat') as f, \
                h5py.File(folder/'configuration.mat') as cfg:
            if sha256(folder/'cold_mechanism_observation.mat')!=original['observation_sha256']:
                raise ValueError('Original physical view changed')
            physical=view['physical'];time=physical['time_s'][:].ravel()
            if not np.array_equal(time,f['signals/SMA_Tx21_internal/time_s'][:].ravel()):
                raise ValueError('Native/public/physical clocks differ')
            native=named_rows(f,f['native'])
            def internal(name):
                row=native[ROOT+name,'T_I']
                if not np.array_equal(time,row['time_s'][:].ravel()):raise ValueError('Internal temperature clock differs')
                return scalar_series(row,'K')
            scalar=lambda key:float(cfg['options/'+key][0,0])
            target=np.mean([scalar('branch/'+key) for key in ('m_dot_sma_shex_kg_per_s','m_dot_sma_the_kg_per_s')])
            front=physical['probes/hhex_sma_branch_outlet_fluid_temp_out'][:].ravel()
            solid=f['signals/SMA_Tx21_internal/values'][:].max(axis=0)
            replacements,details=corrected_checks(physical['stage_id'][:].ravel(),
                internal('SMAHotFluidBuffer'),internal('SHEXFluidBuffer'),front,solid,
                physical['mdot_SMA_stage3_route_kgps'][:].ravel(),scalar('system/Thhex_K'),scalar('system/Tshex_source_K'),
                scalar('validation/max_inactive_SMA_route_flow_fraction')*target,
                scalar('validation/max_stage1_HHEX_SMA_buffer_rise_K'),scalar('validation/max_stage3_SHEX_buffer_above_source_K'))
        checks=dict(original['checks']);checks.update(replacements)
        untouched={k:v for k,v in original['checks'].items() if k not in replacements}
        assert len(untouched)==71 and all(checks[k]==v for k,v in untouched.items())
        results[name]=dict(original_mechanism_pass=original['mechanism_pass'],original_failed_checks=original['failed_checks'],
            corrected_checks=checks,coordinate_corrected_mechanism_pass=all(checks.values()),
            corrected_failed_checks=[k for k,v in checks.items() if not v],
            untouched_original_predicate_count=71,corrected_predicate_count=2,coordinate_details=details,
            original_rejection_marker_preserved=(folder.parent/'REJECTED_DO_NOT_RESUME.json').exists(),
            local_inventory_pass=evidence['all_six_local_inventory_pass'],
            modeled_energy_pass=evidence['modeled_energy_balance']['model_equation_energy_closure_pass'],
            no_old_endpoint_imported=True,old_failed_point_recovery_allowed=False)
    return dict(schema='heatdrive_ecc_buffer_coordinate_gate_review_v1',source_root=str(root),cases=results,
        correction_basis=['Buffer contamination uses native material-control-volume T_I, not conserving-port stream temperature',
            'Advective hot-front timing/solid bound counts every flow above the existing permitted inactive-SMA-route leakage ceiling, not the much larger minimum-active-flow target',
            'Ten-K hot-front onset, two-K solid bound, five-/three-K buffer limits and other 71 predicates unchanged',
            'Inactive conduction/heat exchange remains included in original route/isolation and explicit M/E ledgers'],
        original_predicate_report_is_immutable=True,amplitude_tolerances_changed=False,
        production_validator_modified=False,simulation_executed=False,operating_point_edited=False,
        new_cold_followup_qualified=False,production_recovery_allowed=False,outer_solve_eligible=False,
        table4_reproduction_claim=False,input_sha256={'factorial_audit':sha256(audit_path)})


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--factorial-audit',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():raise FileExistsError('Never overwrite coordinate review')
    result=review(args.factorial_audit.resolve())
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({name:{k:r[k] for k in ('original_mechanism_pass','coordinate_corrected_mechanism_pass',
        'corrected_failed_checks','coordinate_details')} for name,r in result['cases'].items()},indent=2))
