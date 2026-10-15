"""Separate stream-port and material-inventory temperatures in the same cold window."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

from Audit_HeatDriveECC_BufferColdFactorial import read,ROOT
from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def plot(audit_path,review_path,output):
    audited=read(audit_path);review=read(review_path)
    if review['input_sha256']['factorial_audit']!=sha256(audit_path):raise ValueError('Coordinate review changed')
    if output.exists():raise FileExistsError('Never overwrite a plot')
    root=Path(audited['source_root'])
    plt.rcParams.update({'font.family':'Arial','font.size':10,'axes.titlesize':11,
        'axes.labelsize':10,'axes.linewidth':.7,'legend.fontsize':9})
    fig,axes=plt.subplots(1,2,figsize=(10.5,4.1),layout='constrained')
    for name,label,color in (('baseline_tight','Inherited port area','#00796B'),
                              ('sma_pipe_tight','Pipe-area hypothesis','#BF3B5E')):
        file=root/name/'native/observations.mat'
        if sha256(file)!=audited['cases'][name]['input_sha256']['observations.mat']:
            raise ValueError('Changed actual trace')
        with h5py.File(file) as f:
            row=f['signals/sma_hot_buffer_temp_out'];time=row['time_s'][:].ravel();port=row['values'][:].ravel()
            native=named_rows(f,f['native']);internal=scalar_series(native[ROOT+'SMAHotFluidBuffer','T_I'],'K')
            selected=time<5
            axes[0].plot(time[selected],port[selected]-port[0],color=color,lw=1.4,label=label)
            axes[1].plot(time[selected],1000*(internal[selected]-internal[0]),color=color,lw=1.4,label=label)
    axes[0].axhline(5,color='#777777',ls='--',lw=1,label='Legacy port-proxy limit')
    axes[0].set(title='(a) Stream-port temperature',ylabel='Port temperature rise (K)',ylim=(-10,14))
    axes[1].set(title='(b) Buffer material temperature',ylabel='Internal temperature rise (mK)')
    axes[1].text(.98,.97,'Internal-temperature limit remains 5 K',ha='right',va='top',
        transform=axes[1].transAxes,fontsize=8.5)
    for ax in axes:
        ax.set(xlabel='Cold-start time (s)',xlim=(0,5));ax.grid(color='#DDDDDD',lw=.5)
        ax.spines[['top','right']].set_visible(False)
    axes[0].legend(loc='upper right',frameon=True,facecolor='white',edgecolor='none')
    fig.suptitle('SMA hot buffer: different coordinates, different physical questions',fontsize=12)
    output.parent.mkdir(parents=True,exist_ok=True);fig.savefig(output,dpi=260,facecolor='white');plt.close(fig)
    receipt=dict(schema='heatdrive_ecc_buffer_gate_coordinate_diagnostic_figure_v1',figure_sha256=sha256(output),
        same_precision_recipe=True,different_temperature_coordinates_not_mixed=True,
        cold_window_only=True,final_paper_performance_figure=False,table4_reproduction_claim=False,
        input_sha256={'factorial_audit':sha256(audit_path),'coordinate_review':sha256(review_path)})
    output.with_suffix('.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--factorial-audit',type=Path,required=True);p.add_argument('--coordinate-review',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True);args=p.parse_args()
    plot(args.factorial_audit,args.coordinate_review,args.output)
