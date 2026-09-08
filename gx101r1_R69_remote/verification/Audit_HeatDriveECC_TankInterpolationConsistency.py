"""Separate property interpolation from BE quadrature on retained cold evidence.

Fixed-path quadrature refinement is explicitly not a new time-step simulation.
No property, model, initial condition or production gate is changed.
"""
import argparse
import csv
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_ColdChamberCycle import EXPERIMENT, checked_rows
from Audit_HeatDriveECC_ColdChamberRejection import read
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_NativeAccumulation import energy_tables, ENERGY_ATOL_J_KG
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_TLDomainInventory import resolve_domains, DENSITY_ATOL_KG_M3


def integrate_linear(knots, values, start, stop):
    """Exact oriented integral of a piecewise linear function, splitting knots."""
    knots, values, start, stop = [np.asarray(x, dtype=float) for x in (knots, values, start, stop)]
    if (knots.ndim != 1 or knots.size < 2 or values.shape != knots.shape or
            start.shape != stop.shape or not all(np.isfinite(x).all() for x in (knots, values, start, stop)) or
            np.any(np.diff(knots) <= 0) or np.any(start < knots[0]) or np.any(stop < knots[0]) or
            np.any(start > knots[-1]) or np.any(stop > knots[-1])):
        raise ValueError('Invalid piecewise-linear integral domain')
    result = np.zeros_like(start)
    lo, hi = np.minimum(start, stop), np.maximum(start, stop)
    for a, b, va, vb in zip(knots[:-1], knots[1:], values[:-1], values[1:]):
        left, right = np.maximum(lo, a), np.minimum(hi, b)
        width = np.maximum(right-left, 0)
        slope = (vb-va)/(b-a)
        result += width*(va + slope*((left-a)+(right-a))*.5)
    return np.sign(stop-start)*result


def fixed_pressure_slice(table, pressure):
    if not np.isfinite(pressure) or not table['u'].grid[1][0] <= pressure <= table['u'].grid[1][-1]:
        raise ValueError('Pressure outside actual property table')
    t = table['u'].grid[0]
    coords = np.column_stack((t, np.full_like(t, pressure)))
    if any(not np.array_equal(table[k].grid[0], t) for k in ('rho', 'cp')):
        raise ValueError('Different property temperature knots')
    return t, {k: table[k](coords) for k in ('u', 'rho', 'cp')}


def enthalpy_derivative(knots, u, rho, pressure, temperature):
    """One-sided cell derivative of linear u + p/(linear rho), not diff(cp)."""
    knots, u, rho, temp = [np.asarray(x, dtype=float) for x in (knots, u, rho, temperature)]
    if (knots.ndim != 1 or knots.size < 2 or u.shape != knots.shape or rho.shape != knots.shape or
            not all(np.isfinite(x).all() for x in (knots, u, rho, temp)) or
            np.any(np.diff(knots) <= 0) or np.any(rho <= 0) or not np.isfinite(pressure) or
            np.any(temp < knots[0]) or np.any(temp > knots[-1])):
        raise ValueError('Invalid enthalpy derivative inputs')
    cell = np.clip(np.searchsorted(knots, temp, side='right')-1, 0, len(knots)-2)
    du = np.diff(u)/np.diff(knots); drho = np.diff(rho)/np.diff(knots)
    density = np.interp(temp, knots, rho)
    return du[cell]-pressure*drho[cell]/density**2


