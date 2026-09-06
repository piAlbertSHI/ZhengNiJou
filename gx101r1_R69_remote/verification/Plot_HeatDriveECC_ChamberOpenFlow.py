"""Separate reversal, table-knot and energy-convergence failure diagnostics."""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.ticker import NullLocator
import numpy as np

from Audit_HeatDriveECC_ChamberOpenFlowResult import read_case
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--audit',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite a diagnostic figure')
    data=json.loads(args.audit.read_text())
    if data['tested_open_flow_inventory_closure_verified'] or not data['all_spatial_port_identities_pass']:
        raise ValueError('This figure describes the frozen failed inventory audit')
    traces={}
    for i in (10,16):
        path=args.audit.parent/'trial'/f'case_{i}.mat'
        if sha256(path)!=data['input_sha256'][f'case_{i}']:
            raise ValueError('Native trace changed')
        traces[i]=read_case(path)
    plt.rcParams.update({'font.family':'DejaVu Sans','font.size':10,'axes.spines.top':False,'axes.spines.right':False})
    fig,axes=plt.subplots(1,3,figsize=(13,4.2),layout='constrained')
    _,t,p=traces[16]
    axes[0].plot(t,p['chamber']['mdot_A']*1e3,label='Port A',color='#0072B2')
    axes[0].plot(t,p['chamber']['mdot_B']*1e3,label='Port B',color='#D55E00',linestyle='--')
    axes[0].set(title='(a) Reversal: measured signed flow',xlabel='Time (s)',ylabel='Inward mass flow (g/s)')
    meta,t,p=traces[10]
    mass=p['chamber']['rho_I']*meta['volume_m3']
    incoming=-p['hot_reservoir']['mdot_A']-p['cold_reservoir']['mdot_A']
    residual=mass-mass[0]-np.r_[0,np.cumsum(incoming[1:]*np.diff(t))]
    axes[1].plot(t,residual*1e9,color='#0072B2',label='Forward, 1 ms')
    axes[1].axvline(.646,color='#777777',linestyle=':',label='Table-cell transition')
    axes[1].set(title='(b) Forward: inventory mass residual',xlabel='Time (s)',ylabel='Mass residual (micro-g)')
    for mode,color,marker in [('forward','#0072B2','o'),('reverse','#D55E00','s'),('reversal','#009E73','^')]:
        rows=[r for r in data['cases'][9:] if r['mode']==mode]
        axes[2].plot([r['local_step_s']*1e3 for r in rows],
                     [r['external_ledger']['energy_max_abs_residual_J']*1e6 for r in rows],
                     color=color,marker=marker,label=mode.capitalize())
    axes[2].set(xscale='log',yscale='log',title='(c) All-time energy residual',xlabel='Local BE step (ms)',ylabel='Maximum residual (micro-J)')
    axes[2].set_xticks([.25,.5,1],['0.25','0.5','1'])
    axes[2].xaxis.set_minor_locator(NullLocator())
    axes[2].axhline(data['energy_absolute_gate_J']*1e6,color='#555555',linestyle='--',label='Unchanged gate')
    for ax in axes:
        ax.grid(axis='y',alpha=.2)
        ax.legend(frameon=False,fontsize=8)
    fig.suptitle('Open-flow tests: connected port balances pass, endpoint inventory gate fails',fontsize=12)
    fig.supxlabel('No event intervals removed. The constant-pressure test does not qualify the full SMA-SE network.',fontsize=9)
    fig.savefig(args.output,dpi=220)
    plt.close(fig)


if __name__=='__main__':
    main()
