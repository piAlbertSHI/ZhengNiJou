"""Traceable cold diagnostic figures; no publication qualification claim."""
import argparse
import json
from pathlib import Path

import h5py
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

from Audit_HeatDriveECC_ColdChamberCycle import EXPERIMENT
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def plot(repo, audit_path, output):
    data = json.loads(audit_path.read_text(encoding='utf-8'))
    if not data['evidence_audit_pass'] or data['production_recovery_allowed']:
        raise ValueError('Wrong diagnostic scope')
    for path, digest in data['input_sha256'].items():
        if sha256(repo/path) != digest:
            raise ValueError('Audit input changed: '+path)
    output.mkdir(parents=True, exist_ok=False)
    plt.rcParams.update({'font.family': 'DejaVu Sans', 'font.size': 9, 'axes.titlesize': 10,
        'axes.labelsize': 9, 'legend.fontsize': 8, 'pdf.fonttype': 42, 'ps.fonttype': 42,
        'axes.spines.top': False, 'axes.spines.right': False, 'savefig.facecolor': 'white'})
    files = []; checks = []
    def save(fig, name, meaning):
        fig.canvas.draw()
        renderer = fig.canvas.get_renderer()
        outside = []
        labels = list(fig.texts)
        for ax in fig.axes:
            labels.extend([ax.title, ax.xaxis.label, ax.yaxis.label, *ax.texts])
            for axis in (ax.xaxis, ax.yaxis):
                lo, hi = sorted(axis.get_view_interval())
                # Matplotlib creates ticks outside the view but does not draw them.
                for tick in axis.get_major_ticks():
                    if lo <= tick.get_loc() <= hi:
                        labels.extend([tick.label1, tick.label2])
            if ax.get_legend():
                labels.extend(ax.get_legend().get_texts())
        for label in labels:
            if not label.get_visible() or not label.get_text():
                continue
            b = label.get_window_extent(renderer)
            if b.x0 < -1 or b.y0 < -1 or b.x1 > fig.bbox.width+1 or b.y1 > fig.bbox.height+1:
                outside.append(label.get_text())
        if outside:
            raise ValueError('Text outside figure: '+repr(outside))
        for ext in ('png', 'pdf'):
            path = output/(name+'.'+ext)
            fig.savefig(path, dpi=300)
            files.append(path)
        checks.append(dict(figure=name, no_text_outside_canvas=True, meaning=meaning))
        plt.close(fig)
    arms = data['arms']; colors = ['#666666', '#007C78']
    fig, ax = plt.subplots(figsize=(7.1, 3.7), layout='constrained')
    kinds = ['119-storage model CV', 'Two connecting chambers', 'Four buffers']
    y = np.arange(3)
    for i, a in enumerate(arms):
        values = [a['source_minus_actual_endpoint_storage_J'],
                  a['component_groups']['Constant Volume Chamber (TL)']['endpoint_energy_residual_J'],
                  a['component_groups']['Tank (TL)']['endpoint_energy_residual_J']]
        bars = ax.barh(y+(i-.5)*.3, values, height=.28, color=colors[i], label=a['arm'].capitalize())
        for bar, v in zip(bars, values):
            ax.text(v-.015 if v < -.5 else .025, bar.get_y()+bar.get_height()/2,
                    f'{v:.5f}' if abs(v)>1e-6 else f'{v:.2e}',
                    ha='right' if v < -.5 else 'left', va='center', fontsize=8)
    ax.set(yticks=y, yticklabels=kinds, xlim=(-1.38, .21),
           xlabel='Net input minus actual endpoint storage (J)',
           title='Cold cycle, 0-10 s: endpoint residual localization')
    ax.axvline(0, color='black', lw=.7); ax.invert_yaxis()
    ax.legend(loc='lower left', frameon=False)
    save(fig, 'FigC01_endpoint_residuals',
         'Each arm uses its own actual initial state. Pipes and thermal masses sum below 3e-9 J. Not an equal-initial-state performance comparison.')
    fig, axes = plt.subplots(2, 2, figsize=(7.1, 5.2), sharey=True, layout='constrained')
    terms = ['Extra\ncapacity', 'Negative\nhead', 'cp versus\nh secant', 'Discrete\nproduct', 'Endpoint\nresidual']
    for ax, t in zip(axes.flat, arms[1]['tank_coefficient_diagnostics']):
        split = t['endpoint_decomposition']
        values = [t['extra_BE_accumulation_J'], -t['hydrostatic_internal_transport_BE_J'],
                  split['cp_vs_enthalpy_secant_J'], split['discrete_product_term_J'], t['endpoint_residual_J']]
        ax.bar(np.arange(5), values, color=['#777777', '#4477AA', '#CC6677', '#AA3377', '#007C78'], width=.68)
        ax.axhline(0, color='black', lw=.6)
        ax.set(xticks=np.arange(5), xticklabels=terms, ylim=(-.255, .235),
               title=t['block_path'].split('/')[-1], ylabel='Energy term (J)')
        ax.tick_params(axis='x', labelsize=7)
        for i, v in enumerate(values):
            ax.text(i, v+(0.009 if v>=0 else -.009), f'{v:.3f}' if abs(v)>.001 else f'{v:.1e}',
                    ha='center', va='bottom' if v>=0 else 'top', fontsize=7)
    fig.suptitle('Conservative arm: buffer endpoint residual decomposition', fontsize=11)
    save(fig, 'FigC02_buffer_decomposition',
         'First four signed terms reconstruct the endpoint residual up to the retained native equation residual. Algebraic decomposition is not missing physical heat or closure certification.')
    root = repo/'outputs_storage_audit'/EXPERIMENT/'conservative'
    with h5py.File(root/'observations.mat') as raw, h5py.File(root/'configuration.mat') as config:
        options = config['options']
        scalar = lambda p: float(options[p][0, 0])
        target = (scalar('branch/m_dot_se_the_kg_per_s')+scalar('branch/m_dot_se_chex_kg_per_s'))/2
        guard = scalar('validation/se_settled_guard_s')+.001
        ramp = scalar('branch/stage_command_ramp_s')
        limit = scalar('validation/max_se_settled_flow_relative_error')*100
        fig, axes = plt.subplots(2, 1, figsize=(7.1, 4.8), sharex=True, sharey=True, layout='constrained')
        for ax, stage, start, name in zip(axes, [2, 4], [3.5, 8.5],
                ['mass_flow_v1_cold_inlet_kgps', 'mass_flow_v4_hot_inlet_kgps']):
            r = raw['signals'][name]; time = r['time_s'][:].reshape(-1); elapsed = time-start
            mask = (elapsed >= 0)&(elapsed < 1.5 if stage==2 else elapsed <= 1.5)
            flow = r['values'][0]
            ax.axvspan(max(guard, ramp), 1.5-ramp, color='#E8EEEE', zorder=0)
            ax.plot(elapsed[mask], 100*(abs(flow[mask])/target-1), color='#007C78', lw=1)
            ax.axhline(limit, color='#BB3333', ls='--', lw=.8, label=f'Pointwise gate: +/-{limit:g}%')
            ax.axhline(-limit, color='#BB3333', ls='--', lw=.8)
            ax.axhline(0, color='black', lw=.6)
            ax.set(title=f'SE stage {stage}: flow gate failed', ylabel='Flow-magnitude error (%)', xlim=(0, 1.5))
        axes[0].legend(loc='upper right', frameon=False)
        axes[-1].set_xlabel('Elapsed time in stage (s)')
        save(fig, 'FigC03_SE_flow_failures',
             'Shading is the settled audit window. Dashed lines show pointwise limits; RMS gates are independently listed in the JSON. Full stage transient is retained.')
        fig, axes = plt.subplots(1, 2, figsize=(7.1, 2.9), sharey=True, layout='constrained')
        for ax, stage, start, center, name in zip(axes, [2, 4], [3.5, 8.5], [.35, 1.30],
                ['mass_flow_v1_cold_inlet_kgps', 'mass_flow_v4_hot_inlet_kgps']):
            r = raw['signals'][name]; time = r['time_s'][:].reshape(-1); elapsed = time-start
            mask = (elapsed >= center-1e-12)&(elapsed <= center+.010+1e-12)
            error = 100*(abs(r['values'][0, mask])/target-1)
            ax.plot(1000*(elapsed[mask]-center), error, '.-', color='#007C78', lw=.8, ms=4)
            ax.axhline(limit, color='#BB3333', ls='--', lw=.8)
            ax.axhline(-limit, color='#BB3333', ls='--', lw=.8)
            ax.set(title=f'Stage {stage}: {center:.2f}-{center+.01:.2f} s',
                   xlabel='Time from window start (ms)', xticks=[0, 2, 4, 6, 8, 10])
        axes[0].set_ylabel('Flow-magnitude error (%)')
        save(fig, 'FigC04_SE_native_step_detail',
             'Unresampled 1 ms samples within the failed windows. Alternation is observed, not yet assigned a physical or numerical root cause.')
    manifest = dict(schema='heatdrive_ecc_cold_cycle_figures_v1', audit_sha256=sha256(audit_path),
        figures=checks, files={p.name: sha256(p) for p in files},
        publication_quality_independent_review_complete=False, table4_reproduction_claim=False)
    (output/'figure_manifest.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(dict(figures=len(checks), files=len(files), output=str(output))))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--audit', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    plot(Path(__file__).resolve().parents[1], args.audit, args.output)
