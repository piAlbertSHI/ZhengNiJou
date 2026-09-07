"""Audit paired geometric pipe replacements without qualifying production."""
import argparse
import json
from pathlib import Path

import numpy as np

from Audit_HeatDriveECC_DualChamberSwitchResult import read_case, audit_case
from Audit_HeatDriveECC_ChamberStepConvergence import PHYSICAL_SHA, TOPOLOGY_SHA
from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def momentum_audit(p):
    errors, losses = [], []
    for role in ('inlet', 'outlet'):
        v = p[role]
        for side in ('A', 'B'):
            if (not np.isfinite([v[f'{side}.p'], v[f'{side}.T'], v[f'pressure_loss_{side}']]).all()
                    or np.any(v[f'{side}.p'] < .45e6) or np.any(v[f'{side}.p'] > 5e6)
                    or np.any(v[f'{side}.T'] < 273.16) or np.any(v[f'{side}.T'] > 413.16)):
                raise ValueError('Pipe port outside physical domain')
            errors.append(float(np.max(abs(v[f'{side}.p']-v['p_I']-v[f'pressure_loss_{side}']))))
            losses.append(float(np.max(abs(v[f'pressure_loss_{side}']))))
    errors += [float(np.max(abs(p['inlet']['A.p']-p['v1']['B.p']))),
               float(np.max(abs(p['inlet']['A.p']-p['v2']['B.p']))),
               float(np.max(abs(p['outlet']['B.p']-p['v3']['A.p']))),
               float(np.max(abs(p['outlet']['B.p']-p['v4']['A.p'])))]
    return dict(momentum_pressure_max_error_Pa=max(errors), momentum_pressure_pass=max(errors)<=1e-4,
                maximum_half_pipe_loss_Pa=max(losses), finite_pipe_loss_observed=max(losses)>1)


