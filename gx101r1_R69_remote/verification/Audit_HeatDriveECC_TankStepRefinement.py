"""Audit real isolated step trials against the continuous native tank equation."""
import argparse
from collections import defaultdict
import csv
import json
from pathlib import Path

import h5py
import numpy as np
from scipy.optimize import brentq

from Audit_HeatDriveECC_ColdChamberCycle import EXPERIMENT
from Audit_HeatDriveECC_ColdChamberRejection import read
from Audit_HeatDriveECC_ColdCoordinateSmoke import compare_initial
from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_NativeWindowLedger import validate_grid
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field
from Audit_HeatDriveECC_TankEnergyBasis import DEAD_HEIGHT_M
from Audit_HeatDriveECC_TankInterpolationConsistency import analyze_path, fixed_pressure_slice, integrate_linear


PRODUCER = '1d02a37c94f1e39ddddacd010434a4e99bcc4037'


def capacity_integral(knots, cp, rho, mass, extra_volume, start, stop):
    """Exact piecewise-quadratic integral of (M + rho*Vextra)*cp dT."""
    knots, cp, rho = [np.asarray(v, dtype=float) for v in (knots, cp, rho)]
    if (not np.isfinite([mass, extra_volume, start, stop]).all() or mass <= 0 or extra_volume < 0 or
            cp.shape != knots.shape or rho.shape != knots.shape or not np.isfinite([cp, rho]).all() or
            np.any(cp <= 0) or np.any(rho <= 0)):
        raise ValueError('Invalid capacity integral')
    # This call checks the domain even when the integration width is zero.
    total = mass*float(integrate_linear(knots, cp, start, stop))
    lo, hi = sorted([start, stop]); sign = np.sign(stop-start)
    for a, b, ca, cb, ra, rb in zip(knots[:-1], knots[1:], cp[:-1], cp[1:], rho[:-1], rho[1:]):
        left, right = max(lo, a), min(hi, b)
        if right <= left:
            continue
        width = right-left
        cs, rs = (cb-ca)/(b-a), (rb-ra)/(b-a)
        cl, rl = ca+cs*(left-a), ra+rs*(left-a)
        total += sign*extra_volume*(cl*rl*width+(cl*rs+rl*cs)*width**2/2+cs*rs*width**3/3)
    return total


