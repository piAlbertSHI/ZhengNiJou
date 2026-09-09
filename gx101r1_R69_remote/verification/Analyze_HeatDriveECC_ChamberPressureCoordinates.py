"""Compute table-exact local pressure derivatives at prescribed cold coordinates.

This audits the inventory coordinate transformation, not the compiled DAE rank.
No trajectory or operating point is created.
"""
import argparse
import csv
import json
from pathlib import Path
import numpy as np
from Audit_HeatDriveECC_ColdBufferCoupled import topology_check, CYCLE_EXPERIMENT, CYCLE_PRODUCER
from Audit_HeatDriveECC_ColdChamberRejection import read, CHAMBERS
from Audit_HeatDriveECC_ColdChamberStateCoordinates import bilinear_gradient
from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def inventory_jacobian(rho, u, rho_t, rho_p, u_t, u_p, volume):
    inputs = np.asarray([rho, u, rho_t, rho_p, u_t, u_p, volume], dtype=float)
    if not np.isfinite(inputs).all() or rho <= 0 or volume <= 0:
        raise ValueError('Invalid thermodynamic inputs')
    return volume * np.array([[rho_t, rho_p], [u*rho_t+rho*u_t, u*rho_p+rho*u_p]])


def pressure_map(jacobian, inventory_scales, coordinate_scales):
    j = np.asarray(jacobian, dtype=float)
    a, b = np.asarray(inventory_scales, dtype=float), np.asarray(coordinate_scales, dtype=float)
    if (j.shape != (2, 2) or a.shape != (2,) or b.shape != (2,)
            or not np.isfinite(j).all() or not np.isfinite([a, b]).all()
            or np.any(a <= 0) or np.any(b <= 0)):
        raise ValueError('Invalid Jacobian/scales')
    scaled = j * b[None, :] / a[:, None]
    singular = np.linalg.svd(scaled, compute_uv=False)
    if singular[-1] <= np.finfo(float).eps * 2 * singular[0]:
        raise ValueError('Singular local inventory coordinate map')
    scaled_inverse = np.linalg.inv(scaled)
    inverse = b[:, None]*scaled_inverse/a[None, :]
    return dict(jacobian_MU_by_Tp_SI=j.tolist(), inverse_Tp_by_MU_SI=inverse.tolist(),
                pressure_derivative_Pa_per_kg=float(inverse[1, 0]),
                pressure_derivative_Pa_per_J=float(inverse[1, 1]),
                inventory_scales_kg_J=a.tolist(), coordinate_scales_K_Pa=b.tolist(),
                dimensionless_jacobian=scaled.tolist(), dimensionless_singular_values=singular.tolist(),
                dimensionless_condition_number=float(singular[0]/singular[-1]),
                dimensionless_inverse_identity_max_abs_error=float(np.max(abs(scaled_inverse@scaled-np.eye(2)))),
                inverse_identity_max_abs_error=float(np.max(abs(inverse@j-np.eye(2)))))


def finite_difference_check(table, t, p, volume, jacobian):
    def stored(temp, pressure):
        rho = float(table['rho']([[temp, pressure]])[0])
        u = float(table['u']([[temp, pressure]])[0])
        return np.array([volume*rho, volume*rho*u])
    tgrid, pgrid = table['rho'].grid
    i = int(np.clip(np.searchsorted(tgrid, t, side='right')-1, 0, len(tgrid)-2))
    j = int(np.clip(np.searchsorted(pgrid, p, side='right')-1, 0, len(pgrid)-2))
    # Stay inside the exact cell chosen by the production bilinear gradient.
    t_sign = 1 if tgrid[i+1]-t >= t-tgrid[i] else -1
    p_sign = 1 if pgrid[j+1]-p >= p-pgrid[j] else -1
    t_room = tgrid[i+1]-t if t_sign == 1 else t-tgrid[i]
    p_room = pgrid[j+1]-p if p_sign == 1 else p-pgrid[j]
    rows = []
    for factor in (1., .1, .01):
        dt = t_sign*min(.01, t_room/4)*factor
        dp = p_sign*min(100., p_room/4)*factor
        fd = np.column_stack(((stored(t+dt, p)-stored(t, p))/dt,
                              (stored(t, p+dp)-stored(t, p))/dp))
        relative = abs(fd-jacobian)/np.maximum(abs(jacobian), 1e-30)
        rows.append(dict(temperature_step_K=float(dt), pressure_step_Pa=float(dp),
                         max_entry_relative_error=float(relative.max()), fd_jacobian_SI=fd.tolist()))
    return rows


