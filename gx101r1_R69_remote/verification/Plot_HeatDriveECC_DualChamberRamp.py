"""Plot measured finite-actuation diagnostics, never corrected physical gates."""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

from Audit_HeatDriveECC_DualChamberSwitchResult import read_case
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists() or args.output.with_suffix('.pdf').exists():
        raise FileExistsError('Do not overwrite figures')
    base = args.repo / 'outputs_storage_audit'
    modes = [('ramp', 'Original tolerance', '#0072B2', 'o'),
             ('projection', 'Projection', '#009E73', 's'),
             ('tight', 'Tight tolerance', '#CC3311', '^')]
    audits = {key: json.loads((base / f'dual_chamber_{key}_20260907' /
                              f'{key}_audit_v1.json').read_text()) for key, *_ in modes}
    root = base / 'dual_chamber_tight_20260907'
    path = root / 'trial/case_7.mat'
    if sha256(path) != audits['tight']['input_sha256']['case_7']:
        raise ValueError('Trajectory hash changed')
    _, t, p = read_case(path, finite_transition=True)
    coordinate = json.loads((root / 'coordinate_diagnosis_v1.json').read_text())
    if coordinate['source_audit_sha256'] != sha256(root / 'tight_audit_v1.json'):
        raise ValueError('Coordinate source changed')
    plt.rcParams.update({'font.family': 'DejaVu Sans', 'font.size': 10,
                         'axes.spines.top': False, 'axes.spines.right': False,
                         'pdf.fonttype': 42})
    fig, axes = plt.subplots(2, 2, figsize=(11, 8), layout='constrained')
    ax = axes[0, 0]
    for role, label, color, style in [('v1', 'Hot V1/V3', '#0072B2', '-'),
                                      ('v2', 'Cold V2/V4', '#CC3311', '--')]:
        ax.plot(t, p[role]['L'], color=color, linestyle=style, label=label)
    ax.set(xlim=(.49, .52), ylim=(-.05, 1.08), xlabel='Time (s)', ylabel='Valve opening (-)',
           title='(a) Measured 10 ms actuation')
    ax.legend(frameon=False, fontsize=9)
    ax = axes[0, 1]
    for role, signal, label, color, style in [('inlet', 'T_I', 'Inlet chamber', '#0072B2', '-'),
                                             ('outlet', 'T_I', 'Outlet chamber', '#009E73', '-'),
                                             ('v3', 'B.T', 'V3 outlet port', '#CC3311', '--')]:
        ax.plot(t, p[role][signal], color=color, linestyle=style, label=label)
    ax.axhline(273.16, color='#555555', linestyle=':', label='Table lower bound')
    ax.set(xlim=(0, 1), xlabel='Time (s)', ylabel='Temperature (K)',
           title='(b) Finite-actuation thermal response')
    ax.legend(frameon=False, fontsize=8, loc='lower left', bbox_to_anchor=(0, .17))
    ax = axes[1, 0]
    for key, label, color, marker in modes:
        rows = audits[key]['cases'][6:9]
        x = [r['local_step_s'] * 1000 for r in rows]
        y = [max(v['energy_max_abs_residual_J'] for v in r['ledgers'].values()) for r in rows]
        ax.semilogy(x, y, color=color, marker=marker, label=label)
    ax.axhline(1e-8, color='#555555', linestyle=':', label='Unchanged inventory gate')
    ax.set(xticks=[.25, .5, 1], xlabel='Local BE step (ms)', ylabel='Max. inventory residual (J)',
           title='(c) Conservative chamber, pump power none', ylim=(3e-9, 1))
    ax.legend(frameon=False, fontsize=8, loc='center right')
    ax = axes[1, 1]
    selected = [r for r in coordinate['cases'] if r['case_index'] == 7]
    x = np.arange(2)
    within = [r['within_cell_energy_bridge_J'] for r in selected]
    crossing = [r['crossing_cell_energy_bridge_J'] for r in selected]
    ax.bar(x, within, width=.5, color='#0072B2', label='Within-cell difference')
    ax.bar(x, crossing, bottom=within, width=.5, color='#E69F00', label='Cell-crossing difference')
    physical = [audits['tight']['cases'][6]['ledgers'][r['role'] + '_table']['energy_final_residual_J']
                for r in selected]
    ax.scatter(x, physical, marker='_', s=260, color='black', linewidths=2,
               label='Unmodified physical residual', zorder=4)
    ax.set(xticks=x, xticklabels=['Inlet', 'Outlet'], ylabel='Endpoint energy difference (J)',
           ylim=(0, .135), title='(d) TP-coordinate explanation, tight 1 ms')
    ax.legend(frameon=False, fontsize=8, loc='upper right')
    for ax in axes.flat:
        ax.grid(axis='y', alpha=.18)
        ax.set_axisbelow(True)
    fig.suptitle('Dual-chamber diagnostic: completed simulations, failed inventory closure', fontsize=12)
    fig.savefig(args.output, dpi=240)
    fig.savefig(args.output.with_suffix('.pdf'))
    plt.close(fig)


if __name__ == '__main__':
    main()
