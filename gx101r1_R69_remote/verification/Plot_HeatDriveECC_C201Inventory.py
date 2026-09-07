"""Separate native equation diagnostics from endpoint inventory residuals."""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

from Audit_HeatDriveECC_C201Inventory import compute


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    targets=[args.output.with_suffix(s) for s in ('.png','.pdf')]
    if any(p.exists() for p in targets):
        raise FileExistsError('Keep previous figure evidence')
    result,histories=compute(args.repo)
    frozen=json.loads((args.repo/'outputs_storage_audit/c201_inventory_20260907_v2/native_inventory_v2.json').read_text())
    if result!=frozen:
        raise ValueError('Recomputed scientific ledger changed')
    totals={k:sum(h[k] for h in histories.values()) for k in next(iter(histories.values()))}
    phase=np.arange(10001)*.001
    plt.rcParams.update({'font.family':'DejaVu Sans','font.size':10,'axes.spines.top':False,
                         'axes.spines.right':False,'pdf.fonttype':42})
    fig,ax=plt.subplots(2,2,figsize=(12,8.4),layout='constrained')
    blue,red='#0072B2','#D55E00'
    for axis,key,unit,scale,title in (
        (ax[0,0],'energy','J',1,'(a) All storage: energy residual'),
        (ax[0,1],'mass','mg',1e6,'(b) All storage: mass residual')):
        suffix='J' if key=='energy' else 'kg'
        axis.plot(phase,totals[f'endpoint_{key}_residual_{suffix}']*scale,color=red,label='Endpoint inventory',lw=1.4)
        axis.plot(phase,totals[f'BE_coefficient_{key}_residual_{suffix}']*scale,color=blue,label='BE coefficient equation',lw=1.2,ls='--')
        axis.set(xlabel='Cycle phase (s)',ylabel=f'Cumulative residual ({unit})',title=title,xlim=(0,10))
        for boundary in (3.5,5,8.5):
            axis.axvline(boundary,color='.75',ls=':',lw=.7)
        axis.axhline(0,color='.5',lw=.6)
        axis.legend(loc='upper center',bbox_to_anchor=(.5,-.18),fontsize=8,ncol=2,frameon=False)
    rows=[r for r in result['components'] if r['mask_type'] in ('Tank (TL)','Constant Volume Chamber (TL)')]
    labels=['Cold buffer','Hot buffer','SHEX buffer','SMA hot buffer','Pump inlet chamber','Pump outlet chamber']
    y=np.arange(6)
    axis=ax[1,0]
    axis.barh(y-.17,[r['endpoint_energy_residual_J_end'] for r in rows],height=.32,color=red,label='Endpoint inventory')
    axis.barh(y+.17,[r['BE_coefficient_energy_residual_J_end'] for r in rows],height=.32,color=blue,label='BE coefficient equation')
    axis.set(yticks=y,yticklabels=labels,xlabel='Cycle-end energy residual (J)',title='(c) Six variable-inventory components')
    axis.invert_yaxis()
    axis.axvline(0,color='.5',lw=.6)
    axis.legend(fontsize=8,loc='upper center',bbox_to_anchor=(.5,-.18),ncol=2,frameon=False)
    axis=ax[1,1]
    values=np.array([[s['endpoint_energy_residual_J'] for s in r['stages']] for r in rows])
    limit=abs(values).max()
    im=axis.imshow(values,cmap='RdBu_r',vmin=-limit,vmax=limit,aspect='auto')
    for i in range(6):
        for j in range(4):
            axis.text(j,i,f'{values[i,j]:.3f}',ha='center',va='center',fontsize=8,
                      color='white' if abs(values[i,j])>.55*limit else 'black')
    axis.set(xticks=range(4),xticklabels=['0-3.5','3.5-5','5-8.5','8.5-10'],yticks=y,
             yticklabels=labels,xlabel='Stage phase window (s)',title='(d) Endpoint residual by stage (J)')
    fig.colorbar(im,ax=axis,label='Energy residual (J)',shrink=.8)
    fig.suptitle('C201 native inventory audit | 119 components, 1 ms samples\nStorage diagnostic only; external boundary balance remains incomplete',fontsize=12)
    for target in targets:
        fig.savefig(target,dpi=220)
    plt.close(fig)
    print(json.dumps({'figure_files':[str(p) for p in targets],'recomputed_ledger_equal':True}))


if __name__=='__main__':
    main()
