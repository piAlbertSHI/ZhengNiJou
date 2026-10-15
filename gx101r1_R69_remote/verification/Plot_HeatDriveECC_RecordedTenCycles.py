"""Separate thermal qualification, cooling rates and unresolved physical inventory drift."""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

from Close_HeatDriveECC_SplitObservation import read
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def plot(measured, thermal, output, cycle_summary=None):
    if any(output.with_suffix(suffix).exists() for suffix in ('.png', '.pdf', '.json')):
        raise FileExistsError('Never overwrite a result figure')
    data, original = read(measured), read(thermal)
    if original['measured_window_sha256'] != sha256(measured) or not original['original_production_statistics_used']:
        raise ValueError('Statistics must describe the same measured window')
    plt.rcParams.update({'font.family': 'Arial', 'font.size': 10, 'axes.titlesize': 11,
                         'axes.labelsize': 10, 'axes.linewidth': .7, 'pdf.fonttype': 42})
    fig, axes = plt.subplots(2, 2, figsize=(12, 8.2), layout='constrained')
    cycles = read(cycle_summary)['cycles'] if cycle_summary else data['cycles']
    x = [row['cycle'] for row in cycles]
    ticks=x[::max(1,len(x)//5)]
    if ticks[-1]!=x[-1]:ticks.append(x[-1])
    axes[0, 0].plot(x, [row['cooling_power_eq10_W'] for row in cycles], 'o-', color='#00796B', label='Eq.10 metric', ms=4)
    axes[0, 0].plot(x, [row['CHEX_sensor_mean_W'] for row in cycles], 's-', color='#B54464', label='CHEX sensor', ms=4)
    axes[0, 0].set(xlabel='Global cycle', ylabel='Cycle-mean cooling rate (W)', title=f'(a) Cooling boundaries | C{cycles[0]["cycle"]}-C{cycles[-1]["cycle"]}')
    axes[0, 0].set_xticks(ticks)
    axes[0, 0].legend(frameon=False, loc='center right', fontsize=9)
    p = original['statistics']
    fields = [('Endpoint T', 'last_cycle_endpoint_drift_K', 'periodic_endpoint_limit_K'),
        ('Same-phase T P99', 'last_cycle_same_phase_temperature_p99_drift_K', 'periodic_same_phase_temperature_p99_limit_K'),
        ('Same-phase T RMS', 'last_cycle_same_phase_temperature_rms_drift_K', 'periodic_same_phase_temperature_rms_limit_K'),
        ('Phase extrema', 'last_cycle_phase_drift', 'periodic_phase_limit'),
        ('Same-phase phase P99', 'last_cycle_same_phase_phase_p99_drift', 'periodic_same_phase_phase_p99_limit'),
        ('Same-phase phase RMS', 'last_cycle_same_phase_phase_rms_drift', 'periodic_same_phase_phase_rms_limit')]
    ratios = [p[value]/p[limit] for _, value, limit in fields]
    axes[0, 1].barh(range(6), ratios, color=['#00796B' if r<=1 else '#B54464' for r in ratios], height=.55)
    axes[0, 1].axvline(1, color='#444444', ls='--', lw=1)
    axes[0, 1].set(yticks=range(6), yticklabels=[row[0] for row in fields], xlim=(0, max(1.16,1.14*max(ratios))),
                   xlabel='Value / unchanged production limit', title='(b) Original public thermal predicates')
    axes[0, 1].invert_yaxis()
    for y, ratio in enumerate(ratios):
        axes[0, 1].text(ratio+.025, y, f'{ratio:.3f}', va='center', fontsize=9)
    names = [('ColdFluidBuffer', 'Cold buffer', '#00796B'), ('HotFluidBuffer', 'Hot buffer', '#B54464'),
             ('SHEXFluidBuffer', 'SHEX buffer', '#356BA3'), ('SMAHotFluidBuffer', 'SMA-hot buffer', '#75623B')]
    first,last=[int(t/10) for t in data['window_s']]
    for name, label, color in names:
        for variable, axis, scale in [('stored_energy', axes[1, 0], 1), ('stored_mass', axes[1, 1], 1e6)]:
            row = next(row for row in data['native_explicit_inventories'] if row['block_path'].endswith('/'+name) and row['variable'] == variable)
            values = np.asarray(row['cycle_endpoints'])
            axis.plot(range(first,last+1), (values-values[0])*scale, 'o-', label=label, color=color, ms=3)
    axes[1, 0].set(xlabel='Global cycle endpoint', ylabel=f'Inventory change from C{first} (J)', title='(c) Buffer energy: drift is not closure error')
    axes[1, 1].set(xlabel='Global cycle endpoint', ylabel=f'Inventory change from C{first} (mg)', title='(d) Conserved but migrating buffer mass')
    axes[1, 0].legend(frameon=False, fontsize=8, ncols=2, loc='upper left')
    axes[1, 1].legend(frameon=False, fontsize=8, ncols=2, loc='upper left')
    for axis in axes.flat:
        axis.spines[['top', 'right']].set_visible(False)
        axis.grid(color='#DDDDDD', lw=.5, axis='x' if axis is axes[0, 1] else 'y')
        axis.set_axisbelow(True)
    prefix='Twenty-cycle advance; ' if cycle_summary else ''
    fig.suptitle(f'C{last} coupled diagnostic | {prefix}panels (b-d): {first*10}-{last*10} s', fontsize=12)
    status='PASS' if p['periodic_steady_state'] else 'NOT YET PASS'
    fig.supxlabel(f'Public thermal criteria: {status}. Complete internal-state closure and Table 4 reproduction are not established.', fontsize=10)
    output.parent.mkdir(parents=True, exist_ok=True)
    for extension in ('.png', '.pdf'):
        fig.savefig(output.with_suffix(extension), dpi=280, facecolor='white')
    plt.close(fig)
    output.with_suffix('.json').write_text(json.dumps(dict(measured_sha256=sha256(measured), thermal_sha256=sha256(thermal),
        png_sha256=sha256(output.with_suffix('.png')), pdf_sha256=sha256(output.with_suffix('.pdf')),
        source_window_s=data['window_s'],cycle_summary_sha256=sha256(cycle_summary) if cycle_summary else '',
        cooling_trace_window_s=[cycles[0]['window_s'][0],cycles[-1]['window_s'][1]],
        physical_tolerances_changed=False, table4_reproduction_claim=False), indent=2)+'\n', encoding='utf-8')


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for key in ('measured', 'thermal', 'output'):
        parser.add_argument('--'+key, required=True, type=Path)
    parser.add_argument('--cycle-summary',type=Path)
    args=parser.parse_args()
    plot(**vars(args))
