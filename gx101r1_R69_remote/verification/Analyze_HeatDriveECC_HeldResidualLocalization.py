"""Locate measured residual accumulation without reclassifying scientific gates."""
import argparse
import json
from pathlib import Path
import h5py
import numpy as np
from scipy.integrate import cumulative_trapezoid
from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_ColdPassivePSObserver import read, sha256, CHAMBERS, BUFFERS


def localization(t, inventory, flux, limit):
    t, x, f = [np.asarray(v, dtype=float) for v in (t, inventory, flux)]
    if (t.ndim != 1 or len(t) < 2 or x.shape != t.shape or f.shape != t.shape
            or not np.isfinite([t, x, f]).all() or t[0] != 0 or t[-1] != .04
            or np.any(np.diff(t) <= 0) or not np.isfinite(limit) or limit <= 0):
        raise ValueError('Require complete finite held-interval histories')
    change = x - x[0]
    residual = change - cumulative_trapezoid(f, t, initial=0)
    increment = np.diff(residual)
    selected = sorted(set(np.searchsorted(t, [0, .001, .01, .02, .04]).tolist()))
    peak = int(np.argmax(abs(increment)))
    return dict(initial_inventory=float(x[0]), endpoint_inventory_change=float(change[-1]),
                fractional_inventory_change=None if x[0] == 0 else float(change[-1]/x[0]),
                maximum_absolute_residual=float(np.max(abs(residual))),
                first_interval_residual=float(residual[1]),
                largest_residual_increment=float(increment[peak]),
                largest_increment_interval_s=[float(t[peak]), float(t[peak+1])],
                maximum_residual_first_ms=float(np.max(abs(residual[t <= .001]))),
                scientific_limit=limit, scientific_gate_pass=bool(np.all(abs(residual) <= limit)),
                selected_actual_samples=[dict(time_s=float(t[i]), inventory_change=float(change[i]),
                    flux=float(f[i]), residual=float(residual[i])) for i in selected],
                solver_error_source_identified=False)


def analyze(repo):
    root = repo/'outputs_storage_audit/specific_inventory_hybrid_held_moderate_control_20260910'
    ap = repo/'outputs_storage_audit/hybrid_held_moderate_control_audit_20260910/held_interval_audit.json'
    audit = read(ap)
    for relative, expected in audit['input_sha256'].items():
        if sha256(repo/relative) != expected: raise ValueError('Audit dependency changed')
    if audit['numerical_case'] != 'moderate_control' or not audit['evidence_audit_pass']:
        raise ValueError('Wrong evidence baseline')
    raw = root/'observations.mat'; result = []
    with h5py.File(raw) as f:
        rows = named_rows(f, f['native'])
        for name in sorted(CHAMBERS | BUFFERS):
            path = 'heatdrive_ecc_coupled_se21/' + name
            get = lambda n, u: scalar_series(rows[path,n], u)
            t = rows[path,'stored_mass']['time_s'][:].ravel()
            mf = get('mdot_A','kg/s'); power = get('Phi_A','W') + get('Q_H','W')
            if name in CHAMBERS:
                mf = mf + get('mdot_B','kg/s'); power = power + get('Phi_B','W')
            mass = localization(t, get('stored_mass','kg'), mf, 1e-15)
            energy = localization(t, get('stored_energy','J'), power, 1e-8)
            prior = next(r for r in audit['local_balances'] if r['block_path'] == path)
            if (mass['maximum_absolute_residual'] != prior['mass_max_abs_residual_kg']
                    or energy['maximum_absolute_residual'] != prior['energy_max_abs_residual_J']):
                raise ValueError('Residual calculation disagrees with original gate')
            result.append(dict(block_path=path, exported_sample_count=len(t),
                minimum_exported_dt_s=float(np.diff(t).min()), maximum_exported_dt_s=float(np.diff(t).max()),
                mass_kg=mass, energy_J=energy))
    return dict(component_residual_localization=result,
                input_sha256={str(p.relative_to(repo)):sha256(p) for p in (ap,raw)},
                actual_internal_solver_mesh_certified=False, unique_root_cause_verified=False,
                local_balance_gate=audit['local_balance_gate'], production_recovery_allowed=False,
                table4_reproduction_claim=False)


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output-root',type=Path,required=True);args=p.parse_args()
    if args.output_root.exists(): raise FileExistsError('Never overwrite evidence')
    report=analyze(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'residual_localization.json').write_text(json.dumps(report,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k!='component_residual_localization'},indent=2))