def analyze_path(table, pressure, temperature, mass, native_h, native_rho, native_u):
    temperature, mass, native_h, native_rho, native_u = [np.asarray(x, dtype=float) for x in
        (temperature, mass, native_h, native_rho, native_u)]
    if (temperature.ndim != 1 or temperature.size < 2 or any(v.shape != temperature.shape for v in
            (mass, native_h, native_rho, native_u)) or
            not np.isfinite([temperature, mass, native_h, native_rho, native_u]).all() or np.any(mass <= 0)):
        raise ValueError('Invalid native path')
    knots, fields = fixed_pressure_slice(table, pressure)
    # The native implementation has already passed its independent table audit;
    # check again here before assigning any discrepancy to interpolation.
    interpolated = {k: np.interp(temperature, knots, v) for k, v in fields.items()}
    h = interpolated['u']+pressure/interpolated['rho']
    errors = dict(u_J_kg=float(abs(interpolated['u']-native_u).max()),
                  rho_kg_m3=float(abs(interpolated['rho']-native_rho).max()),
                  h_J_kg=float(abs(h-native_h).max()))
    if (errors['u_J_kg'] > ENERGY_ATOL_J_KG or errors['rho_kg_m3'] > DENSITY_ATOL_KG_M3
            or errors['h_J_kg'] > ENERGY_ATOL_J_KG):
        raise ValueError('Native properties differ from the actual table')
    cp = interpolated['cp']; delta_t = np.diff(temperature)
    exact_cp = integrate_linear(knots, fields['cp'], temperature[:-1], temperature[1:])
    dh = np.diff(native_h)
    quadrature = mass[1:]*(cp[1:]*delta_t-exact_cp)
    interpolation = mass[1:]*(exact_cp-dh)
    original = mass[1:]*(cp[1:]*delta_t-dh)
    if abs((quadrature+interpolation-original)).max() > 1e-11:
        raise ValueError('Quadrature/interpolation decomposition failed')
    derivative = enthalpy_derivative(knots, fields['u'], fields['rho'], pressure, temperature)
    mismatch = cp-derivative
    refinements = []
    for n in (1, 2, 4, 8, 16, 64):
        total = np.zeros_like(delta_t)
        for j in range(1, n+1):
            t = temperature[:-1]+delta_t*j/n
            total += np.interp(t, knots, fields['cp'])*delta_t/n
        refinements.append(dict(subdivisions_per_retained_interval=n,
            weighted_cp_minus_native_dh_J=float(np.sum(mass[1:]*(total-dh))),
            weighted_quadrature_error_J=float(np.sum(mass[1:]*(total-exact_cp))),
            is_new_simulation=False))
    # Independent symmetric finite difference, strictly inside a temperature cell.
    mid = (knots[:-1]+knots[1:])*.5
    eps = np.minimum(np.diff(knots)*1e-4, .001)
    eval_h = lambda t: np.interp(t, knots, fields['u'])+pressure/np.interp(t, knots, fields['rho'])
    numerical = (eval_h(mid+eps)-eval_h(mid-eps))/(2*eps)
    analytic = enthalpy_derivative(knots, fields['u'], fields['rho'], pressure, mid)
    fd_error = float(abs(numerical-analytic).max())
    fd_allowance = 1e-4  # J/(kg K), derivative implementation check only.
    if fd_error > fd_allowance:
        raise ValueError('Analytic property derivative failed independent finite difference')
    result = dict(pressure_Pa=float(pressure), temperature_range_K=[float(temperature.min()), float(temperature.max())],
        samples=len(temperature), native_lookup_max_errors=errors,
        BE_cp_minus_native_dh_weighted_J=float(original.sum()),
        exact_table_interpolation_term_J=float(interpolation.sum()),
        BE_quadrature_term_J=float(quadrature.sum()),
        interpolation_absolute_interval_sum_J=float(abs(interpolation).sum()),
        quadrature_absolute_interval_sum_J=float(abs(quadrature).sum()),
        cp_minus_dh_dT_range_J_kgK=[float(mismatch.min()), float(mismatch.max())],
        cp_minus_dh_dT_max_relative=float(abs(mismatch/derivative).max()),
        derivative_finite_difference_max_error_J_kgK=fd_error,
        derivative_finite_difference_allowance_J_kgK=fd_allowance,
        within_cell_right_derivative_at_knots=True, fixed_path_quadrature_refinements=refinements,
        physical_time_step_convergence_verified=False, model_or_property_table_changed=False)
    rows = [dict(temperature_K=float(t), pressure_Pa=float(pressure), cp_J_kgK=float(c),
                 analytic_dh_dT_J_kgK=float(d), cp_minus_dh_dT_J_kgK=float(c-d))
            for t, c, d in zip(mid, np.interp(mid, knots, fields['cp']), analytic)]
    return result, rows


