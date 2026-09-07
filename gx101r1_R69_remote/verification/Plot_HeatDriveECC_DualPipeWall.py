"""Separate temperatures, energy storage and numerical closure of wall diagnostics."""
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
    root = args.repo/'outputs_storage_audit/dual_pipe_wall_20260907_v2'
    audit = json.loads((root/'wall_audit_v1.json').read_text())
    if not audit['all_inventory_pass'] or audit['production_recovery_allowed']:
        raise ValueError('Expected passed component-only audit')
    case = root/'case_1.mat'
    if sha256(case) != audit['input_sha256']['case_1']:
        raise ValueError('Changed plotted raw data')
    meta, t, p = read_case(case, finite_transition=True, pipe_model=True, wall_model=True)
    plt.rcParams.update({'font.family':'DejaVu Sans', 'font.size':10, 'axes.spines.top':False,
                         'axes.spines.right':False, 'pdf.fonttype':42})
    fig, axes = plt.subplots(2, 2, figsize=(10, 7), layout='constrained')
    for ax, role, title in zip(axes[0], ('inlet','outlet'), ('(a) Inlet pipe','(b) Outlet pipe')):
        ax.plot(t,p[role]['T_I'],color='#0072B2',label='Fluid')
        ax.plot(t,p[role+'_wall']['T'],color='#D55E00',linestyle='--',label='Wall')
        ax.axvline(.5, color='#555555', linestyle=':', linewidth=1)
        ax.set(title=title, xlabel='Time (s)', ylabel='Temperature (K)')
        ax.legend(frameon=False)
    fluid_energy = sum(p[k]['rho_I']*meta['volume_each_m3']*p[k]['u_I'] for k in ('inlet','outlet'))
    fluid_energy -= fluid_energy[0]
    wall_energy = sum(meta['wall_contract']['capacity_each_J_K']*(p[k+'_wall']['T']-340) for k in ('inlet','outlet'))
    boundary_power = -sum(p[k]['Phi_A'] for k in ('inlet_reservoir','outlet_reservoir','hot_return','cold_return')) + p['pump']['power']
    boundary_energy = np.r_[0,np.cumsum(boundary_power[1:]*np.diff(t))]
    ax = axes[1,0]
    ax.plot(t,fluid_energy,color='#0072B2',label='Fluid storage change')
    ax.plot(t,wall_energy,color='#D55E00',label='Wall storage change')
    ax.plot(t,boundary_energy,color='#222222',linestyle='--',label='Net external input')
    ax.set(title='(c) Two-pipe energy partition',xlabel='Time (s)',ylabel='Energy change (J)')
    ax.legend(frameon=False,fontsize=8)
    ax = axes[1,1]
    for offset, label, color, marker in [(0,'No native pump heat','#0072B2','o'),(3,'Isentropic pump power','#D55E00','s')]:
        rows = audit['cases'][offset:offset+3]
        ax.semilogy([r['local_step_s']*1000 for r in rows],
                    [max(v['energy_max_abs_residual_J'] for v in r['ledgers'].values()) for r in rows],
                    marker=marker,color=color,label=label)
    ax.axhline(1e-8,color='#555555',linestyle=':',label='Unchanged energy gate')
    ax.set(title='(d) Maximum all-time energy residual',xlabel='Backward Euler step (ms)',ylabel='Absolute residual (J)',
           xticks=[.25,.5,1],ylim=(1e-13,1e-7))
    ax.legend(frameon=False,fontsize=8)
    for ax in axes.flat:
        ax.grid(alpha=.16)
    fig.suptitle('Finite-wall diagnostic: hard switch at 0.5 s; panels (a-c) use 1 ms, no native pump heat',fontsize=10)
    fig.savefig(args.output,dpi=240)
    fig.savefig(args.output.with_suffix('.pdf'))
    plt.close(fig)


if __name__ == '__main__':
    main()
