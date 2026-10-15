"""Plot matched measured energy rates separately from their boundary-gap decomposition."""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

from Analyze_HeatDriveECC_CoolingBoundaryReconciliation import read
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def plot(source, output):
    if output.exists() or output.with_suffix('.json').exists():
        raise FileExistsError('Never overwrite a diagnostic figure')
    data = read(source)
    window = data['cooling_boundary_reconciliation']
    duration = window['window_s'][1]-window['window_s'][0]
    balance = window['quadratures']['BE_J']
    energies = balance['energies_J']
    terms = balance['resolved_terms_J']
    plt.rcParams.update({'font.family': 'Arial', 'font.size': 10, 'axes.linewidth': .7,
                         'axes.titlesize': 11, 'axes.labelsize': 10})
    fig, axes = plt.subplots(1, 2, figsize=(11, 4.3), layout='constrained',
                             gridspec_kw={'width_ratios': [1, 1.65]})
    powers = [energies[key]/duration for key in ('eq10', 'sensor', 'native_export_all')]
    bars = axes[0].bar([0, 1, 2], powers, width=.55, color=['#00796B', '#C04B63', '#666666'])
    axes[0].bar_label(bars, labels=[f'{value:.5f}' for value in powers], padding=5, fontsize=9)
    axes[0].set(xticks=[0, 1, 2], xticklabels=['Eq.10\nmetric', 'CHEX\nsensor', 'Native port\nexport'],
                ylim=(0, 14.8), ylabel='Window-mean rate (W)', title='(a) Matched measured window')
    labels = ['Stage-4 metric minus native export', 'Omitted inactive-stage export',
              'Negative fluid-storage change', 'Pipe heat minus sensor', 'Net metric minus sensor']
    values = [terms[key]/duration for key in ('stage4_metric_minus_native_port_export_J',
        'omitted_inactive_native_export_J', 'negative_pipe_storage_change_J', 'pipe_heat_minus_sensor_J')]
    values.append(balance['difference_mean_W'])
    axes[1].barh(range(5), values, color=['#00796B', '#C04B63', '#00796B', '#777777', '#333333'], height=.55)
    for y, value in enumerate(values):
        label = f'{value:+.6f} W' if abs(value) >= 1e-6 else f'{value:+.2e} W'
        axes[1].text(max(value, 0)+.013, y, label, va='center', fontsize=9)
    axes[1].set(yticks=range(5), yticklabels=labels, xlabel='Contribution to the difference (W)',
                title='(b) Different boundaries, not missing heat', xlim=(-.16, .67))
    axes[1].invert_yaxis()
    axes[1].axvline(0, color='#777777', lw=.7)
    for axis in axes:
        axis.spines[['top', 'right']].set_visible(False)
        axis.set_axisbelow(True)
    axes[0].grid(axis='y', color='#DDDDDD', lw=.5)
    axes[1].grid(axis='x', color='#DDDDDD', lw=.5)
    fig.suptitle('C62 cooling-boundary reconciliation | 600-620 s', fontsize=12)
    fig.supxlabel('Native backward-Euler energy rates; storage from independent endpoints. Diagnostic, not a Table 4 endpoint.',
                   fontsize=9)
    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=260, facecolor='white')
    plt.close(fig)
    output.with_suffix('.json').write_text(json.dumps(dict(
        schema='heatdrive_ecc_cooling_boundary_diagnostic_figure_v1', figure_sha256=sha256(output),
        input_sha256=sha256(source), common_window_s=window['window_s'], quadrature='native_BE',
        full_inventory_residual_not_hidden=True, table4_reproduction_claim=False), indent=2)+'\n', encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    plot(args.source, args.output)
