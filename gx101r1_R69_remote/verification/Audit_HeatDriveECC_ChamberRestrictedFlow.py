"""Independent finite-restriction ledger; the failed fixed-pressure test remains open."""
import argparse
import json
from pathlib import Path

import numpy as np

from Audit_HeatDriveECC_ChamberOpenFlowResult import balance, command, read_case
from Audit_HeatDriveECC_ChamberStepConvergence import PHYSICAL_SHA, TOPOLOGY_SHA
from Audit_HeatDriveECC_ConservativeChamberResult import MASS_ATOL_KG, ENERGY_ATOL_J
from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def port_identities(c, source, hot, cold, restriction):
    mass = [hot['mdot_A']+source['mdot_A'], source['mdot_B']+c['mdot_A'],
            c['mdot_B']+restriction['mdot_A'], restriction['mdot_B']+cold['mdot_A'],
            restriction['mdot_A']+restriction['mdot_B'], source['mdot_A']+source['mdot_B']]
    energy = [hot['Phi_A']+source['Phi_A'], source['Phi_B']+c['Phi_A'],
              c['Phi_B']+restriction['Phi_A'], restriction['Phi_B']+cold['Phi_A'],
              restriction['Phi_A']+restriction['Phi_B'], source['Phi_A']+source['Phi_B']+source['power']]
    arrays = [np.asarray(mass), np.asarray(energy)]
    if any(not np.isfinite(a).all() for a in arrays):
        raise ValueError('Nonfinite port identity')
    return float(np.max(abs(arrays[0]))), float(np.max(abs(arrays[1])))


def pump_power_contract(source, upstream_pressure, downstream_pressure):
    rho = (source['rho_A']+source['rho_B'])/2
    if not np.isfinite(rho).all() or np.any(rho <= 0):
        raise ValueError('Invalid source port density')
    independent = source['mdot_A']*(downstream_pressure-upstream_pressure)/rho
    error = float(np.max(abs(independent-source['power'])))
    if not np.isfinite(error):
        raise ValueError('Nonfinite pump power')
    return error


