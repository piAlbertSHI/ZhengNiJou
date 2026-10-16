"""Separate mean phase, completion time and cold-end spatial traces in a diagnostic PNG."""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256


def plot(source, output):
    manifest = output.with_suffix('.json')
    if output.exists() or manifest.exists():
        raise FileExistsError('Do not overwrite diagnostic figures')
    data = json.loads(source.read_text(encoding='utf-8-sig'))
    if data['rejected_packet_may_propagate'] or data['root_interpolation_allowed']:
        raise ValueError('This figure requires explicitly rejected transient evidence')
    rows = data['cycles']
    cycle = np.array([r['cycle'] for r in rows])
    completion = np.array([r['cold_half_completion_s'] if r['cold_half_completion_s'] is not None else np.nan for r in rows])
    residual = 100*np.array([r['cold_half_min_mean_phase'] for r in rows])
    end = rows[-1]
    last_cycle = end['cycle']
    missing = cycle[~np.isfinite(completion)]
    missing_label = ', '.join('C'+str(c) for c in missing)
    nodes = np.arange(1, 22)
    with plt.rc_context({'font.family': 'DejaVu Sans', 'font.size': 10,
                         'axes.spines.top': False, 'axes.spines.right': False,
                         'axes.labelsize': 10, 'axes.titlesize': 11, 'axes.titleweight': 'bold',
                         'legend.frameon': False, 'savefig.facecolor': 'white'}):
        fig, axes = plt.subplots(2, 2, figsize=(10.8, 7.2), layout='constrained')
        a, b, c, d = axes.ravel()
        a.plot(cycle, residual, 'o-', color='#0072B2', markersize=4)
        a.scatter(cycle[residual > 1], residual[residual > 1], color='#D55E00', zorder=4, label='Completion not reached')
        a.axhline(1, color='0.35', linestyle='--', linewidth=1, label='Original 1% criterion')
        a.set(title='(a) Cold-half residual', xlabel='Total cycle', ylabel='Mean martensite fraction (%)')
        a.legend(loc='upper left', fontsize=8, frameon=True, facecolor='white', edgecolor='white', framealpha=1)
        b.plot(cycle, completion, 'o-', color='#0072B2', markersize=4)
        b.axhline(5, color='0.35', linestyle='--', linewidth=1, label='Cold-half end')
        b.text(.97, .18, missing_label+': no completion event', ha='right', transform=b.transAxes, color='#D55E00', fontsize=9)
        b.set(title='(b) Reverse-transformation deadline', xlabel='Total cycle', ylabel='Time from cold-half start (s)',
              ylim=(min(4.92, float(np.nanmin(completion))-.015), 5.015))
        b.legend(loc='upper left', fontsize=8)
        for ax in (a, b):
            ax.set_xticks(np.unique(np.rint(np.linspace(cycle[0], cycle[-1], 4)).astype(int)))
            ax.set_xlim(cycle[0]-.4, cycle[-1]+.4)
        c.plot(nodes, 100*np.array(end['cold_min_node_phase']), 'o-', color='#D55E00', markersize=4)
        c.set(title=f'(c) C{last_cycle} local residual', xlabel='SE node index', ylabel='Martensite fraction (%)',
              ylim=(-.3, max(15, 110*max(end['cold_min_node_phase']))))
        d.plot(nodes, end['cold_min_node_temperature_K'], 'o-', color='#009E73', markersize=4)
        d.axhline(data['candidate_Tc_K'], color='0.35', linestyle='--', linewidth=1, label='Prescribed CHEX Tc')
        d.set(title=f'(d) C{last_cycle} solid-temperature profile', xlabel='SE node index', ylabel='Temperature (K)')
        d.legend(loc='upper right', fontsize=8)
        for ax in (c, d):
            ax.set_xticks([1, 6, 11, 16, 21])
            ax.set_xlim(.5, 21.5)
        for ax in axes.ravel():
            ax.grid(axis='y', color='0.90', linewidth=.6)
            ax.set_axisbelow(True)
        fig.suptitle(f"Tc = {data['candidate_Tc_K']:.2f} K: transient diagnostic, rejected at C{last_cycle}", fontsize=13)
        output.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(output, dpi=180)
        plt.close(fig)
    record = dict(schema='heatdrive_ecc_phase_rejection_figure_v1', source_path=str(source.resolve()),
        source_sha256=sha256(source), script_sha256=sha256(Path(__file__)),
        png_sha256=sha256(output), final_node_profile_time_s=end['cold_half_min_time_s'],
        missing_completion_events_plotted_as_missing_not_zero=True,
        rejected_transient_only=True, paper_final_figure=False, root_interpolation_allowed=False)
    manifest.write_text(json.dumps(record, indent=2)+'\n', encoding='utf-8', newline='\n')
    return record


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    print(json.dumps(plot(**vars(parser.parse_args())), indent=2))
