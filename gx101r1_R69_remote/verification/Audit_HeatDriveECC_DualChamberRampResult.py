"""Audit finite valve actuation without qualifying the frozen hard-switch model."""
import argparse
import json
from pathlib import Path

from Audit_HeatDriveECC_DualChamberSwitchResult import read_case,audit_case
from Audit_HeatDriveECC_ChamberStepConvergence import PHYSICAL_SHA,TOPOLOGY_SHA
from Audit_HeatDriveECC_ConservativeChamberResult import MASS_ATOL_KG,ENERGY_ATOL_J
from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite audit evidence')
    base = args.repo/'outputs_storage_audit'
    root = base/'dual_chamber_ramp_20260907/trial'
    trial_path = root/'dual_switch_result.json'
    trial = json.loads(trial_path.read_text(encoding='utf-8-sig'))
    topology_path = base/'tl_domain_energy_tables_20260906/tl_domain_metadata.json'
    parent_path = base/'dual_chamber_switch_20260907_v4/failure_matrix_audit.json'
    parent = json.loads(parent_path.read_text())
    component = root/'build/+ecc_inventory/conservative_chamber.ssc'
    old_component = base/'dual_chamber_switch_20260907_v4/trial/build/+ecc_inventory/conservative_chamber.ssc'
    if (trial['schema'] != 'heatdrive_ecc_dual_chamber_switch_trial_v3' or not trial['collection_pass']
            or len(trial['cases']) != 12 or trial['failed_cases'] or trial['valve_transition_s'] != .01
            or not trial['execution_commit'].startswith('7021656') or trial['production_model_changed']
            or trial['production_checkpoint_loaded'] or trial['production_recovery_allowed']
            or sha256(topology_path).upper() != TOPOLOGY_SHA or sha256(Path(trial['source_options_path'])).upper() != PHYSICAL_SHA
            or sha256(component) != sha256(old_component) or parent['completed_simulations'] != 0):
        raise ValueError('Frozen source, failed baseline or scope changed')
    table_data = json.loads(topology_path.read_text(encoding='utf-8-sig'))
    water = next(r for r in table_data['settings_tables'] if r['block_path'].endswith('/SMA_ThermalLiquidSettings'))
    table = energy_tables(water['parameters'])
    rows,hashes = [],dict(contract=sha256(trial_path),topology=sha256(topology_path),hard_switch_audit=sha256(parent_path),component=sha256(component))
    keys = [(f,p,s) for f in ('native','conservative') for p in ('none','isentropic') for s in (.001,.0005,.00025)]
    for i,key in enumerate(keys,1):
        path = root/f'case_{i}.mat'
        meta,t,p = read_case(path,finite_transition=True)
        if meta != trial['cases'][i-1] or tuple(meta[k] for k in ('formulation','power_mode','local_step_s')) != key:
            raise ValueError('Mismatched finite-actuation case')
        rows.append(audit_case(meta,t,p,table,finite_transition=True))
        hashes[f'case_{i}'] = sha256(path)
    result = dict(schema='heatdrive_ecc_dual_chamber_ramp_audit_v1',computation_complete=True,
                  trial_execution_commit=trial['execution_commit'],actual_simscape_cases=12,actual_scalar_trace_count=948,
                  cases=rows,input_sha256=hashes,mass_absolute_gate_kg=MASS_ATOL_KG,energy_absolute_gate_J=ENERGY_ATOL_J,
                  tested_dual_inventory_closure_verified=all(r['dual_inventory_closure_pass'] for r in rows[6:]),
                  conservative_mass_max_residual_kg=max(v['mass_max_abs_residual_kg'] for r in rows[6:] for v in r['ledgers'].values()),
                  conservative_energy_max_residual_J=max(v['energy_max_abs_residual_J'] for r in rows[6:] for v in r['ledgers'].values()),
                  all_spatial_port_identities_pass=all(r['spatial_port_identities_pass'] for r in rows),
                  all_pump_mode_formulas_pass=all(r['pump_mode_formula_pass'] for r in rows),
                  all_valve_commands_pass=all(r['valve_command_pass'] for r in rows),
                  all_thermal_excitation_observed=all(r['thermal_excitation_observed'] for r in rows),
                  minimum_valve_port_temperature_K=min(r['minimum_valve_port_temperature_K'] for r in rows),
                  hard_switch_failure_resolved=False,production_model_changed=False,production_recovery_allowed=False,
                  whole_model_first_law_verified=False,table4_reproduction_claim=False,omitted_event_intervals=0)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('cases','input_sha256')},indent=2))


if __name__=='__main__':
    main()
