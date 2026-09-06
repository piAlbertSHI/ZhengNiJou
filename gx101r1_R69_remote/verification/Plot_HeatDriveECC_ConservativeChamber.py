"""Show signed endpoint defects for the paired one-millisecond trials."""
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
    if not data['sealed_component_inventory_closure_verified'] or data['actual_simscape_cases'] != 24:
        raise ValueError('Require audited paired component evidence')
    plt.rcParams.update({'font.family': 'DejaVu Sans', 'font.size': 10,
                         'axes.spines.top': False, 'axes.spines.right': False})
    fig, axes = plt.subplots(1, 2, figsize=(10, 4.4), layout='constrained')
    labels = ['300 K\n+5 W', '300 K\n-5 W', '380 K\n+5 W', '380 K\n-5 W']
    x = np.arange(4)
    for form, offset, color in [('native', -.16, '#0072B2'), ('conservative', .16, '#009E73')]:
        rows = [r for r in data['cases'] if r['formulation'] == form and r['local_step_s'] == .001]
        for ax, key, scale in [(axes[0], 'mass_endpoint_change_kg', 1e9), (axes[1], 'energy_endpoint_excess_J', 1e3)]:
            y = np.array([r[key] for r in rows])*scale
            ax.bar(x+offset, y, width=.3, color=color, label=form.capitalize())
            ax.plot(x+offset, y, '_', color=color, markersize=12)
    for ax in axes:
        ax.axhline(0, color='black', linewidth=.7)
        ax.set_xticks(x, labels)
        ax.grid(axis='y', alpha=.2)
        ax.legend(frameon=False, loc='upper right', fontsize=9)
    axes[0].set(title='(a) Closed-port mass change', ylabel='Endpoint mass change (micro-g)')
    axes[1].set(title='(b) Energy inventory minus measured heat', ylabel='Endpoint energy excess (mJ)')
    fig.suptitle('Paired native and conservative chambers: 1 ms local BE, 1 s, 2.5 MPa initial', fontsize=11)
    fig.supxlabel('Green marks lie at zero on this scale. Open-flow and full-network validation are not yet complete.', fontsize=9)
    fig.savefig(args.output, dpi=240)
    plt.close(fig)


if __name__ == '__main__':
    main()