def audit(repo):
    root = repo/'outputs_storage_audit'/EXPERIMENT
    ledger_path = repo/'outputs_storage_audit/cold_cycle_ledger_20260909_v2/cold_cycle_ledger.json'
    prior = read(ledger_path)
    if not prior['evidence_audit_pass'] or prior['production_recovery_allowed'] or prior['full_device_first_law_verified']:
        raise ValueError('Invalid prior cold diagnostic scope')
    for path, digest in prior['input_sha256'].items():
        if sha256(repo/path) != digest:
            raise ValueError('Prior evidence changed: '+path)
    assignment, count = resolve_domains(read(root/'native/tl_connectivity.json'))
    if count != 2:
        raise ValueError('Unexpected fluid domain count')
    results = []; grid_rows = []
    for arm, expected in (('native', 1240), ('conservative', 1242)):
        meta = read(root/arm/'inventory_metadata.json')
        tables = {r['block_path']: energy_tables(r['parameters']) for r in meta['settings_tables']}
        tanks = [b for b in meta['storage_blocks'] if b['mask_type'] == 'Tank (TL)']
        if len(tanks) != 4 or len({b['block_path'] for b in tanks}) != 4:
            raise ValueError('Incomplete tank coverage')
        baseline = {b['block_path']: b for a in prior['arms'] if a['arm'] == arm for b in a['tank_coefficient_diagnostics']}
        with h5py.File(root/arm/'observations.mat') as f:
            rows = checked_rows(f, 'native', expected)
            for tank in tanks:
                path = tank['block_path']; get = lambda n, u: scalar_series(rows[path, n], u)
                pressure = get('p_I', 'Pa')
                if np.ptp(pressure) > 1e-6:
                    raise ValueError('Require a constant-pressure tank')
                result, mids = analyze_path(tables[assignment[path]], pressure[0], get('T_I', 'K'), get('mass', 'kg'),
                    get('h_I', 'J/kg'), get('rho_I', 'kg/m^3'), get('u_I', 'J/kg'))
                if abs(result['BE_cp_minus_native_dh_weighted_J']-baseline[path]['endpoint_decomposition']['cp_vs_enthalpy_secant_J']) > 1e-8:
                    raise ValueError('Changed prior endpoint decomposition')
                result.update(arm=arm, block_path=path, settings_path=assignment[path])
                results.append(result)
                grid_rows.extend(dict(arm=arm, block_path=path, **r) for r in mids)
    source = Path('C:/Program Files/MATLAB/R2025b/toolbox/physmod/simscape/library/m/+foundation/+thermal_liquid/+utilities/thermal_liquid_settings.ssc')
    result = dict(schema='heatdrive_ecc_tank_interpolation_consistency_v1', evidence_computation_pass=True,
        scope='Exact fixed-pressure table integral on each retained temperature interval, mass held at its original BE endpoint',
        tanks=results, arm_totals={a: {k: sum(r[k] for r in results if r['arm']==a) for k in
            ('BE_cp_minus_native_dh_weighted_J', 'exact_table_interpolation_term_J', 'BE_quadrature_term_J')}
            for a in ('native', 'conservative')},
        native_sample_interpolation_or_replacement=False, fixed_path_quadrature_is_not_a_new_simulation=True,
        physical_time_step_convergence_verified=False, full_device_first_law_verified=False,
        production_recovery_allowed=False, table4_reproduction_claim=False,
        input_sha256={str(ledger_path.relative_to(repo)): sha256(ledger_path), **prior['input_sha256']},
        public_settings_source=dict(path=str(source), sha256=sha256(source),
            relevant_lines='769-775: expanded u then finiteDifference(u+p/rho,T); 857 onward: finiteDifference implementation'))
    return result, grid_rows


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-root', type=Path, required=True)
    args = parser.parse_args()
    if args.output_root.exists():
        raise FileExistsError('Preserve prior evidence')
    result, rows = audit(Path(__file__).resolve().parents[1])
    args.output_root.mkdir(parents=True)
    (args.output_root/'tank_interpolation_audit.json').write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    with (args.output_root/'property_cell_derivatives.csv').open('w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)
    print(json.dumps(dict(evidence_computation_pass=True, arm_totals=result['arm_totals'],
        physical_time_step_convergence_verified=False, production_recovery_allowed=False, output=str(args.output_root)), indent=2))