def audit(repo):
    root = repo/'outputs_storage_audit/isolated_tank_step_refinement_20260909'
    execution_path = root/'tank_step_execution.json'; execution = read(execution_path)
    if (execution['execution_commit'] != PRODUCER or not execution['collection_pass'] or len(execution['cases']) != 12 or
            any(execution[k] for k in ('checkpoint_loaded', 'checkpoint_saved', 'production_recovery_allowed', 'model_or_property_correction_applied'))):
        raise ValueError('Wrong isolated trial provenance')
    source = repo/'outputs_storage_audit'/EXPERIMENT/'native'
    configuration = source/'configuration.mat'
    if sha256(configuration) != execution['configuration_sha256']:
        raise ValueError('Source options changed')
    metadata = read(source/'inventory_metadata.json')
    tables = {b['block_path']: energy_tables(b['parameters']) for b in metadata['settings_tables']}
    inputs = [execution_path, root/'matlab_diary.log', configuration, source/'inventory_metadata.json']
    results = []; seen = set()
    for c in execution['cases']:
        key = c['source_tank'], c['fixed_step_s']
        if (key in seen or c['fixed_step_s'] not in (.001, .0005, .00025) or c['stop_s'] != .1 or
                c['area_m2'] != .001 or c['initial_volume_m3'] != .0001 or c['heat_into_tank_W'] != 10 or
                c['local_solver'] != 'NE_BACKWARD_EULER_ADVANCER' or not c['closed_mass_port']):
            raise ValueError('Unexpected matrix or trial conditions')
        seen.add(key); path = root/c['file']; inputs.append(path)
        if sha256(path) != c['sha256']:
            raise ValueError('Trial raw hash changed')
        with h5py.File(path) as f:
            saved = json.loads(text_field(f['record_json']))
            if saved != {k: v for k, v in c.items() if k not in ('file', 'sha256')}:
                raise ValueError('Raw trial identity differs from execution record')
            traces = {}
            for ref in f['traces'][:].flat:
                r = f[ref]; name = text_field(r['name'])
                if name in traces:
                    raise ValueError('Duplicate trial leaf')
                t = r['time_s'][:].reshape(-1); validate_grid(t, 0, .1, c['fixed_step_s'])
                if r['values'].shape != (1, len(t)) or not np.isfinite(r['values'][:]).all():
                    raise ValueError('Incomplete finite scalar trial leaf')
                traces[name] = dict(unit=text_field(r['unit']), values=r['values'][:].reshape(-1))
        if set(traces) != {'mass', 'volume', 'T_I', 'p_I', 'rho_I', 'u_I', 'h_I', 'mdot_A', 'Phi_A', 'Q_H'}:
            raise ValueError('Incomplete closed-tank observation')
        get = lambda n, u: convert(traces[n]['values'], traces[n]['unit'], u)
        temp, mass, pressure = get('T_I', 'K'), get('mass', 'kg'), get('p_I', 'Pa')
        rho, u, h, volume = get('rho_I', 'kg/m^3'), get('u_I', 'J/kg'), get('h_I', 'J/kg'), get('volume', 'm^3')
        if (np.any(get('mdot_A', 'kg/s') != 0) or np.any(get('Phi_A', 'W') != 0) or
                np.any(get('Q_H', 'W') != 10) or np.ptp(mass) > 1e-14 or np.ptp(pressure) > 1e-6 or
                abs(volume[0]-.0001) > 1e-12 or abs(temp[0]-c['initial_temperature_K']) > 1e-7 or
                abs(mass-rho*volume).max() > 1e-12):
            raise ValueError('Closed-mass/heat/initialization contract failed')
        table = tables[c['source_settings']]
        split, _ = analyze_path(table, pressure[0], temp, mass, h, rho, u)
        knots, fields = fixed_pressure_slice(table, pressure[0])
        cp = np.interp(temp, knots, fields['cp']); extra_volume = c['area_m2']*DEAD_HEIGHT_M
        extra = float(np.sum(extra_volume*rho[1:]*cp[1:]*np.diff(temp)))
        input_intervals = 10*np.diff(t)
        equation = input_intervals-(mass[1:]+extra_volume*rho[1:])*cp[1:]*np.diff(temp)
        allowance = 16*np.finfo(float).eps*max(temp)*max((mass+extra_volume*rho)*cp)
        equation_pass = bool(np.all(abs(equation) <= allowance))
        heat = float(input_intervals.sum()); endpoint = float(mass[-1]*h[-1]-mass[0]*h[0])
        integral = lambda end: capacity_integral(knots, fields['cp'], fields['rho'], mass[0], extra_volume, temp[0], end)
        continuous_t = brentq(lambda end: integral(end)-heat, temp[0], min(temp[0]+1., knots[-1]), xtol=1e-12, rtol=1e-14)
        continuous_h = np.interp(continuous_t, knots, fields['u'])+pressure[0]/np.interp(continuous_t, knots, fields['rho'])
        initial_h = np.interp(temp[0], knots, fields['u'])+pressure[0]/np.interp(temp[0], knots, fields['rho'])
        continuous_gap = heat-mass[0]*(continuous_h-initial_h)
        continuous_cp = float(integrate_linear(knots, fields['cp'], temp[0], continuous_t))
        continuous_extra = heat-mass[0]*continuous_cp
        row = dict(source_tank=c['source_tank'], source_settings=c['source_settings'], fixed_step_s=c['fixed_step_s'],
            samples=len(t), mass_start_kg=float(mass[0]), volume_start_m3=float(volume[0]), initial_temperature_K=float(temp[0]),
            heat_input_J=heat, end_temperature_K=float(temp[-1]), endpoint_enthalpy_change_J=endpoint,
            raw_endpoint_gap_J=heat-endpoint, extra_capacity_BE_J=extra,
            endpoint_gap_after_extra_coefficient_J=heat-extra-endpoint,
            coefficient_equation_max_interval_residual_J=float(abs(equation).max()),
            coefficient_equation_allowance_J=float(allowance), coefficient_equation_pass=equation_pass,
            continuous_native_equation_end_temperature_K=float(continuous_t),
            end_temperature_minus_continuous_K=float(temp[-1]-continuous_t),
            continuous_native_equation_endpoint_gap_J=float(continuous_gap),
            continuous_gap_after_extra_coefficient_J=float(continuous_gap-continuous_extra),
            continuous_prediction_is_not_a_conservative_physical_model=True,
            fixed_path_property_split=split)
        results.append(row)
    grouped = defaultdict(list)
    for r in results:
        grouped[r['source_tank']].append(r)
    if set(grouped) != {'ColdFluidBuffer', 'HotFluidBuffer', 'SHEXFluidBuffer', 'SMAHotFluidBuffer'}:
        raise ValueError('Incomplete four-tank matrix')
    summary = []
    for name, rows in grouped.items():
        if len(rows) != 3:
            raise ValueError('Incomplete step matrix')
        for key in ('mass_start_kg', 'volume_start_m3', 'initial_temperature_K'):
            if not all(compare_initial(r[key], rows[0][key])['within_strict_comparison'] for r in rows):
                raise ValueError('Initial state differs across step-size trials')
        gaps = [r['endpoint_gap_after_extra_coefficient_J'] for r in rows]
        summary.append(dict(source_tank=name, initial_state_comparison_pass=True,
            steps_s=[r['fixed_step_s'] for r in rows], gap_after_extra_coefficient_J=gaps,
            continuous_gap_after_extra_coefficient_J=rows[0]['continuous_gap_after_extra_coefficient_J'],
            max_temperature_error_against_continuous_K=max(abs(r['end_temperature_minus_continuous_K']) for r in rows),
            gap_spread_J=float(np.ptp(gaps)), all_coefficient_equations_pass=all(r['coefficient_equation_pass'] for r in rows)))
    result = dict(schema='heatdrive_ecc_isolated_tank_step_audit_v1', execution_commit=PRODUCER,
        evidence_computation_pass=True, cases=results, summary=summary, real_simulation_cases=12,
        closed_mass_and_fixed_heat_contract_pass=True, all_coefficient_equations_pass=all(r['coefficient_equation_pass'] for r in results),
        continuous_reference='Closed native equation: integral((M+rho*A*0.001)*cp dT)=Q*t, actual piecewise-linear properties',
        whole_model_time_step_convergence_verified=False, full_device_first_law_verified=False,
        property_correction_applied=False, production_recovery_allowed=False, table4_reproduction_claim=False,
        input_sha256={str(p.relative_to(repo)): sha256(p) for p in inputs})
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-root', type=Path, required=True)
    args = parser.parse_args()
    if args.output_root.exists():
        raise FileExistsError('Preserve prior evidence')
    result = audit(Path(__file__).resolve().parents[1])
    args.output_root.mkdir(parents=True)
    (args.output_root/'tank_step_audit.json').write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    fields = [k for k in result['cases'][0] if k != 'fixed_path_property_split']
    with (args.output_root/'step_comparison.csv').open('w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=fields); writer.writeheader()
        writer.writerows({k: r[k] for k in fields} for r in result['cases'])
    print(json.dumps({k: result[k] for k in ('evidence_computation_pass', 'summary', 'all_coefficient_equations_pass', 'production_recovery_allowed')}, indent=2))
    raise SystemExit(0 if result['all_coefficient_equations_pass'] else 1)
