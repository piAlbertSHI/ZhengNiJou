"""Separate transient performance and original thermal drift criteria into four panels."""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Close_HeatDriveECC_SplitObservation import read
from HeatDriveECC_PublicPeriodicity import PUBLIC_PREDICATES, audit_public_statistics


def plot(summary,output):
    r=read(summary);cycles=r['cycles'];x=[c['cycle'] for c in cycles];s=r['public_periodicity']
    audit_public_statistics(s)
    if r['schema'] not in ('heatdrive_ecc_runtime_sensitivity_cold_closeout_v1','heatdrive_ecc_sensitivity_continuation_closeout_v1') or x!=list(range(1,len(x)+1)):
        raise ValueError('Require a sealed consecutive measured case')
    plt.rcParams.update({'font.family':'DejaVu Sans','font.size':10,'axes.titlesize':11,'axes.labelsize':10})
    fig,axes=plt.subplots(2,2,figsize=(12,7.4),layout='constrained')
    axes[0,0].plot(x,[c['temperature_lift_eq9_K'] for c in cycles],'o-',color='#2771A5',ms=3)
    axes[0,0].set(title='(a) Eq.9 temperature lift',ylabel='Temperature lift (K)')
    axes[0,1].plot(x,[c['cooling_power_eq10_W'] for c in cycles],'o-',color='#00796B',ms=3,label='Eq.10 metric')
    axes[0,1].plot(x,[c['CHEX_sensor_mean_W'] for c in cycles],'s-',color='#B54464',ms=3,label='CHEX sensor')
    axes[0,1].set(title='(b) Distinct cooling boundaries',ylabel='Cycle-mean cooling rate (W)')
    axes[0,1].legend(frameon=False)
    axes[1,0].plot(x,[c['SCP_W_per_g'] for c in cycles],'o-',color='#00796B',ms=3)
    axes[1,0].set(title='(c) Eq.10 specific cooling power',ylabel='SCP (W/g)')
    rows=PUBLIC_PREDICATES
    ratios=[s[v]/s[limit] for _,v,limit in rows];axis=axes[1,1]
    axis.barh(range(len(rows)),ratios,color=['#00796B' if v<=1 else '#B54464' for v in ratios],height=.6)
    axis.axvline(1,color='#333333',ls='--',lw=1)
    axis.set(yticks=range(len(rows)),yticklabels=[n for n,_,_ in rows],xlim=(0,max(1.12,max(ratios)*1.25)),
             xlabel='Drift / original limit',title='(d) Last 10 cycles: six actual public predicates')
    axis.invert_yaxis()
    for k,v in enumerate(ratios):axis.text(v+.025,k,f'{v:.2f}',va='center',fontsize=9)
    for axis in (axes[0,0],axes[0,1],axes[1,0]):
        ticks=[1]+list(range(10,len(x)+1,10))
        if ticks[-1]!=x[-1]:ticks.append(x[-1])
        axis.set(xlabel='Cycle',xticks=ticks);axis.grid(axis='y',color='#DDDDDD',lw=.5)
    for axis in axes.flat:axis.spines[['top','right']].set_visible(False)
    fig.suptitle(f'SMA-SE nominal cold control | Tc = 276.95 K | {len(x)} measured cycles',fontsize=13)
    public='PASS' if s['periodic_steady_state'] else 'FAIL'
    precision='PASS' if r['target_precision']['precision_pass'] else 'FAIL'
    fig.supxlabel(f'Packet gates pass | Public thermal criteria: {public} | Target precision: {precision} | Not Table 4 reproduction',fontsize=9)
    output.parent.mkdir(parents=True,exist_ok=True)
    for ext in ('.png','.pdf'):
        path=output.with_suffix(ext)
        if path.exists():raise FileExistsError('Never overwrite a diagnostic figure')
        fig.savefig(path,dpi=220,facecolor='white')
    plt.close(fig)
    output.with_suffix('.json').write_text(json.dumps(dict(source_sha256=sha256(summary),
        png_sha256=sha256(output.with_suffix('.png')),pdf_sha256=sha256(output.with_suffix('.pdf')),
        original_thresholds_changed=False,steady_state_claim=False),indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--summary',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    plot(**vars(p.parse_args()))
