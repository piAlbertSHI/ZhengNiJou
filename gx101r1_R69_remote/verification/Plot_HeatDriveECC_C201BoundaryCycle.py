"""Separated complete-cycle external heat, pump work and inventory diagnostics."""
import argparse
import csv
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

from Audit_HeatDriveECC_C201BoundaryCycle import compute


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    files=[args.output.with_suffix(s) for s in ('.png','.pdf','.csv')]
    if any(p.exists() for p in files):
        raise FileExistsError('Keep previous evidence')
    result,time,rates,_=compute(args.repo.resolve())
    frozen=json.loads((args.repo/'outputs_storage_audit/c201_boundary_full_20260907/full_boundary_audit_v1.json').read_text())
    if result!=frozen:
        raise ValueError('Recomputed boundary ledger changed')
    plt.rcParams.update({'font.family':'DejaVu Sans','font.size':10,'pdf.fonttype':42,
                         'axes.spines.top':False,'axes.spines.right':False})
    fig,ax=plt.subplots(2,2,figsize=(12,8),layout='constrained')
    phase=time-2000
    blue,red,green='#0072B2','#D55E00','#009E73'
    ax[0,0].plot(phase,rates['SHEX_source_in'],label='SHEX supply',color=red,lw=1.3)
    ax[0,0].plot(phase,-rates['HHEX_ambient_in'],label='HHEX rejection',color=blue,lw=1.3,ls='--')
    ax[0,0].set(title='(a) External heating and rejection',ylabel='Heat-flow magnitude (W)')
    ax[0,1].plot(phase,rates['CHEX_reservoir_in'],color=green,lw=1.3,label='CHEX reservoir to network')
    ax[0,1].set(title='(b) Cold reservoir heat exchange',ylabel='Heat input (W)')
    ax[1,0].plot(phase,rates['SMA_hydraulic_estimate'],label='SMA hydraulic estimate',color=red,lw=1.2)
    ax[1,0].plot(phase,rates['SE_hydraulic_estimate'],label='SE hydraulic estimate',color=blue,lw=1.2)
    ax[1,0].plot(phase,rates['native_pump_input'],label='Native fluid power: zero',color='black',ls='--',lw=1)
    ax[1,0].set(title='(c) Pump work: distinct energy boundaries',ylabel='Power (W)')
    for axis in (ax[0,0],ax[0,1],ax[1,0]):
        axis.set(xlabel='Cycle phase (s)',xlim=(0,10))
        for boundary in (3.5,5,8.5):
            axis.axvline(boundary,color='.75',lw=.7,ls=':')
        axis.legend(loc='upper center',bbox_to_anchor=(.5,-.18),fontsize=8,frameon=False)
    values=[result['BE_source_net_energy_J'],result['endpoint_storage_plus_pdv_J'],result['source_minus_endpoint_storage_J']]
    bars=ax[1,1].bar(['Net source\ninput','Declared storage\nchange + p dV','Difference'],values,color=[blue,green,red],width=.6)
    ax[1,1].bar_label(bars,labels=[f'{v:.3f}' for v in values],padding=4,fontsize=10)
    ax[1,1].axhline(0,color='.4',lw=.8)
    ax[1,1].set(title='(d) Endpoint inventory does not close',ylabel='Cycle energy (J)',ylim=(-6,38))
    fig.suptitle('C201 complete source observation | one diagnostic cycle\nPort sums match; endpoint first-law qualification remains incomplete',fontsize=12)
    fig.savefig(files[0],dpi=220);fig.savefig(files[1]);plt.close(fig)
    with files[2].open('w',encoding='utf-8-sig',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(result['source_rows'][0]))
        writer.writeheader();writer.writerows(result['source_rows'])
    print(json.dumps(dict(figure_paths=[str(p) for p in files],recomputed_equal=True)))


if __name__=='__main__':
    main()
