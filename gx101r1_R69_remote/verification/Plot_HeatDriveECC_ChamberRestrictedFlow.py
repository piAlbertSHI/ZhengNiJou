"""Separate measured pressure/work from inventory-gate comparisons."""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.ticker import NullLocator

from Audit_HeatDriveECC_ChamberOpenFlowResult import read_case
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--audit',type=Path,required=True)
    parser.add_argument('--prior-audit',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite a figure')
    data = json.loads(args.audit.read_text())
    prior = json.loads(args.prior_audit.read_text())
    path = args.audit.parent/'trial/case_16.mat'
    if (sha256(path) != data['input_sha256']['case_16']
            or sha256(args.prior_audit) != data['input_sha256']['prior_failed_audit']):
        raise ValueError('Figure input changed')
    _,t,p = read_case(path,restricted=True)
    plt.rcParams.update({'font.family':'DejaVu Sans','font.size':10,'axes.spines.top':False,'axes.spines.right':False})
    fig, axes = plt.subplots(2,2,figsize=(11,7.6),layout='constrained')
    axes[0,0].plot(t,p['chamber']['p_I']/1e6,color='#0072B2',label='Chamber')
    axes[0,0].plot(t,p['cold_reservoir']['p_I']/1e6,color='#555555',linestyle='--',label='Reservoir')
    axes[0,0].set(title='(a) Reversal: pressure is no longer fixed',xlabel='Time (s)',ylabel='Pressure (MPa)')
    axes[0,1].plot(t,p['flow_source']['power']*1e3,color='#009E73',label='Measured source power')
    axes[0,1].set(title='(b) Reversal: measured pump work rate',xlabel='Time (s)',ylabel='Power added to fluid (mW)')
    groups = [(data['cases'][:9],'Native, finite resistance','#D55E00','s'),
              (prior['cases'][9:],'Conservative, fixed pressure','#555555','^'),
              (data['cases'][9:],'Conservative, finite resistance','#0072B2','o')]
    for ax,metric,gate,title,unit in [
            (axes[1,0],'mass_max_abs_residual_kg',data['mass_absolute_gate_kg'],'(c) All-time mass inventory residual','kg'),
            (axes[1,1],'energy_max_abs_residual_J',data['energy_absolute_gate_J'],'(d) All-time energy inventory residual','J')]:
        for rows,label,color,marker in groups:
            values = [max(r['external_ledger'][metric] for r in rows if r['local_step_s']==s) for s in (.00025,.0005,.001)]
            ax.plot([.25,.5,1],values,label=label,color=color,marker=marker)
        ax.axhline(gate,color='#AA3377',linestyle=':',label='Unchanged acceptance gate')
        ax.set(xscale='log',yscale='log',xlabel='Local BE step (ms)',ylabel=f'Maximum absolute residual ({unit})',title=title)
        ax.set_xticks([.25,.5,1],['0.25','0.5','1'])
        ax.xaxis.set_minor_locator(NullLocator())
    for ax in axes.flat:
        ax.grid(axis='y',alpha=.2)
    for ax in axes[0]:
        ax.legend(frameon=False,fontsize=8)
    handles, labels = axes[1,0].get_legend_handles_labels()
    fig.legend(handles,labels,loc='outside lower center',ncol=2,frameon=False,fontsize=9)
    fig.suptitle('Finite-resistance component test: measured work and unchanged inventory gates',fontsize=12)
    fig.savefig(args.output,dpi=220)
    plt.close(fig)


if __name__ == '__main__':
    main()