def verify_parameters(meta, *, wall_model=False):
    contract = meta['pipe_contract']
    expected = dict(length_m=.2, diameter_m=.0032, roughness_m=15e-6, length_add_m=0,
                    Re_lam=2000, Re_tur=4000, shape_factor=64, inertia=False, wall_heat_flow_W=0,
                    production_qualification=False)
    if wall_model:
        expected['wall_heat_flow_W'] = []
    if any(contract.get(k)!=v for k,v in expected.items()):
        raise ValueError('Declared pipe physics changed')
    for key in ('actual_inlet_parameters','actual_outlet_parameters'):
        actual = meta[key]['values']
        numbers = dict(length=.2, Dh=.0032, area=meta['area_m2'], roughness=15e-6)
        units = dict(length_unit='m', Dh_unit='m', area_unit='m^2', roughness_unit='m')
        if meta['formulation']=='native':
            numbers.update(length_add=0, Re_lam=2000, Re_tur=4000, shape_factor=64, p0=2.5, T0=340)
            units.update(length_add_unit='m', p0_unit='MPa', T0_unit='K', dynamic_compressibility='true', inertia='false')
        else:
            numbers.update(volume=meta['volume_each_m3'], p_I=2.5, T_I=340)
            units.update(volume_unit='m^3', p_I_unit='MPa', T_I_unit='K')
        if any(float(actual[k])!=v for k,v in numbers.items()) or any(actual[k]!=v for k,v in units.items()):
            raise ValueError('Actual pipe parameters changed')
    tol=meta['solver_tolerances']
    if (meta['index_reduction']!='DerivativeReplacement' or tol['ConsistencyTolSource']!='LOCAL'
            or any(float(tol[k])!=1e-12 for k in ('ResidualTolerance','ConsistencyAbsTol','ConsistencyRelTol'))):
        raise ValueError('Actual solver changed')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--hard',action='store_true')
    args=parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite audit evidence')
    base=args.repo/'outputs_storage_audit'
    root=base/'dual_pipe_friction_20260907_v2/trial'
    if args.hard:
        root=base/'dual_pipe_hard_switch_20260907/trial'
    trial_path=root/'dual_switch_result.json'
    trial=json.loads(trial_path.read_text(encoding='utf-8-sig'))
    topology=base/'tl_domain_energy_tables_20260906/tl_domain_metadata.json'
    component=root/'build/+ecc_inventory/conservative_chamber.ssc'
    source=args.repo/'verification/simscape_inventory_pipe/+ecc_inventory/conservative_chamber.ssc'
    schema='heatdrive_ecc_dual_chamber_switch_trial_v7' if args.hard else 'heatdrive_ecc_dual_chamber_switch_trial_v6'
    commit='7bbd60bf79e125664476f9a4d248e9de64b2cadc' if args.hard else 'd9c689797498949f96b0a536cac0fa5dba54456e'
    duration=0 if args.hard else .01
    if (trial['schema']!=schema or not trial['collection_pass']
            or len(trial['cases'])!=12 or trial['failed_cases'] or not trial['pipe_model']
            or trial['execution_commit']!=commit or trial['valve_transition_s']!=duration
            or trial['production_model_changed'] or trial['production_checkpoint_loaded'] or trial['production_recovery_allowed']
            or sha256(topology)!=TOPOLOGY_SHA or sha256(Path(trial['source_options_path']))!=PHYSICAL_SHA
            or sha256(component)!=sha256(source)):
        raise ValueError('Frozen pipe trial identity or scope changed')
    data=json.loads(topology.read_text(encoding='utf-8-sig'))
    water=next(r for r in data['settings_tables'] if r['block_path'].endswith('/SMA_ThermalLiquidSettings'))
    table=energy_tables(water['parameters'])
    hashes=dict(trial=sha256(trial_path),topology=sha256(topology),component=sha256(component))
    rows=[]
    keys=[(f,p,s) for f in ('native','conservative') for p in ('none','isentropic') for s in (.001,.0005,.00025)]
    for i,key in enumerate(keys,1):
        path=root/f'case_{i}.mat'
        meta,t,p=read_case(path,finite_transition=True,pipe_model=True)
        if (meta!=trial['cases'][i-1] or tuple(meta[k] for k in ('formulation','power_mode','local_step_s'))!=key
                or meta['valve_transition_s']!=duration):
            raise ValueError('Unpaired experiment')
        verify_parameters(meta)
        row=audit_case(meta,t,p,table,finite_transition=True,pipe_model=True)
        row.update(momentum_audit(p))
        if meta['formulation']=='conservative':
            row['dual_inventory_closure_pass'] &= row['momentum_pressure_pass'] and row['finite_pipe_loss_observed']
        rows.append(row)
        hashes[f'case_{i}']=sha256(path)
    result=dict(schema='heatdrive_ecc_dual_pipe_hard_audit_v1' if args.hard else 'heatdrive_ecc_dual_pipe_friction_audit_v1',computation_complete=True,
                **(dict(valve_transition_s=duration) if args.hard else {}),
                trial_execution_commit=trial['execution_commit'],actual_simscape_cases=12,actual_scalar_trace_count=1092,
                cases=rows,input_sha256=hashes,mass_absolute_gate_kg=1e-15,energy_absolute_gate_J=1e-8,
                conservative_inventory_all_pass=all(r['dual_inventory_closure_pass'] for r in rows[6:]),
                conservative_mass_max_residual_kg=max(v['mass_max_abs_residual_kg'] for r in rows[6:] for v in r['ledgers'].values()),
                conservative_energy_max_residual_J=max(v['energy_max_abs_residual_J'] for r in rows[6:] for v in r['ledgers'].values()),
                all_spatial_port_identities_pass=all(r['spatial_port_identities_pass'] for r in rows),
                all_pump_mode_formulas_pass=all(r['pump_mode_formula_pass'] for r in rows),
                all_momentum_pressure_pass=all(r['momentum_pressure_pass'] and r['finite_pipe_loss_observed'] for r in rows),
                all_thermal_excitation_observed=all(r['thermal_excitation_observed'] for r in rows),
                all_valve_commands_pass=all(r['valve_command_pass'] for r in rows),
                hard_switch_failure_resolved=False,production_model_changed=False,production_recovery_allowed=False,
                whole_model_first_law_verified=False,table4_reproduction_claim=False,omitted_event_intervals=0)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('cases','input_sha256')},indent=2))


if __name__=='__main__':
    main()