def audit_case(meta, time, packets, table):
    required = dict(boundary_mode='finite_outlet_restriction', outlet_area_m2=2e-8,
                    restriction_type='foundation.enum.restriction_type.fixed', discharge_coefficient=.64,
                    critical_reynolds_number=150, pressure_recovery='on',
                    local_solver_enabled='on', local_solver='NE_BACKWARD_EULER_ADVANCER', global_solver='ode3',
                    initial_temperature_K=340, pressure_Pa=2.5e6, hot_reservoir_K=380, cold_reservoir_K=300,
                    flow_magnitude_kg_s=.0002, reversal_time_s=.5, stop_s=1,
                    volume_m3=1.6084954386379741e-6, area_m2=8.04247719318987e-6)
    if any(meta.get(k) != v for k, v in required.items()) or meta['local_step_s'] != meta['global_step_s']:
        raise ValueError('Restricted-flow contract changed')
    c, s, hot, cold, r = [packets[k] for k in ('chamber','flow_source','hot_reservoir','cold_reservoir','outlet_restriction')]
    expected = command(time, meta['mode'], meta['local_step_s'])
    if (np.max(abs(c['mdot_A']-expected)) > 1e-15 or np.max(abs(s['mdot_A']-expected)) > 1e-15
            or np.max(abs(c['Q_H'])) > 1e-9 or abs(c['p_I'][0]-2.5e6) > 1e-4 or abs(c['T_I'][0]-340) > 1e-9
            or any(np.max(abs(x['p_I']-2.5e6)) > 1e-4 for x in (hot,cold))
            or np.max(abs(hot['T_I']-380)) > 1e-9 or np.max(abs(cold['T_I']-300)) > 1e-9):
        raise ValueError('Measured command, initial state or reservoir condition failed')
    point = np.column_stack((c['T_I'], c['p_I']))
    if np.max(abs(table['rho'](point)-c['rho_I'])) > 1e-8 or np.max(abs(table['u'](point)-c['u_I'])) > 1e-6:
        raise ValueError('Water domain mismatch')
    m = meta['volume_m3']*c['rho_I']
    u = m*c['u_I']
    local = balance(time, m, u, c['mdot_A']+c['mdot_B'], c['Phi_A']+c['Phi_B']+c['Q_H'])
    external = balance(time, m, u, -hot['mdot_A']-cold['mdot_A'], -hot['Phi_A']-cold['Phi_A']+s['power'])
    mass_error, energy_error = port_identities(c,s,hot,cold,r)
    power_error = pump_power_contract(s,hot['p_I'],c['p_I'])
    row = dict(meta, sample_count=len(time), local_ledger=local, external_ledger=external,
               spatial_mass_max_abs_kg_s=mass_error, spatial_energy_max_abs_W=energy_error,
               spatial_port_identities_pass=mass_error <= 1e-15 and energy_error <= 1e-9,
               pump_power_formula_max_error_W=power_error, pump_power_formula_pass=power_error <= 1e-9,
               max_abs_pump_power_W=float(np.max(abs(s['power']))),
               integrated_pump_energy_J=float(np.sum(s['power'][1:]*np.diff(time))),
               min_chamber_pressure_Pa=float(c['p_I'].min()), max_chamber_pressure_Pa=float(c['p_I'].max()),
               min_temperature_K=float(c['T_I'].min()), max_temperature_K=float(c['T_I'].max()),
               outlet_flow_min_kg_s=float(r['mdot_A'].min()), outlet_flow_max_kg_s=float(r['mdot_A'].max()),
               nonzero_pump_head_measured=bool(np.max(abs(c['p_I']-hot['p_I'])) > 1e3 and np.max(abs(s['power'])) > 1e-4),
               omitted_event_intervals=0, compiler_state_selection_directly_observed=False)
    if meta['formulation'] == 'conservative':
        row['inventory_aliases_match'] = bool(np.max(abs(c['stored_mass']-m)) <= MASS_ATOL_KG
                                              and np.max(abs(c['stored_energy']-u)) <= ENERGY_ATOL_J)
        row['restricted_inventory_closure_pass'] = (row['inventory_aliases_match'] and row['spatial_port_identities_pass']
            and row['pump_power_formula_pass'] and row['nonzero_pump_head_measured']
            and all(x['mass_closure_pass'] and x['energy_closure_pass'] for x in (local, external)))
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--trial', type=Path, required=True)
    parser.add_argument('--execution-commit', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite an audit')
    base = args.repo/'outputs_storage_audit'
    contract_path = args.trial/'open_flow_result.json'
    trial = json.loads(contract_path.read_text(encoding='utf-8-sig'))
    topology_path = base/'tl_domain_energy_tables_20260906/tl_domain_metadata.json'
    prior_path = base/'chamber_open_flow_20260907_v2/open_flow_audit_v3.json'
    prior = json.loads(prior_path.read_text())
    sealed_path = base/'conservative_chamber_20260907_v4/conservative_audit_v1.json'
    sealed = json.loads(sealed_path.read_text())
    component = args.trial/'build/+ecc_inventory/conservative_chamber.ssc'
    if (trial['schema'] != 'heatdrive_ecc_chamber_restricted_flow_trial_v1' or not trial['collection_pass']
            or len(trial['cases']) != 18 or trial['execution_commit'] != args.execution_commit
            or trial['outlet_area_m2'] != 2e-8 or trial['production_model_changed'] or trial['production_checkpoint_loaded']
            or trial['production_recovery_allowed'] or prior['tested_open_flow_inventory_closure_verified']
            or sha256(topology_path).upper() != TOPOLOGY_SHA
            or sha256(Path(trial['source_options_path'])).upper() != PHYSICAL_SHA
            or sha256(component) != sealed['input_sha256']['compiled_source']):
        raise ValueError('Frozen identity, failure evidence or diagnostic scope changed')
    topology = json.loads(topology_path.read_text(encoding='utf-8-sig'))
    water = next(x for x in topology['settings_tables'] if x['block_path'].endswith('/SMA_ThermalLiquidSettings'))
    table = energy_tables(water['parameters'])
    rows = []
    hashes = dict(trial=sha256(contract_path), topology=sha256(topology_path), prior_failed_audit=sha256(prior_path),
                  sealed_audit=sha256(sealed_path), compiled_component=sha256(component))
    keys = [(f,m,s) for f in ('native','conservative') for m in ('forward','reverse','reversal') for s in (.001,.0005,.00025)]
    for i,key in enumerate(keys,1):
        path = args.trial/f'case_{i}.mat'
        meta,time,packets = read_case(path, restricted=True)
        if (meta != trial['cases'][i-1] or tuple(meta[k] for k in ('formulation','mode','local_step_s')) != key
                or meta['source_settings'] != water['block_path']):
            raise ValueError('Missing or mismatched paired case')
        rows.append(audit_case(meta,time,packets,table))
        hashes[f'case_{i}'] = sha256(path)
    result = dict(schema='heatdrive_ecc_chamber_restricted_flow_audit_v1', computation_complete=True,
                  trial_execution_commit=args.execution_commit, cases=rows, input_sha256=hashes,
                  actual_simscape_cases=18, actual_native_scalar_trace_count=522,
                  mass_absolute_gate_kg=MASS_ATOL_KG, energy_absolute_gate_J=ENERGY_ATOL_J,
                  tested_restricted_inventory_closure_verified=all(r['restricted_inventory_closure_pass'] for r in rows[9:]),
                  conservative_mass_max_residual_kg=max(r['external_ledger']['mass_max_abs_residual_kg'] for r in rows[9:]),
                  conservative_energy_max_residual_J=max(r['external_ledger']['energy_max_abs_residual_J'] for r in rows[9:]),
                  all_spatial_port_identities_pass=all(r['spatial_port_identities_pass'] for r in rows),
                  all_pump_power_formulas_pass=all(r['pump_power_formula_pass'] for r in rows),
                  nonzero_pump_head_verified=all(r['nonzero_pump_head_measured'] for r in rows),
                  fixed_pressure_failure_resolved=False, whole_model_first_law_verified=False,
                  production_recovery_allowed=False, table4_reproduction_claim=False, omitted_event_intervals=0)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('cases','input_sha256')},indent=2))


if __name__ == '__main__':
    main()
