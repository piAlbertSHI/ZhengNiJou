"""Plot the invalid switching sample explicitly as rejected solver evidence."""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

from Audit_HeatDriveECC_DualSwitchFailureMatrix import read_leaves
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--audit',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite a figure')
    data = json.loads(args.audit.read_text())
    path = args.audit.parent/'trial/failed_case_1.mat'
    if sha256(path) != data['input_sha256']['failed_case_1'] or data['completed_simulations'] != 0:
        raise ValueError('Failed diagnostic identity changed')
    _,tr = read_leaves(path)
    t = tr['/V3/B/T']['time']
    plt.rcParams.update({'font.family':'DejaVu Sans','font.size':10,'axes.spines.top':False,'axes.spines.right':False})
    fig,axes = plt.subplots(2,1,figsize=(8,7),layout='constrained')
    for path,label,color in [('/Inlet/T_I','Inlet chamber','#0072B2'),('/Outlet/T_I','Outlet chamber','#009E73'),('/V3/B/T','V3 outlet port','#D55E00')]:
        axes[0].plot(t[:-1],tr[path]['value'][:-1],label=label,color=color)
    axes[0].scatter(t[-1],tr['/V3/B/T']['value'][-1],marker='x',s=65,color='#CC3311',label='Rejected solver sample')
    axes[0].axhline(273.16,color='#555555',linestyle=':',label='Water table lower bound')
    axes[0].set(title='(a) Pre-event temperatures and invalid terminal sample',xlabel='Time (s)',ylabel='Temperature (K)')
    axes[0].legend(loc='center left',frameon=False,fontsize=8)
    flow = tr['/V3/mdot_A']['value']*1e3
    axes[1].plot(t[-6:-1],flow[-6:-1],marker='o',color='#0072B2',label='Pre-event samples')
    axes[1].scatter(t[-1],flow[-1],marker='x',s=65,color='#CC3311',label='Rejected terminal sample')
    axes[1].axhline(0,color='#777777',linewidth=.8)
    axes[1].set(title='(b) V3 closes at 0.5 s: sign reversal in the failed sample',xlabel='Time (s)',ylabel='V3 inward mass flow (g/s)')
    axes[1].legend(frameon=False,fontsize=8)
    for ax in axes:
        ax.grid(axis='y',alpha=.2)
    fig.suptitle('Dual-chamber diagnostic failure: native chamber, pump power none, 1 ms',fontsize=11)
    fig.savefig(args.output,dpi=220)
    plt.close(fig)


if __name__=='__main__':
    main()
