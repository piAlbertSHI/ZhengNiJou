"""Test a post-hoc 20 us state-shift signature, without changing any targets."""
import argparse
from collections import Counter
import csv
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_ColdBufferCoupled import topology_check
from Audit_HeatDriveECC_ColdChamberCycle import checked_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series, compare_initial
from Audit_HeatDriveECC_ConservativeBufferTrial import inventory
from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_TLDomainInventory import scalar


EXPERIMENT = 'specific_inventory_cold_onset_20260909'
PRODUCER = '7408b1deda367f2d5324bd75e66ab593114cc459'
HYPOTHESIS_S = 2e-5


def signature(delta, rate, step=HYPOTHESIS_S):
    delta, rate = np.asarray(delta, float), np.asarray(rate, float)
    if (delta.ndim != 1 or delta.shape != rate.shape or delta.size == 0
            or not np.isfinite([delta, rate]).all() or not np.isfinite(step) or step <= 0):
        raise ValueError('Require matching finite inventories and rates')
    residual = delta-step*rate
    denominator = float(rate @ rate)
    return dict(hypothesis_step_s=step, least_squares_step_s=float(delta @ rate/denominator) if denominator else None,
                maximum_abs_residual=float(abs(residual).max()), residual=residual.tolist())


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def quantity(value, unit, target_unit):
    result = float(value) if unit == target_unit else float(convert(value, unit, target_unit))
    if not np.isfinite(result): raise ValueError('Nonfinite physical parameter')
    return result


