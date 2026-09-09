"""Check actual t=0 inventories, source balances and pressure-rate consistency."""
import argparse
import csv
import json
from pathlib import Path
import h5py
import numpy as np
from Analyze_HeatDriveECC_ChamberPressureCoordinates import inventory_jacobian, pressure_map
from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdChamberRejection import read
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_ColdChamberStateCoordinates import bilinear_gradient
from Audit_HeatDriveECC_ColdInitialTolerance import coordinates
from Audit_HeatDriveECC_ColdInitializationPhases import check_phases
from Audit_HeatDriveECC_ColdProjectionInitialization import check_runtime, check_derivative
from Audit_HeatDriveECC_CompiledInventoryStates import CHAMBERS, BUFFERS, decode_tags, component_inventory_preserved
from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def initial_value(rows, path, name, unit):
    r = rows[path, name]
    t = np.asarray(r['time_s']).ravel()
    v = scalar_series(r, unit)
    if len(t) != 1 or t[0] != 0 or np.asarray(v).size != 1 or not np.isfinite(v).all():
        raise ValueError('Only one actual finite t=0 sample is admissible')
    return float(np.asarray(v).ravel()[0])


def flux_constraints(chambers, pump, commanded_rate=0.):
    if len(chambers) != 2 or not np.isfinite(commanded_rate):
        raise ValueError('Incomplete pressure pair')
    a, b = chambers
    mass = [a['mdot_B']+pump['mdot_A'], b['mdot_A']+pump['mdot_B'], pump['mdot_A']+pump['mdot_B']]
    energy = [a['Phi_B']+pump['Phi_A'], b['Phi_A']+pump['Phi_B'], pump['Phi_A']+pump['Phi_B']+pump['power']]
    rate = b['pdot']-a['pdot']-commanded_rate
    if not np.isfinite(mass+energy+[rate]).all():
        raise ValueError('Nonfinite local flux residual')
    return dict(mass_residuals_kg_s=mass, energy_residuals_W=energy, pressure_rate_residual_Pa_s=rate,
                mass_residual_limit_kg_s=1e-15, energy_residual_limit_W=1e-8, pressure_rate_residual_limit_Pa_s=1e-3,
                initial_flux_pressure_consistency_pass=max(map(abs, mass)) <= 1e-15
                    and max(map(abs, energy)) <= 1e-8 and abs(rate) <= 1e-3)


