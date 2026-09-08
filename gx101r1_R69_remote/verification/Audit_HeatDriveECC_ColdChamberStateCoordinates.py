"""Distinguish endpoint conservation from a right-Jacobian differential ledger."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdBufferCoupled import CYCLE_EXPERIMENT, CYCLE_PRODUCER, topology_check
from Audit_HeatDriveECC_ColdChamberRejection import CHAMBERS, read
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_NativeWindowLedger import validate_grid
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def bilinear_gradient(table, temperature, pressure):
    x, y = table.grid; t, p = np.asarray(temperature), np.asarray(pressure)
    if (t.ndim != 1 or t.shape != p.shape or not np.isfinite([t, p]).all() or
            np.any(t < x[0]) or np.any(t > x[-1]) or np.any(p < y[0]) or np.any(p > y[-1])):
        raise ValueError('Invalid in-domain coordinates')
    i = np.clip(np.searchsorted(x, t, side='right')-1, 0, len(x)-2)
    j = np.clip(np.searchsorted(y, p, side='right')-1, 0, len(y)-2)
    a, b = (t-x[i])/(x[i+1]-x[i]), (p-y[j])/(y[j+1]-y[j]); z = table.values
    dt = ((1-b)*(z[i+1, j]-z[i, j])+b*(z[i+1, j+1]-z[i, j+1]))/(x[i+1]-x[i])
    dp = ((1-a)*(z[i, j+1]-z[i, j])+a*(z[i+1, j+1]-z[i+1, j]))/(y[j+1]-y[j])
    return dt, dp


def analyze(repo):
    root = repo/'outputs_storage_audit'/CYCLE_EXPERIMENT
    execution = read(root/'cold_chamber_execution.json')
    if execution['execution_commit'] != CYCLE_PRODUCER or not execution['collection_pass'] or execution['production_recovery_allowed']:
        raise ValueError('Wrong cold experiment')
    raw = root/'conservative/observations.mat'
    if sha256(raw) != execution['cases'][1]['observation_sha256']: raise ValueError('Changed raw evidence')
    assignment = topology_check(read(root/'native/tl_connectivity.json'), read(root/'conservative/tl_connectivity.json'))
    meta = read(root/'conservative/inventory_metadata.json')
    tables = {r['block_path']: energy_tables(r['parameters']) for r in meta['settings_tables']}
    records = []; histories = {}
    with h5py.File(raw) as f:
        rows = named_rows(f, f['native'])
        for path in sorted(CHAMBERS):
            get = lambda n, u: scalar_series(rows[path, n], u)
            time = rows[path, 'T_I']['time_s'][:].reshape(-1); validate_grid(time, 0, 10, .001)
            temp, pressure = get('T_I', 'K'), get('p_I', 'Pa')
            mass, energy = get('stored_mass', 'kg'), get('stored_energy', 'J')
            rho, u = get('rho_I', 'kg/m^3'), get('u_I', 'J/kg')
            volume = next(r['mask_parameters']['volume']['value'] for r in meta['storage_blocks'] if r['block_path'] == path)
            if abs(volume*rho-mass).max() > 1e-15 or abs(mass*u-energy).max() > 1e-8:
                raise ValueError('Native inventory aliases differ')
            rT, rp = bilinear_gradient(tables[assignment[path]]['rho'], temp[1:], pressure[1:])
            uT, up = bilinear_gradient(tables[assignment[path]]['u'], temp[1:], pressure[1:])
            jac_mass = volume*(rT*np.diff(temp)+rp*np.diff(pressure))
            jac_energy = mass[1:]*(uT*np.diff(temp)+up*np.diff(pressure))+u[1:]*jac_mass
            mass_in = (get('mdot_A', 'kg/s')+get('mdot_B', 'kg/s'))[1:]*np.diff(time)
            energy_in = (get('Phi_A', 'W')+get('Phi_B', 'W')+get('Q_H', 'W'))[1:]*np.diff(time)
            dm, de = mass_in-np.diff(mass), energy_in-np.diff(energy)
            jm, je = mass_in-jac_mass, energy_in-jac_energy
            indices = np.argsort(abs(de))[-12:][::-1]; bad = np.flatnonzero(abs(de) > 1e-8)
            row = dict(block_path=path, first_bad_energy_interval_end_s=float(time[bad[0]+1]) if len(bad) else None,
                       failed_energy_intervals=int(len(bad)), endpoint_mass_residual_kg=float(dm.sum()),
                       endpoint_energy_residual_J=float(de.sum()),
                       right_Jacobian_mass_max_interval_residual_kg=float(abs(jm).max()),
                       right_Jacobian_energy_max_interval_residual_J=float(abs(je).max()),
                       right_Jacobian_mass_cumulative_end_residual_kg=float(jm.sum()),
                       right_Jacobian_energy_cumulative_end_residual_J=float(je.sum()),
                       right_Jacobian_agreement_pass=bool(abs(jm).max() <= 1e-15 and abs(je).max() <= 1e-8),
                       largest_intervals=[dict(end_time_s=float(time[i+1]), endpoint_energy_defect_J=float(de[i]),
                           endpoint_mass_defect_kg=float(dm[i]), temperature_before_K=float(temp[i]),
                           temperature_after_K=float(temp[i+1]), pressure_before_Pa=float(pressure[i]),
                           pressure_after_Pa=float(pressure[i+1])) for i in indices])
            records.append(row)
            histories[path] = dict(time=time, energy_endpoint=np.r_[0, np.cumsum(de)], mass_endpoint=np.r_[0, np.cumsum(dm)],
                                   energy_jacobian=np.r_[0, np.cumsum(je)], mass_jacobian=np.r_[0, np.cumsum(jm)])
    files = [raw, root/'cold_chamber_execution.json', root/'conservative/inventory_metadata.json',
             root/'native/tl_connectivity.json', root/'conservative/tl_connectivity.json',
             root/'component_build/+ecc_inventory/conservative_chamber.ssc']
    return dict(schema='heatdrive_ecc_cold_chamber_coordinate_diagnosis_v1', records=records,
                observation='Port inputs match the right-end T,p Jacobian increments, not endpoint M,U increments.',
                interpretation_is_inference=True, compiled_state_selection_exported=False,
                state_selection_hypothesis='Symbolic reduction may have chosen T,p differential coordinates despite der(M),der(U) declarations.',
                next_required_check='Export actual compiled continuous states and independently test a state-coordinate-preserving chamber implementation.',
                simulation_rerun=False, physical_energy_correction_applied=False, scientific_gate_relaxed=False,
                full_device_first_law_verified=False, production_recovery_allowed=False,
                input_sha256={str(p.relative_to(repo)): sha256(p) for p in files}), histories


def figures(out, histories):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    plt.rcParams.update({'font.family': 'DejaVu Serif', 'font.size': 11, 'axes.spines.top': False,
                         'axes.spines.right': False, 'pdf.fonttype': 42})
    fig, axes = plt.subplots(2, 2, figsize=(11, 7), layout='constrained')
    for col, (path, h) in enumerate(sorted(histories.items())):
        name = 'Inlet chamber' if 'Inlet' in path else 'Outlet chamber'
        for row, (kind, scale, unit) in enumerate([('energy', 1, 'J'), ('mass', 1e6, 'mg')]):
            ax = axes[row, col]
            ax.plot(h['time'], h[kind+'_endpoint']*scale, color='#B3261E', lw=1.5, label='Actual inventory endpoint')
            ax.plot(h['time'], h[kind+'_jacobian']*scale, color='#007C78', lw=1.1, ls='--', label='Right-Jacobian diagnostic')
            for t in (3.5, 5, 8.5): ax.axvline(t, color='0.8', lw=.6)
            ax.set(xlabel='Cold-cycle time (s)', ylabel=f'Cumulative {kind} residual ({unit})', title=name)
            ax.set_xlim(0, 10); ax.legend(frameon=False, fontsize=9, loc='lower left')
    fig.suptitle('Rejected cold cycle: differential ledger agreement is not endpoint conservation', fontsize=12)
    for suffix in ('png', 'pdf'): fig.savefig(out/f'FigD01_chamber_coordinate_defect.{suffix}', dpi=220)
    plt.close(fig)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--output-root', type=Path, required=True)
    args = parser.parse_args()
    if args.output_root.exists(): raise FileExistsError('Never overwrite evidence')
    result, histories = analyze(Path(__file__).resolve().parents[1]); args.output_root.mkdir(parents=True)
    (args.output_root/'chamber_coordinate_diagnosis.json').write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    figures(args.output_root, histories)
    print(json.dumps({k: v for k, v in result.items() if k != 'input_sha256'}, indent=2))
    raise SystemExit(0 if all(r['right_Jacobian_agreement_pass'] for r in result['records']) else 1)
