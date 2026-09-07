"""Plot measured scalar falling-input controls, not production model results."""
import argparse
import csv
from pathlib import Path

import h5py
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    args.output.mkdir(exist_ok=False)
    colors=['#202020','#0072B2','#D55E00','#009E73']
    labels=['Strict original OP','Seed OP','Original converter snapshot','Output sample as state']
    traces=[]
    for i in (7,8,9):
        with h5py.File(args.root/f'case_{i}.mat') as f:
            r=f['row']
            if i==7:traces.append({k:r['reference'][k][:] for k in ('time_s','source_Q_W','converter_values','temperature_K')})
            traces.append({k:r['actual'][k][:] for k in ('time_s','source_Q_W','converter_values','temperature_K')})
    plt.rcParams.update({'font.family':'DejaVu Sans','font.size':9,'pdf.fonttype':42,'axes.spines.top':False,'axes.spines.right':False})
    fig,axes=plt.subplots(2,2,figsize=(8.4,5.8),layout='constrained')
    rows=[]
    for j,tr in enumerate(traces):
        t=(tr['time_s'].reshape(-1)-2000.004)*1000
        style=['-','--',':','-.'][j]
        axes[0,0].plot(t,tr['source_Q_W'].reshape(-1),style,color=colors[j],lw=1.4,drawstyle='steps-post')
        axes[0,1].plot(t,tr['converter_values'][0],style,color=colors[j],lw=1.4,label=labels[j],drawstyle='steps-post')
        axes[1,0].plot(t,tr['converter_values'][1],style,color=colors[j],lw=1.4,drawstyle='steps-post')
        temp=tr['temperature_K'].reshape(-1)
        heat=-.001*np.cumsum(tr['source_Q_W'].reshape(-1)[1:])
        residual=1000*(temp[1:]-temp[0])-heat
        axes[1,1].plot(t[1:],residual*1e9,style,color=colors[j],lw=1.4)
        for k,time in enumerate(tr['time_s'].reshape(-1)):
            rows.append(dict(mode=labels[j],time_s=time,time_after_restart_ms=t[k],
                source_heat_W=tr['source_Q_W'].reshape(-1)[k],converter_channel_1=tr['converter_values'][0,k],
                converter_channel_2=tr['converter_values'][1,k],temperature_K=temp[k],
                energy_residual_J='' if k==0 else residual[k-1]))
    panels=[('a  Delivered source heat','Heat flow (W)'),('b  Converter channel 1','Logged value (native)'),
            ('c  Converter channel 2','Logged value (native)'),('d  Storage minus BE heat integral','Residual (nJ)')]
    for ax,(title,ylabel) in zip(axes.flat,panels):
        ax.set_title(title,loc='left',fontsize=10);ax.set_xlabel('Time after restart (ms)');ax.set_ylabel(ylabel)
        ax.grid(axis='y',color='#dddddd',lw=.5)
    axes[0,1].legend(fontsize=8,loc='upper left',bbox_to_anchor=(0,1.02))
    axes[0,1].set_ylim(-.1,1.9)
    fig.savefig(args.output/'Fig23_converter_restart_phase.png',dpi=220)
    fig.savefig(args.output/'Fig23_converter_restart_phase.pdf')
    with (args.output/'Fig23_converter_restart_phase.csv').open('w',newline='',encoding='utf-8') as f:
        writer=csv.DictWriter(f,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
    plt.close(fig)


if __name__=='__main__':main()
