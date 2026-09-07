"""Audit independent friction and port-length interventions with original gates."""
import argparse
import json
from pathlib import Path

from Audit_HeatDriveECC_ChamberStepConvergence import PHYSICAL_SHA, TOPOLOGY_SHA
from Audit_HeatDriveECC_DualChamberSwitchResult import read_case, audit_case
from Audit_HeatDriveECC_DualPipeResult import momentum_audit, verify_parameters
from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--mode',choices=['no_friction_long_port','friction_short_port','no_friction_short_port'],required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite ablation evidence')
    base=args.repo/'outputs_storage_audit'
    root=base/f'ablation_{args.mode}_20260907/trial'
    trial_path=root/'dual_switch_result.json'
    trial=json.loads(trial_path.read_text(encoding='utf-8-sig'))
    topology=base/'tl_domain_energy_tables_20260906/tl_domain_metadata.json'
    component=root/'build/+ecc_inventory/conservative_chamber.ssc'
    source=args.repo/'verification/simscape_inventory_ablation/+ecc_inventory/conservative_chamber.ssc'
    scale=1 if args.mode=='friction_short_port' else 0
    port_length=.0032 if args.mode.endswith('short_port') else .1
    if (trial['schema']!='heatdrive_ecc_dual_chamber_switch_trial_v8' or not trial['collection_pass']
            or len(trial['cases'])!=6 or trial['failed_cases'] or trial['ablation_mode']!=args.mode
            or trial['friction_scale']!=scale or trial['convection_length_m']!=port_length
            or trial['valve_transition_s']!=0 or trial['production_model_changed'] or trial['production_checkpoint_loaded']
            or trial['production_recovery_allowed'] or sha256(component)!=sha256(source)
            or sha256(topology)!=TOPOLOGY_SHA or sha256(Path(trial['source_options_path']))!=PHYSICAL_SHA):
        raise ValueError('Ablation input or scope changed')
    water=next(r for r in json.loads(topology.read_text(encoding='utf-8-sig'))['settings_tables']
               if r['block_path'].endswith('/SMA_ThermalLiquidSettings'))
    table=energy_tables(water['parameters'])
    rows=[]
    hashes=dict(trial=sha256(trial_path),component=sha256(component),topology=sha256(topology))
    for i,(power,step) in enumerate([(p,s) for p in ('none','isentropic') for s in (.001,.0005,.00025)],1):
        path=root/f'case_{i}.mat'
        meta,t,p=read_case(path,finite_transition=True,pipe_model=True)
        if (meta!=trial['cases'][i-1] or meta['formulation']!='conservative' or meta['power_mode']!=power
                or meta['local_step_s']!=step or meta['ablation_mode']!=args.mode or meta['friction_scale']!=scale
                or meta['convection_length_m']!=port_length or meta['valve_transition_s']!=0):
            raise ValueError('Unpaired ablation case')
        verify_parameters(meta)
        for key in ('actual_inlet_parameters','actual_outlet_parameters'):
            actual=meta[key]['values']
            if (float(actual['friction_scale'])!=scale or float(actual['convection_length'])!=port_length
                    or actual['convection_length_unit']!='m'):
                raise ValueError('Actual intervention changed')
        row=audit_case(meta,t,p,table,finite_transition=True,pipe_model=True)
        row.update(momentum_audit(p))
        row['declared_friction_observed']=(row['finite_pipe_loss_observed'] if scale else row['maximum_half_pipe_loss_Pa']<=1e-9)
        row['dual_inventory_closure_pass'] &= row['momentum_pressure_pass'] and row['declared_friction_observed']
        rows.append(row)
        hashes[f'case_{i}']=sha256(path)
    result=dict(schema='heatdrive_ecc_pipe_ablation_audit_v1',mode=args.mode,execution_commit=trial['execution_commit'],
                computation_complete=True,actual_simscape_cases=6,actual_scalar_trace_count=558,
                friction_scale=scale,convection_length_m=port_length,valve_transition_s=0,
                mass_absolute_gate_kg=1e-15,energy_absolute_gate_J=1e-8,
                conservative_inventory_all_pass=all(r['dual_inventory_closure_pass'] for r in rows),
                conservative_mass_max_residual_kg=max(v['mass_max_abs_residual_kg'] for r in rows for v in r['ledgers'].values()),
                conservative_energy_max_residual_J=max(v['energy_max_abs_residual_J'] for r in rows for v in r['ledgers'].values()),
                all_spatial_port_identities_pass=all(r['spatial_port_identities_pass'] for r in rows),
                all_declared_friction_observed=all(r['declared_friction_observed'] for r in rows),
                all_thermal_excitation_observed=all(r['thermal_excitation_observed'] for r in rows),
                all_valve_commands_pass=all(r['valve_command_pass'] for r in rows),
                minimum_valve_port_temperature_K=min(r['minimum_valve_port_temperature_K'] for r in rows),
                cases=rows,input_sha256=hashes,production_model_changed=False,production_recovery_allowed=False,
                whole_model_first_law_verified=False,table4_reproduction_claim=False,omitted_event_intervals=0)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('cases','input_sha256')},indent=2))


if __name__=='__main__':
    main()