def analyze(repo):
    root = repo/'outputs_storage_audit'/CYCLE_EXPERIMENT
    execution_path = root/'cold_chamber_execution.json'
    execution = read(execution_path)
    if execution['execution_commit'] != CYCLE_PRODUCER or not execution['collection_pass']:
        raise ValueError('Wrong reference experiment')
    raw = root/'native/observations.mat'
    if sha256(raw) != execution['cases'][0]['observation_sha256']:
        raise ValueError('Cold reference changed')
    paths = [root/a/'tl_connectivity.json' for a in ('native', 'conservative')]
    assignment = topology_check(*map(read, paths))
    meta_path = root/'conservative/inventory_metadata.json'
    meta = read(meta_path)
    table_by_path = {r['block_path']: energy_tables(r['parameters']) for r in meta['settings_tables']}
    target_path = root/'conservative/public_inventory_targets.json'
    target_record = read(target_path)
    if target_record['source_sha256'] != sha256(raw) or target_record['has_private_data']:
        raise ValueError('Invalid cold target provenance')
    targets = {(r['block_path'], r['state_name']): r for r in target_record['targets']}
    blocks = {r['block_path']: r for r in meta['storage_blocks']}
    results, csv_rows = [], []
    for path in sorted(CHAMBERS):
        def target(name, unit):
            r = targets[path, name]
            if r['source_time_s'] != 0:
                raise ValueError('Noninitial target')
            return float(convert(np.array([r['value']]), r['unit'], unit)[0])
        t, p = target('T_I', 'K'), target('p_I', 'Pa')
        table = table_by_path[assignment[path]]
        rho, u = (float(table[key]([[t, p]])[0]) for key in ('rho', 'u'))
        parameter = blocks[path]['mask_parameters']['volume']
        volume = float(convert(np.array([parameter['value']]), parameter['unit'], 'm^3')[0])
        mass, energy = volume*rho, volume*rho*u
        if abs(mass-target('stored_mass', 'kg')) > 1e-15 or abs(energy-target('stored_energy', 'J')) > 1e-8:
            raise ValueError('Reconstructed inventories differ from the declared targets')
        rho_t, rho_p = (float(v[0]) for v in bilinear_gradient(table['rho'], np.array([t]), np.array([p])))
        u_t, u_p = (float(v[0]) for v in bilinear_gradient(table['u'], np.array([t]), np.array([p])))
        jacobian = inventory_jacobian(rho, u, rho_t, rho_p, u_t, u_p, volume)
        result = pressure_map(jacobian, [mass, abs(energy)], [1., 1e6])
        checks = finite_difference_check(table, t, p, volume, jacobian)
        result.update(block_path=path, settings_path=assignment[path], prescribed_temperature_K=t,
                      prescribed_pressure_Pa=p, volume_m3=volume, mass_kg=mass, energy_J=energy,
                      density_kg_m3=rho, internal_energy_J_kg=u, finite_difference_checks=checks,
                      finite_difference_limit_relative=1e-4,
                      coordinate_derivative_check_pass=(checks[-1]['max_entry_relative_error'] <= 1e-4
                                                        and result['dimensionless_inverse_identity_max_abs_error'] <= 1e-10))
        results.append(result)
        csv_rows.append({k: result[k] for k in ('block_path', 'prescribed_temperature_K', 'prescribed_pressure_Pa',
            'mass_kg', 'energy_J', 'pressure_derivative_Pa_per_kg', 'pressure_derivative_Pa_per_J',
            'dimensionless_condition_number', 'coordinate_derivative_check_pass')})
    chamber = repo/'verification/simscape_inventory_specific/+ecc_inventory_specific/conservative_chamber.ssc'
    text = chamber.read_text(encoding='utf-8')
    for equation in ('rho_I == stored_mass / volume;', 'u_I == stored_energy / stored_mass;',
                     'der(stored_mass) == mdot_A + mdot_B;', 'der(stored_energy) == Phi_A + Phi_B + Q_H;'):
        if equation not in text:
            raise ValueError('Inventory differential equations changed')
    files = [execution_path, raw, *paths, meta_path, target_path, chamber]
    freeze_path = repo/'verification/c200_mainline_freeze_contract.json'
    freeze = read(freeze_path)
    files.append(freeze_path)
    for key in ('result', 'checkpoint'):
        path = repo/freeze[key+'_relative_path']
        if sha256(path) != freeze[key+'_sha256']:
            raise ValueError('Frozen C200 evidence changed')
        files.append(path)
    return dict(schema='heatdrive_ecc_chamber_pressure_coordinates_v2',
                coordinate_derivative_audit_pass=all(r['coordinate_derivative_check_pass'] for r in results),
                inverse_residual_basis='dimensionless scaled inventory-coordinate map; dimensional residual retained diagnostically',
                coordinate_source='prescribed public cold targets, not failed PS-run observations',
                records=results, pressure_rate_identity='pdot = dp_dM*(mdot_A+mdot_B) + dp_dU*(Phi_A+Phi_B+Q_H)',
                complete_compiled_DAE_rank_verified=False, actual_failed_DAE_matrix_extracted=False,
                initial_solver_repaired=False, trajectory_conservation_verified=False,
                production_recovery_allowed=False, full_device_first_law_verified=False,
                input_sha256={str(p.relative_to(repo)): sha256(p) for p in files}), csv_rows


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-root', type=Path, required=True)
    args = parser.parse_args()
    if args.output_root.exists():
        raise FileExistsError('Never overwrite evidence')
    result, rows = analyze(Path(__file__).resolve().parents[1])
    args.output_root.mkdir(parents=True)
    (args.output_root/'pressure_coordinates.json').write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    with (args.output_root/'pressure_coordinates.csv').open('w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)
    print(json.dumps({k: v for k, v in result.items() if k != 'input_sha256'}, indent=2))
    raise SystemExit(0 if result['coordinate_derivative_audit_pass'] else 1)