def audit(repo):
    root = repo/'outputs_storage_audit'/EXPERIMENT
    execution_path = root/'cold_chamber_execution.json'; execution = read(execution_path)
    if (execution['execution_commit'] != PRODUCER or not execution['collection_pass'] or execution['stop_time_s'] != .2
            or execution['start_time_s'] != 0 or execution['inventory_formulation'] != 'specific_inventory'
            or execution['checkpoint_saved'] or execution['c200_state_imported'] or execution['production_recovery_allowed']):
        raise ValueError('Wrong cold trajectory provenance')
    files = [execution_path]
    cases = {c['arm']: c for c in execution['cases']}
    if set(cases) != {'native', 'conservative'} or len(execution['cases']) != 2:
        raise ValueError('Incomplete paired trajectory')
    for arm in cases:
        path = root/arm/'observations.mat'; files.append(path)
        if sha256(path) != cases[arm]['observation_sha256']: raise ValueError('Raw trajectory changed')
    top_paths = [root/a/'tl_connectivity.json' for a in ('native', 'conservative')]
    native_top, candidate_top = map(read, top_paths); files += top_paths
    domains = topology_check(native_top, candidate_top, 'ecc_inventory_specific.conservative_chamber')
    meta_path = root/'conservative/inventory_metadata.json'; meta = read(meta_path); files.append(meta_path)
    native_meta_path = root/'native/inventory_metadata.json'; native_meta = read(native_meta_path); files.append(native_meta_path)
    if meta['settings_tables'] != native_meta['settings_tables']: raise ValueError('Fluid tables changed')
    tables = {b['block_path']: energy_tables(b['parameters']) for b in meta['settings_tables']}
    contracts_path = root/'conservative/buffer_replacement_contract.json'; files.append(contracts_path)
    contracts = {c['block_path']: c for c in read(contracts_path)['buffers']}
    targets_path = root/'conservative/public_inventory_targets.json'; targets = read(targets_path); files.append(targets_path)
    if targets['has_private_data'] or targets['source_time_s'] != 0 or targets['source_sha256'] != cases['native']['observation_sha256']:
        raise ValueError('Not an independent same-run public cold target')
    target = {(r['block_path'], r['state_name']): r for r in targets['targets']}
    if len(target) != 204 or len(targets['targets']) != 204: raise ValueError('Incomplete target coordinates')
    rows = []; seen = set(); property_rows = []
    with h5py.File(root/'native/observations.mat') as f, h5py.File(root/'conservative/observations.mat') as g:
        native = checked_rows(f, 'native', 1240, stop=.2)
        actual = checked_rows(g, 'native', 1258, stop=.2)
        def initial(data, path, name, unit):
            return float(scalar_series(data[path, name], unit)[0])
        def expected(path, name, unit):
            t = target[path, name]
            return quantity(t['value'], t['unit'], unit)
        for block in meta['storage_blocks']:
            p = block['block_path']; kind = block['mask_type']; par = block['mask_parameters']
            if p in seen: raise ValueError('Repeated storage component')
            seen.add(p)
            if kind == 'Pipe (TL)':
                mode = block['model_modes']
                if mode['dynamic_compressibility'] != 'false': raise ValueError('Wrong pipe dynamics')
                table = tables[domains[p]]
                nominal_t = scalar(mode['T_nominal'], mode['T_nominal_unit'], 'K')
                nominal_p = scalar(mode['p_nominal'], mode['p_nominal_unit'], 'Pa')
                mass = float(table['rho']([[nominal_t, nominal_p]])[0])*quantity(par['area']['value'],par['area']['unit'],'m^2')*quantity(par['length']['value'],par['length']['unit'],'m')
                before = mass*initial(native,p,'u_I','J/kg'); after = mass*initial(actual,p,'u_I','J/kg')
                if not compare_initial(initial(native,p,'u_I','J/kg'),expected(p,'u_I','J/kg'))['within_strict_comparison']:
                    raise ValueError('Pipe target differs from native source')
                # Separate constitutive error from target displacement.
                native_t = initial(native,p,'T_I','K'); native_p = initial(native,p,'p_I','Pa')
                actual_t = initial(actual,p,'T_I','K'); actual_p = initial(actual,p,'p_I','Pa')
                u_native = float(table['u']([[native_t,native_p]])[0]); u_actual = float(table['u']([[actual_t,actual_p]])[0])
                u_pressure_only = float(table['u']([[native_t,actual_p]])[0])
                property_rows.append(dict(block_path=p, native_u_error_J_kg=u_native-initial(native,p,'u_I','J/kg'),
                    actual_u_error_J_kg=u_actual-initial(actual,p,'u_I','J/kg'),
                    pressure_only_change_J_kg=u_pressure_only-u_native,
                    actual_u_change_J_kg=initial(actual,p,'u_I','J/kg')-initial(native,p,'u_I','J/kg'),
                    temperature_change_K=actual_t-native_t, pressure_change_Pa=actual_p-native_p))
            elif kind == 'Thermal Mass':
                capacity = quantity(par['mass']['value'],par['mass']['unit'],'kg')*quantity(par['sp_heat']['value'],par['sp_heat']['unit'],'J/(K*kg)')
                before = capacity*initial(native,p,'T','K'); after = capacity*initial(actual,p,'T','K')
                if not compare_initial(initial(native,p,'T','K'),expected(p,'T','K'))['within_strict_comparison']:
                    raise ValueError('Solid target differs from native source')
            elif kind == 'Conservative Buffer (TL)':
                c = contracts[p]; mass = initial(native,p,'mass','kg'); temp = initial(native,p,'T_I','K')
                before = float(inventory(tables[domains[p]],np.array([temp]),np.array([mass]),c['p_environment_Pa'],
                    c['tank_area_m2'],c['gravity_m_s2'],c['reference_temperature_K'],c['auxiliary_depth_m'])['total'][0])
                after = initial(actual,p,'stored_energy','J')
            elif block['conservative_diagnostic']:
                volume = quantity(par['volume']['value'],par['volume']['unit'],'m^3')
                mass = initial(native,p,'rho_I','kg/m^3')*volume
                before = mass*initial(native,p,'u_I','J/kg'); after = initial(actual,p,'stored_energy','J')
            else:
                raise ValueError('Unaccounted storage class')
            flux_names = ('Q',) if kind == 'Thermal Mass' else ('Phi_A','Phi_B','Q_H')
            if kind == 'Conservative Buffer (TL)': flux_names = ('Phi_A','Q_H')
            rate = sum(initial(actual,p,n,'W') for n in flux_names)
            # Difference-first avoids cancellation between large absolute solid energies.
            delta = capacity*(initial(actual,p,'T','K')-initial(native,p,'T','K')) if kind == 'Thermal Mass' else after-before
            if kind == 'Pipe (TL)': delta = mass*(initial(actual,p,'u_I','J/kg')-initial(native,p,'u_I','J/kg'))
            rows.append(dict(block_path=p, kind=kind, inventory='energy', unit='J', delta=delta, rate=rate,
                             expected_delta=HYPOTHESIS_S*rate, residual=delta-HYPOTHESIS_S*rate,
                             equivalent_step_s=delta/rate if abs(rate)>1e-12 else None))
            if kind == 'Conservative Buffer (TL)' or block['conservative_diagnostic']:
                if not compare_initial(before,expected(p,'stored_energy','J'))['within_strict_comparison']:
                    raise ValueError('Inventory source reconstruction differs from target')
                if not compare_initial(mass,expected(p,'stored_mass','kg'))['within_strict_comparison']:
                    raise ValueError('Mass source reconstruction differs from target')
                delta_m = initial(actual,p,'stored_mass','kg')-mass
                names = ('mdot_A',) if kind == 'Conservative Buffer (TL)' else ('mdot_A','mdot_B')
                rate_m = sum(initial(actual,p,n,'kg/s') for n in names)
                rows.append(dict(block_path=p,kind=kind,inventory='mass',unit='kg',delta=delta_m,rate=rate_m,
                    expected_delta=HYPOTHESIS_S*rate_m,residual=delta_m-HYPOTHESIS_S*rate_m,
                    equivalent_step_s=delta_m/rate_m if abs(rate_m)>1e-12 else None))
    if len(seen) != 119 or len(rows) != 125 or len(property_rows) != 67:
        raise ValueError('Incomplete physical inventory coverage')
    grouped = {}
    for name, limit in [('energy',1e-8),('mass',1e-15)]:
        selected = [r for r in rows if r['inventory']==name]
        result = signature([r['delta'] for r in selected],[r['rate'] for r in selected])
        result.pop('residual')
        grouped[name] = dict(**result, count=len(selected), diagnostic_residual_limit=limit,
                             signature_within_limit=result['maximum_abs_residual']<=limit)
    frozen_path = repo/'verification/c200_mainline_freeze_contract.json'; frozen = read(frozen_path); files.append(frozen_path)
    for key in ('result','checkpoint'):
        p=repo/frozen[key+'_relative_path']
        if sha256(p)!=frozen[key+'_sha256']: raise ValueError('C200 authority changed')
        files.append(p)
    return dict(schema='heatdrive_ecc_cold_initial_flux_signature_v1',evidence_audit_pass=True,
        execution_commit=PRODUCER, post_hoc_hypothesis=True, inventory_groups=grouped,
        storage_classes=dict(Counter(r['kind'] for r in rows if r['inventory']=='energy')),
        constitutive_max_abs_error_J_kg=max(abs(r[k]) for r in property_rows for k in ('native_u_error_J_kg','actual_u_error_J_kg')),
        pipe_properties=property_rows, initialization_repair_verified=False,
        solver_internal_step_proven=False, targets_modified=False, time_axis_modified=False,
        production_recovery_allowed=False, full_device_first_law_verified=False, table4_reproduction_claim=False,
        input_sha256={str(p.relative_to(repo)):sha256(p) for p in files}),rows


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output-root',type=Path,required=True)
    args=parser.parse_args()
    if args.output_root.exists(): raise FileExistsError('Never overwrite diagnosis')
    result,rows=audit(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'initial_flux_signature.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    with (args.output_root/'initial_inventory_shift.csv').open('w',newline='',encoding='utf-8') as f:
        writer=csv.DictWriter(f,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
    print(json.dumps({k:v for k,v in result.items() if k not in ('input_sha256','pipe_properties')},indent=2))
    # A diagnostic signature is not a repaired initial-condition gate.
    raise SystemExit(0 if all(r['signature_within_limit'] for r in result['inventory_groups'].values()) else 1)
