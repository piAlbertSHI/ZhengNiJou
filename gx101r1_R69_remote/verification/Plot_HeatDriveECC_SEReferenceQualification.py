"""Measured commutation references, transported mass and complete-cycle residual."""
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


def render(audit_path,output):
    if output.exists():raise FileExistsError('Never overwrite scientific figures')
    audit=json.loads(audit_path.read_text(encoding='utf-8'))
    root=Path(audit['source_root'])
    manifest=json.loads((root/'state_qualification_execution.json').read_text(encoding='utf-8'))
    data=[]
    for folder,case in zip(manifest['case_roots'],audit['cases']):
        path=Path(folder)/'native/observations.mat'
        if sha256(path)!=case['source_observation_sha256']:raise ValueError('Changed raw plot inputs')
        with h5py.File(path) as f:
            time=f['signals/stage4_target_flow_command/time_s'][:].ravel()
            rows=named_rows(f,f['native'])
            mass=scalar_series(rows['heatdrive_ecc_coupled_se21/ColdFluidBuffer','stored_mass'],'kg')
            data.append(dict(time=time,mass=mass,
                PI=f['signals/stage4_target_flow_command/values'][:].ravel(),
                FF=f['signals/distributed_target_flow_kg_s/values'][:].ravel()))
    plt.rcParams.update({'font.family':'Arial','font.size':10,'pdf.fonttype':42,'axes.linewidth':.8})
    figure,axes=plt.subplots(1,3,figsize=(11.5,4.2))
    figure.suptitle('SE common stroke-reference correction: independent cold cycle 2',fontsize=13,y=.98)
    colors=['#252525','#008477'];labels=['Original reference','Coherent reference']
    window=(data[0]['time']>=14.99-1e-9)&(data[0]['time']<=15.16+1e-9)
    axes[0].plot(data[0]['time'][window]-15,data[0]['PI'][window]*1000,color=colors[0],label='Original PI target')
    axes[0].plot(data[0]['time'][window]-15,data[0]['FF'][window]*1000,color='.5',linestyle=':',label='FF stroke target')
    axes[0].plot(data[1]['time'][window]-15,data[1]['PI'][window]*1000,color=colors[1],linestyle='--',label='Coherent PI target')
    axes[0].set(title='(a) Reference disagreement removed',xlabel='Time from S3 boundary (s)',ylabel='Flow reference (g/s)')
    axes[0].legend(frameon=False,fontsize=8,loc='upper right')
    for values,color,label in zip(data,colors,labels):
        select=(values['time']>=15-1e-9)&(values['time']<=15.15+1e-9)
        origin=np.flatnonzero(abs(values['time']-15)<=1e-9)[0]
        axes[1].plot(values['time'][select]-15,(values['mass'][select]-values['mass'][origin])*1e6,
            color=color,linestyle='-' if color==colors[0] else '--',label=label)
    axes[1].set(title='(b) Measured commutation transport',xlabel='Time from S3 boundary (s)',ylabel='Cold-buffer mass change (mg)')
    axes[1].legend(frameon=False,fontsize=8,loc='lower left')
    residual=np.array(audit['C2_Cold_mass_change_kg'])*1e6
    axes[2].bar([0,1],residual,color=colors,width=.55)
    axes[2].set_xticks([0,1],['Original','Coherent'])
    axes[2].set(title='(c) Complete cycle-2 imbalance',ylabel='Net Cold-buffer mass change (mg)')
    axes[2].set_ylim(0,max(residual)*1.2)
    for index,value in enumerate(residual):axes[2].text(index,value+.12,f'{value:.4f}',ha='center',fontsize=10)
    for axis in axes:
        axis.spines[['top','right']].set_visible(False)
        axis.grid(axis='y',color='.9',linewidth=.5)
        axis.set_axisbelow(True)
    figure.subplots_adjust(left=.065,right=.985,bottom=.19,top=.78,wspace=.4)
    figure.text(.5,.035,'No geometry or PI-gain change; residual drift remains. Not a steady-state benchmark endpoint.',ha='center',fontsize=9)
    output.mkdir(parents=True)
    files=[]
    for extension in ('png','pdf'):
        path=output/('se_common_reference_effect.'+extension)
        figure.savefig(path,dpi=300,facecolor='white')
        files.append(dict(path=str(path.resolve()),bytes=path.stat().st_size,sha256=sha256(path)))
    plt.close(figure)
    receipt=dict(schema='heatdrive_ecc_se_reference_figure_v1',audit_sha256=sha256(audit_path),
        plot_source_sha256=sha256(Path(__file__)),files=files,periodic_performance_claim=False)
    (output/'plot_receipt.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(receipt))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--audit',type=Path,required=True);p.add_argument('--output-root',type=Path,required=True)
    args=p.parse_args();render(args.audit.resolve(),args.output_root.resolve())
