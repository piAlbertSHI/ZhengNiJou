"""Plot three separate inventory observables, using every original millisecond sample."""
import argparse
import json
from pathlib import Path

import h5py
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def plot(audit_path, output):
    evidence=json.loads(audit_path.read_text(encoding='utf-8'))
    if not evidence['candidate_numerical_inventory_qualification']:
        raise ValueError('Do not plot rejected inventory as the final qualified diagnostic')
    root=Path(evidence['source_root'])
    manifest=json.loads((root/'storage_closure_execution.json').read_text(encoding='utf-8'))
    folders=[Path(manifest[key])/'native' for key in ('baseline_root','candidate_root')]
    data=[]
    for folder, case in zip(folders,evidence['cases']):
        source=folder/'observations.mat'
        if sha256(source)!=case['input_sha256']['observations.mat']:
            raise ValueError('Plot observations changed')
        with h5py.File(source) as f:
            rows=named_rows(f,f['native'])
            series={}
            for name in ('SMA_PumpInletConnectingPipeVolume','SMAHotFluidBuffer','ColdFluidBuffer'):
                mass=scalar_series(rows['heatdrive_ecc_coupled_se21/'+name,'stored_mass'],'kg')
                if mass.size!=10001:raise ValueError('Incomplete plot clock')
                series[name]=(mass-mass[0])*1e6
            data.append(series)
    output.mkdir(parents=True,exist_ok=False)
    plt.rcParams.update({'font.family':'DejaVu Sans','font.size':9,'axes.labelsize':10,
                         'axes.linewidth':.8,'pdf.fonttype':42,'ps.fonttype':42})
    fig,axes=plt.subplots(1,3,figsize=(10.2,3.6),sharex=True)
    time=np.arange(10001)*.001
    names=('SMA_PumpInletConnectingPipeVolume','SMAHotFluidBuffer','ColdFluidBuffer')
    titles=('(a) SMA inlet manifold','(b) SMA ambient-side buffer','(c) SE cold-side buffer')
    colors=('#333333','#008678');labels=('Full density storage','Pressure-only density storage')
    for ax,name,title in zip(axes,names,titles):
        for case,color,label in zip(data,colors,labels):
            ax.plot(time,case[name],color=color,lw=1.4,label=label)
        for boundary in (3.5,5,8.5):ax.axvline(boundary,color='#aaaaaa',lw=.6,ls=':',zorder=0)
        ax.set_title(title,loc='left',fontsize=10,pad=10)
        ax.set_xlabel('Time (s)');ax.set_ylabel('Mass change from t = 0 (mg)')
        ax.set_xlim(0,10);ax.set_xticks((0,2.5,5,7.5,10))
        ax.spines[['top','right']].set_visible(False)
        ax.grid(axis='y',color='#dddddd',lw=.5)
    endpoints=('C1 endpoints\n'
               f'Full: {data[0][names[1]][-1]:+.3f} mg\n'
               f'Approx: {data[1][names[1]][-1]:+.3f} mg')
    axes[1].text(.97,.65,endpoints,transform=axes[1].transAxes,
                 ha='right',va='bottom',fontsize=8,color='#333333')
    fig.legend(*axes[0].get_legend_handles_labels(),loc='upper center',ncol=2,
               frameon=False,bbox_to_anchor=(.5,1.01),fontsize=9)
    fig.subplots_adjust(left=.075,right=.985,top=.79,bottom=.24,wspace=.38)
    fig.text(.075,.06,'Matched geometry, property tables and control commands; independent 0-10 s diagnostic.\n'
             'The pressure-only storage law is an approximation, not a real-fluid repair or periodic-state result.',
             fontsize=8,color='#333333')
    pdf=output/'manifold_storage_closure.pdf';png=output/'manifold_storage_closure.png'
    fig.savefig(pdf);fig.savefig(png,dpi=220);plt.close(fig)
    receipt=dict(audit_sha256=sha256(audit_path),source_sha256=[case['input_sha256']['observations.mat']
                 for case in evidence['cases']],all_10001_samples_used=True,
                 PDF_sha256=sha256(pdf),PNG_sha256=sha256(png),periodic_result_claim=False)
    (output/'plot_receipt.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'PDF':str(pdf),'PNG':str(png),'all_samples':10001}))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--audit',type=Path,required=True)
    parser.add_argument('--output-dir',type=Path,required=True)
    args=parser.parse_args()
    plot(args.audit.resolve(),args.output_dir.resolve())
