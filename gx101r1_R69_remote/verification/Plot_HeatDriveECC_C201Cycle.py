"""Show cycle evolution separately from same-phase discrepancies."""
import argparse
import json

import h5py
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
from pathlib import Path

from Audit_HeatDriveECC_C201Cycle import load_signals
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists() or args.output.with_suffix('.pdf').exists():
        raise FileExistsError('Do not overwrite figures')
    root=args.repo/'outputs_storage_audit/c201_bounded_20260907'
    report=json.loads((root/'cycle_diagnostic_v1.json').read_text())
    for i in range(1,4):
        if sha256(root/f'nominal_s{i:02d}'/f'segment_{i:02d}.mat')!=report['input_sha256'][f'segment_{i}']:
            raise ValueError('Plotted input changed')
    signals=load_signals(root)
    authority=json.loads((args.repo/'verification/c200_mainline_freeze_contract.json').read_text(encoding='utf-8-sig'))
    old={}
    with h5py.File(args.repo/authority['result_relative_path']) as f:
        for name in ('SMA','SE'):
            old[name]=f['physical'][name+'_T_21_K'][:,-10001:]
            old[name+'_phase']=f['physical']['xM_'+name+'_21'][:,-10001:]
    plt.rcParams.update({'font.family':'DejaVu Sans','font.size':10,'axes.spines.top':False,
                         'axes.spines.right':False,'pdf.fonttype':42})
    t=np.arange(10001)*.001
    fig,axes=plt.subplots(2,2,figsize=(10,7),layout='constrained')
    for ax,name,title in zip(axes[0],('SMA','SE'),('(a) Forward SMA temperature','(b) Reverse SE temperature')):
        ax.plot(t,old[name].mean(axis=0),color='#222222',label='Frozen C200')
        ax.plot(t,signals[name+'_Tx21_internal'].mean(axis=0),color='#0072B2',linestyle='--',label='Diagnostic C201')
        ax.set(title=title,ylabel='Mean solid temperature (K)')
        ax.legend(frameon=False,fontsize=9)
    for name,color,offset in [('SMA','#0072B2',42),('SE','#D55E00',63)]:
        delta=signals[name+'_Tx21_internal']-old[name]
        axes[1,0].plot(t,abs(delta).max(axis=0),color=color,label=name)
        delta=signals['ECC_constitutive21_output'][offset:offset+21]-old[name+'_phase']
        axes[1,1].plot(t,np.sqrt(np.mean(delta**2,axis=0)),color=color,label=name)
    axes[1,0].set(title='(c) Same-phase temperature difference',ylabel='Maximum over 21 nodes (K)')
    axes[1,1].set(title='(d) Same-phase martensite difference',ylabel='RMS over 21 nodes (fraction)')
    for ax in axes.flat:
        for edge in (3.5,5,8.5):
            ax.axvline(edge,color='#777777',linestyle=':',linewidth=.8)
        ax.set(xlabel='Time within cycle (s)',xlim=(0,10))
        ax.grid(alpha=.15)
    for ax in axes[1]:
        ax.legend(frameon=False,fontsize=9)
    fig.suptitle('One C201 diagnostic cycle; no claim of ten-cycle periodicity or Table 4 reproduction',fontsize=10)
    fig.savefig(args.output,dpi=240)
    fig.savefig(args.output.with_suffix('.pdf'))
    plt.close(fig)


if __name__=='__main__':
    main()
