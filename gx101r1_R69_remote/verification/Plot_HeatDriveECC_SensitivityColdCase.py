"""Separate transient performance and original thermal drift criteria into four panels."""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Close_HeatDriveECC_SplitObservation import read


def plot(summary,output):
    r=read(summary);cycles=r['cycles'];x=[c['cycle'] for c in cycles];s=r['public_periodicity']
    if r['schema']!='heatdrive_ecc_runtime_sensitivity_cold_closeout_v1' or x!=list(range(1,21)):
        raise ValueError('Require the sealed measured twenty-cycle case')
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
    rows=[('Endpoint T','last_cycle_endpoint_drift_K','periodic_endpoint_limit_K'),
          ('Same-phase T max','last_cycle_same_phase_temperature_drift_K','periodic_same_phase_temperature_limit_K'),
          ('Same-phase T P99','last_cycle_same_phase_temperature_p99_drift_K','periodic_same_phase_temperature_p99_limit_K'),
          ('Same-phase T RMS','last_cycle_same_phase_temperature_rms_drift_K','periodic_same_phase_temperature_rms_limit_K'),
          ('Phase endpoint','last_cycle_phase_drift','periodic_phase_limit'),
          ('Same-phase phase P99','last_cycle_same_phase_phase_p99_drift','periodic_same_phase_phase_p99_limit'),
          ('Same-phase phase RMS','last_cycle_same_phase_phase_rms_drift','periodic_same_phase_phase_rms_limit')]
    ratios=[s[v]/s[limit] for _,v,limit in rows];axis=axes[1,1]
    axis.barh(range(len(rows)),ratios,color=['#00796B' if v<=1 else '#B54464' for v in ratios],height=.6)
    axis.axvline(1,color='#333333',ls='--',lw=1)
    axis.set(yticks=range(len(rows)),yticklabels=[n for n,_,_ in rows],xlim=(0,max(ratios)*1.25),
             xlabel='Drift / original limit',title='(d) Last 10 cycles: public thermal drift')
    axis.invert_yaxis()
    for k,v in enumerate(ratios):axis.text(v+.025,k,f'{v:.2f}',va='center',fontsize=9)
    for axis in (axes[0,0],axes[0,1],axes[1,0]):
        axis.set(xlabel='Cycle',xticks=[1,5,10,15,20]);axis.grid(axis='y',color='#DDDDDD',lw=.5)
    for axis in axes.flat:axis.spines[['top','right']].set_visible(False)
    fig.suptitle('SMA-SE nominal cold control | Tc = 276.95 K | 20 measured cycles',fontsize=13)
    fig.supxlabel('All packet gates pass; current thermal periodicity and lift precision fail. Transient evidence, not Table 4 reproduction.',fontsize=9)
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
