"""Audit all two-chamber inventory intervals with explicit pump-work modes."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_ChamberOpenFlowResult import balance
from Audit_HeatDriveECC_ChamberRestrictedFlow import pump_power_contract
from Audit_HeatDriveECC_ChamberStepConvergence import PHYSICAL_SHA, TOPOLOGY_SHA
from Audit_HeatDriveECC_ConservativeChamberResult import MASS_ATOL_KG, ENERGY_ATOL_J
from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_NativeWindowLedger import validate_grid
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field


def read_case(path):
    units = dict(T_I='K',p_I='Pa',rho_I='kg/m^3',u_I='J/kg',mdot_A='kg/s',mdot_B='kg/s',
                 Phi_A='W',Phi_B='W',Q_H='W',stored_mass='kg',stored_energy='J',power='W',rho_A='kg/m^3',rho_B='kg/m^3')
    with h5py.File(path,'r') as f:
        meta = json.loads(text_field(f['record_json']))
        packets,time = {},None
        for ref in f['packets'][:].flat:
            block = f[ref]
            role = text_field(block['role'])
            if role in packets:
                raise ValueError('Duplicate component role')
            traces = {}
            for trace_ref in block['traces'][:].flat:
                trace = f[trace_ref]
                name,unit = text_field(trace['name']),text_field(trace['unit'])
                t,raw = trace['time_s'][:].reshape(-1),trace['values'][:].reshape(-1)
                validate_grid(t,0,1,meta['local_step_s'])
                if time is None:
                    time = t
                if name in traces or name not in units or raw.shape != t.shape or not np.array_equal(t,time):
                    raise ValueError('Incomplete, duplicate or off-grid trace')
                traces[name] = convert(raw,unit,units[name])
            packets[role] = traces
    chamber = {'T_I','p_I','rho_I','u_I','mdot_A','mdot_B','Phi_A','Phi_B','Q_H'}
    if meta['formulation'] == 'conservative':
        chamber |= {'stored_mass','stored_energy'}
    expected = dict(inlet=chamber,outlet=chamber,pump={'mdot_A','mdot_B','Phi_A','Phi_B','power','rho_A','rho_B'},
                    inlet_reservoir={'mdot_A','Phi_A','p_I','T_I'},outlet_reservoir={'mdot_A','Phi_A','p_I','T_I'})
    expected.update({f'v{i}':{'mdot_A','mdot_B','Phi_A','Phi_B'} for i in range(1,5)})
    if set(packets) != set(expected) or any(set(packets[k]) != v for k,v in expected.items()):
        raise ValueError('Require complete nine-component port coverage')
    return meta,time,packets


def spatial_identities(p, kind):
    if kind not in ('mdot','Phi'):
        raise ValueError('Unsupported conserved port quantity')
    a,b = kind+'_A',kind+'_B'
    c,d,s,h,k = [p[x] for x in ('inlet','outlet','pump','inlet_reservoir','outlet_reservoir')]
    v1,v2,v3,v4 = [p[f'v{i}'] for i in range(1,5)]
    rows = [h[a]+v1[a]+v3[b], k[a]+v2[a]+v4[b], c[a]+v1[b]+v2[b], c[b]+s[a],
            s[b]+d[a], d[b]+v3[a]+v4[a], s[a]+s[b]+(s['power'] if kind=='Phi' else 0)]
    rows += [v[a]+v[b] for v in (v1,v2,v3,v4)]
    if not np.isfinite(rows).all():
        raise ValueError('Nonfinite spatial identity')
    return float(np.max(abs(np.asarray(rows))))


def audit_case(meta,t,p,table):
    required = dict(volume_each_m3=1.6084954386379741e-6,area_m2=8.04247719318987e-6,
                    initial_temperature_K=340,initial_pressure_Pa=2.5e6,hot_reservoir_K=380,cold_reservoir_K=300,
                    reservoir_pressure_Pa=2.5e6,pressure_step_time_s=.01,command_pressure_Pa=260,route_switch_time_s=.5,
                    stop_s=1,local_solver='NE_BACKWARD_EULER_ADVANCER',global_solver='ode3')
    if (any(meta.get(k) != v for k,v in required.items()) or meta['formulation'] not in ('native','conservative')
            or meta['power_mode'] not in ('none','isentropic') or meta['local_step_s'] not in (.001,.0005,.00025)
            or meta['global_step_s'] != meta['local_step_s']):
        raise ValueError('Changed dual-chamber contract')
    c,d,s,h,k = [p[x] for x in ('inlet','outlet','pump','inlet_reservoir','outlet_reservoir')]
    index = np.rint(t/meta['local_step_s']).astype(int)
    dp = np.where(index < round(.01/meta['local_step_s']),0,260)
    if (np.max(abs(d['p_I']-c['p_I']-dp)) > 1e-4 or np.max(abs(h['p_I']-2.5e6)) > 1e-4
            or np.max(abs(k['p_I']-2.5e6)) > 1e-4 or np.max(abs(h['T_I']-380)) > 1e-9
            or np.max(abs(k['T_I']-300)) > 1e-9):
        raise ValueError('Measured pressure command or reservoir boundary failed')
    masses,energies,ledgers,aliases = [],[],{},[]
    for role in ('inlet','outlet'):
        v = p[role]
        if abs(v['T_I'][0]-340) > 1e-9 or abs(v['p_I'][0]-2.5e6) > 1e-4 or np.max(abs(v['Q_H'])) > 1e-9:
            raise ValueError('Unpaired initial state or heat input')
        point = np.column_stack((v['T_I'],v['p_I']))
        if np.max(abs(table['rho'](point)-v['rho_I'])) > 1e-8 or np.max(abs(table['u'](point)-v['u_I'])) > 1e-6:
            raise ValueError('Frozen water domain mismatch')
        m = v['rho_I']*meta['volume_each_m3']
        u = m*v['u_I']
        masses.append(m)
        energies.append(u)
        ledgers[role] = balance(t,m,u,v['mdot_A']+v['mdot_B'],v['Phi_A']+v['Phi_B']+v['Q_H'])
        if meta['formulation']=='conservative':
            aliases.append(np.max(abs(v['stored_mass']-m)) <= MASS_ATOL_KG and np.max(abs(v['stored_energy']-u)) <= ENERGY_ATOL_J)
    total_mass,total_energy = np.sum(masses,axis=0),np.sum(energies,axis=0)
    ledgers['external_total'] = balance(t,total_mass,total_energy,-h['mdot_A']-k['mdot_A'],-h['Phi_A']-k['Phi_A']+s['power'])
    mass_identity,energy_identity = spatial_identities(p,'mdot'),spatial_identities(p,'Phi')
    hypothetical = s['mdot_A']*dp/((s['rho_A']+s['rho_B'])/2)
    power_error = (pump_power_contract(s,c['p_I'],d['p_I']) if meta['power_mode']=='isentropic' else float(np.max(abs(s['power']))))
    active = [(t>=.1)&(t<.49),(t>=.6)&(t<.99)]
    route = dict(hot_active_mean_kg_s=float(np.mean(p['v1']['mdot_A'][active[0]])),
                 hot_inactive_mean_kg_s=float(np.mean(p['v1']['mdot_A'][active[1]])),
                 cold_active_mean_kg_s=float(np.mean(p['v2']['mdot_A'][active[1]])),
                 cold_inactive_mean_kg_s=float(np.mean(p['v2']['mdot_A'][active[0]])))
    route_pass = (route['hot_active_mean_kg_s']>0 and route['cold_active_mean_kg_s']>0
                  and abs(route['hot_inactive_mean_kg_s']) < .01*route['hot_active_mean_kg_s']
                  and abs(route['cold_inactive_mean_kg_s']) < .01*route['cold_active_mean_kg_s'])
    row = dict(meta,sample_count=len(t),ledgers=ledgers,route_flow_metrics=route,route_selection_observed=route_pass,
               spatial_mass_max_abs_kg_s=mass_identity,spatial_energy_max_abs_W=energy_identity,
               spatial_port_identities_pass=mass_identity <= 1e-15 and energy_identity <= 1e-9,
               pump_mode_formula_max_error_W=power_error,pump_mode_formula_pass=power_error <= 1e-9,
               measured_pump_power_max_abs_W=float(np.max(abs(s['power']))),
               hypothetical_isentropic_power_max_abs_W=float(np.max(abs(hypothetical))),
               measured_pump_energy_J=float(np.sum(s['power'][1:]*np.diff(t))),
               min_pressure_Pa=float(min(c['p_I'].min(),d['p_I'].min())),max_pressure_Pa=float(max(c['p_I'].max(),d['p_I'].max())),
               min_temperature_K=float(min(c['T_I'].min(),d['T_I'].min())),max_temperature_K=float(max(c['T_I'].max(),d['T_I'].max())),
               omitted_event_intervals=0,compiler_state_selection_directly_observed=False)
    if meta['formulation']=='conservative':
        row['inventory_aliases_match'] = bool(all(aliases))
        row['dual_inventory_closure_pass'] = (row['inventory_aliases_match'] and row['spatial_port_identities_pass']
            and row['pump_mode_formula_pass'] and route_pass
            and all(v['mass_closure_pass'] and v['energy_closure_pass'] for v in ledgers.values()))
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--trial',type=Path,required=True)
    parser.add_argument('--execution-commit',required=True)
    parser.add_argument('--output',type=Path,required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite audit evidence')
    base = args.repo/'outputs_storage_audit'
    trial_path = args.trial/'dual_switch_result.json'
    trial = json.loads(trial_path.read_text(encoding='utf-8-sig'))
    topology_path = base/'tl_domain_energy_tables_20260906/tl_domain_metadata.json'
    parent_path = base/'chamber_restricted_flow_20260907_v2/restricted_flow_audit_v1.json'
    parent = json.loads(parent_path.read_text())
    component = args.trial/'build/+ecc_inventory/conservative_chamber.ssc'
    if (trial['schema'] != 'heatdrive_ecc_dual_chamber_switch_trial_v1' or not trial['collection_pass'] or len(trial['cases']) != 12
            or trial['execution_commit'] != args.execution_commit or trial['production_model_changed']
            or trial['production_checkpoint_loaded'] or trial['production_recovery_allowed']
            or sha256(topology_path).upper() != TOPOLOGY_SHA or sha256(Path(trial['source_options_path'])).upper() != PHYSICAL_SHA
            or sha256(component) != parent['input_sha256']['compiled_component']
            or trial['source_pressure_parameters']['values']['power_spec'] != 'foundation.enum.power_spec.none'):
        raise ValueError('Source identity, actual pump mode or scope changed')
    topology = json.loads(topology_path.read_text(encoding='utf-8-sig'))
    water = next(x for x in topology['settings_tables'] if x['block_path'].endswith('/SMA_ThermalLiquidSettings'))
    table = energy_tables(water['parameters'])
    hashes = dict(trial=sha256(trial_path),topology=sha256(topology_path),parent_audit=sha256(parent_path),component=sha256(component))
    rows = []
    keys = [(f,p,s) for f in ('native','conservative') for p in ('none','isentropic') for s in (.001,.0005,.00025)]
    for i,key in enumerate(keys,1):
        path = args.trial/f'case_{i}.mat'
        meta,t,p = read_case(path)
        if meta != trial['cases'][i-1] or tuple(meta[k] for k in ('formulation','power_mode','local_step_s')) != key:
            raise ValueError('Missing paired case')
        rows.append(audit_case(meta,t,p,table))
        hashes[f'case_{i}'] = sha256(path)
    result = dict(schema='heatdrive_ecc_dual_chamber_switch_audit_v1',computation_complete=True,
                  trial_execution_commit=args.execution_commit,actual_simscape_cases=12,actual_scalar_trace_count=612,
                  cases=rows,input_sha256=hashes,mass_absolute_gate_kg=MASS_ATOL_KG,energy_absolute_gate_J=ENERGY_ATOL_J,
                  tested_dual_inventory_closure_verified=all(r['dual_inventory_closure_pass'] for r in rows[6:]),
                  conservative_mass_max_residual_kg=max(v['mass_max_abs_residual_kg'] for r in rows[6:] for v in r['ledgers'].values()),
                  conservative_energy_max_residual_J=max(v['energy_max_abs_residual_J'] for r in rows[6:] for v in r['ledgers'].values()),
                  all_spatial_port_identities_pass=all(r['spatial_port_identities_pass'] for r in rows),
                  all_pump_mode_formulas_pass=all(r['pump_mode_formula_pass'] for r in rows),
                  all_route_selection_observed=all(r['route_selection_observed'] for r in rows),
                  production_pressure_source_power_mode='none',production_model_changed=False,production_recovery_allowed=False,
                  whole_model_first_law_verified=False,table4_reproduction_claim=False,omitted_event_intervals=0)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('cases','input_sha256')},indent=2))


if __name__=='__main__':
    main()