def audit(repo):
    root = repo/'outputs_storage_audit'
    trial = root/'specific_inventory_projection_initial_flux_20260909'
    record_path = trial/'compiled_states_inspection.json'; r = read(record_path)
    if (r['inspector_commit'] != 'ad716d9530622bddc06c734343f6fac8df7c1ebe' or not r['inspection_pass']
            or not r['initial_flux_export_requested'] or r['stage'] != 'complete' or not r['initialization_only']
            or any(r[k] for k in ('ps_controller_requested', 'analytic_pressure_derivative_requested',
                                 'production_recovery_allowed', 'c200_state_imported', 'failed_terminal_state_imported', 'checkpoint_saved'))):
        raise ValueError('Unqualified initial flux collection')
    reference_root = root/'conservative_buffer_coupled_cycle_20260909'
    targets_path = reference_root/'conservative/public_inventory_targets.json'
    reference = read(targets_path); targets = reference['targets']
    if len(targets) != 204 or reference['has_private_data']:
        raise ValueError('Invalid reference targets')
    check_runtime(r, targets, 'derivative'); check_derivative(r['initial_pressure_derivative_contract'])
    coordinate_rows = coordinates(r['initial_coordinates'], targets)
    check_phases(r['cached_phase_targets'], targets, coordinate_rows)
    tagged = [dict(block_name=x['block_name'], variable_name=x['variable_name'], **decode_tags(x)) for x in r['node_metadata']]
    inventories_retained = component_inventory_preserved(tagged, CHAMBERS | BUFFERS)
    if not all(x['within_strict_comparison'] for x in coordinate_rows) or not inventories_retained:
        raise ValueError('The repeat lost strict initial inventory qualification')
    raw = trial/'observations.mat'
    if sha256(raw) != r['observations_sha256']:
        raise ValueError('Initial observation hash changed')
    contract_path = root/'pump_subnetwork_contract_20260909_v2/pump_subnetwork_contract.json'
    contract = read(contract_path)
    blocks = {b['path'].split('/')[-1]: b for b in contract['blocks']}
    if blocks['SMA Pressure Source (TL)']['parameters']['power_spec'] != 'foundation.enum.power_spec.none':
        raise ValueError('Unexpected actual pump mode')
    table = energy_tables(blocks['SMA_ThermalLiquidSettings']['parameters'])
    chamber_records = []
    with h5py.File(raw) as f:
        native, sources = named_rows(f, f['native']), named_rows(f, f['source_traces'])
        if len(native) != 1258 or len(sources) != 162 or len({p for p, _ in native}) != 119 or len({p for p, _ in sources}) != 49:
            raise ValueError('Incomplete actual storage/source coverage')
        for path in sorted('heatdrive_ecc_coupled_se21/'+name for name in CHAMBERS):
            get = lambda name, unit: initial_value(native, path, name, unit)
            t, p, mass, energy = get('T_I', 'K'), get('p_I', 'Pa'), get('stored_mass', 'kg'), get('stored_energy', 'J')
            volume = blocks[path.split('/')[-1]]['resolved_geometry']['volume']['value']
            rho, u = float(table['rho']([[t, p]])[0]), float(table['u']([[t, p]])[0])
            if abs(volume*rho-mass) > 1e-15 or abs(mass*u-energy) > 1e-8:
                raise ValueError('Actual inventory aliases disagree')
            rt, rp = (float(v[0]) for v in bilinear_gradient(table['rho'], np.array([t]), np.array([p])))
            ut, up = (float(v[0]) for v in bilinear_gradient(table['u'], np.array([t]), np.array([p])))
            mapping = pressure_map(inventory_jacobian(rho, u, rt, rp, ut, up, volume), [mass, abs(energy)], [1., 1e6])
            flux = {name: get(name, 'kg/s' if name.startswith('mdot') else 'W') for name in ('mdot_A', 'mdot_B', 'Phi_A', 'Phi_B', 'Q_H')}
            dm = flux['mdot_A']+flux['mdot_B']; du = flux['Phi_A']+flux['Phi_B']+flux['Q_H']
            pdot = mapping['pressure_derivative_Pa_per_kg']*dm+mapping['pressure_derivative_Pa_per_J']*du
            chamber_records.append(dict(block_path=path, temperature_K=t, pressure_Pa=p, mass_kg=mass, energy_J=energy,
                                        **flux, Mdot_kg_s=dm, Udot_W=du, pdot=pdot, pdot_basis='inferred from actual native fluxes and table-exact inventory derivatives'))
        pump_path = 'heatdrive_ecc_coupled_se21/SMA Pressure Source (TL)'
        pump = {name: initial_value(sources, pump_path, name, 'kg/s' if name.startswith('mdot') else 'W')
                for name in ('mdot_A', 'mdot_B', 'Phi_A', 'Phi_B', 'power')}
        signal = f['signals/mass_flow_sma_stage13_kgps']
        signal_time = signal['time_s'][...].ravel(); signal_value = signal['values'][...].ravel()
        if (signal_time.tolist() != [0.] or len(signal_value) != 1 or not np.isfinite(signal_value).all()
                or abs(signal_value[0]-pump['mdot_A']) > 1e-15):
            raise ValueError('Actual feedback signal differs from source mass flow')
        measured_mdot = float(signal_value[0])
    constraints = flux_constraints(chamber_records, pump)
    local_path = root/'pump_local_initialization_20260909_v3/pump_local_initialization.json'
    local = read(local_path)
    if not local['local_residual_pass']:
        raise ValueError('Local equation prerequisite failed')
    files = [record_path, raw, targets_path, trial/'compiled_initial_state_dataset.mat', trial/'matlab_diary.log', contract_path, local_path]
    freeze_path = repo/'verification/c200_mainline_freeze_contract.json'; freeze = read(freeze_path); files.append(freeze_path)
    for key in ('result', 'checkpoint'):
        path = repo/freeze[key+'_relative_path']
        if sha256(path) != freeze[key+'_sha256']:
            raise ValueError('Frozen C200 changed')
        files.append(path)
    return dict(schema='heatdrive_ecc_initial_flux_pressure_audit_v1', strict_initial_coordinate_match=True,
                matching_initial_coordinates=len(coordinate_rows), compiled_inventory_gate=inventories_retained,
                chambers=chamber_records, pump=pump, constraints=constraints,
                measured_flow_signal_initial_kg_s=measured_mdot,
                difference_from_fixed_outer_flux_local_solution=dict(
                    pump_mdot_kg_s=pump['mdot_A']-local['result']['mdot_A_pump_kg_s'],
                    outer_energy_flux_W=[chamber_records[0]['Phi_A']-local['prescribed_outer_fluxes'][0]['Phi_W'],
                                         chamber_records[1]['Phi_B']-local['prescribed_outer_fluxes'][1]['Phi_W']]),
                exact_old_local_solution_comparison_claim=False, trajectory_conservation_verified=False,
                ps_controller_initialization_verified=False, production_recovery_allowed=False,
                full_device_first_law_verified=False, table4_reproduction_claim=False,
                input_sha256={str(p.relative_to(repo)): sha256(p) for p in files}), coordinate_rows


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--output-root', type=Path, required=True)
    args = parser.parse_args()
    if args.output_root.exists():
        raise FileExistsError('Never overwrite evidence')
    result, rows = audit(Path(__file__).resolve().parents[1]); args.output_root.mkdir(parents=True)
    (args.output_root/'initial_flux_pressure_audit.json').write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    with (args.output_root/'initial_coordinates.csv').open('w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)
    print(json.dumps({k: v for k, v in result.items() if k != 'input_sha256'}, indent=2))
    raise SystemExit(0 if result['constraints']['initial_flux_pressure_consistency_pass'] else 1)
