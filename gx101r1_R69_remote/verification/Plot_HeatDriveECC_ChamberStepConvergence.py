"""Four separate diagnostics; no production-performance or closure claim."""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--audit', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite a diagnostic figure')
    data = json.loads(args.audit.read_text(encoding='utf-8'))
    if data['schema'] != 'heatdrive_ecc_chamber_step_convergence_v1' or not data['computation_complete']:
        raise ValueError('Require audited component experiment')
    plt.rcParams.update({'font.family': 'DejaVu Sans', 'font.size': 10,
                         'axes.spines.top': False, 'axes.spines.right': False,
                         'savefig.facecolor': 'white'})
    fig, axes = plt.subplots(2, 2, figsize=(10, 7), layout='constrained')
    for temp, color, marker in ((300, '#0072B2', 'o'), (380, '#D55E00', 's')):
        rows = sorted((r for r in data['cases'] if r['initial_temperature_K'] == temp), key=lambda r: r['local_step_s'])
        x = np.array([r['local_step_s'] for r in rows])*1e3
        for ax, key, scale in ((axes[0, 0], 'max_temperature_error_K', 1e6),
                               (axes[0, 1], 'max_pressure_error_Pa', 1),
                               (axes[1, 0], 'native_endpoint_mass_change_kg', 1e9),
                               (axes[1, 1], 'native_endpoint_energy_residual_J', -1e3)):
            ax.plot(x, [r[key]*scale for r in rows], color=color, marker=marker, label=f'{temp} K initial')
        axes[1, 0].axhline(rows[0]['reference_endpoint_mass_change_kg']*1e9, color=color, linestyle='--', linewidth=1)
        axes[1, 1].axhline(-rows[0]['reference_endpoint_energy_residual_J']*1e3, color=color, linestyle='--', linewidth=1)
    titles = ['(a) Temperature error vs independent ODE', '(b) Pressure error vs independent ODE',
              '(c) Closed-port endpoint mass increase', '(d) Endpoint energy excess over 10 J input']
    labels = ['Maximum error (micro-K)', 'Maximum error (Pa)', 'Mass increase (micro-g)', 'Energy excess (mJ)']
    for ax, title, ylabel in zip(axes.flat, titles, labels):
        ax.set(title=title, xlabel='Local BE step (ms)', ylabel=ylabel, xticks=[.25, .5, 1])
        ax.grid(axis='y', alpha=.2)
        ax.legend(frameon=False, fontsize=9)
    for ax in axes[0]:
        ax.set_xscale('log', base=2)
        ax.set_yscale('log', base=2)
        ax.set_xticks([.25, .5, 1], ['0.25', '0.5', '1'])
    fig.suptitle('Isolated water chamber: physical step convergence is not endpoint closure', fontsize=12)
    fig.supxlabel('Six actual Simscape runs, 1 s each. Dashed: same-equation DOP853 limit; not an experimental reference.', fontsize=9)
    fig.savefig(args.output, dpi=220)
    plt.close(fig)


if __name__ == '__main__':
    main()
