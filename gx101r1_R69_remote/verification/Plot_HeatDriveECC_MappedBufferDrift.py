"""Separate mass migration from thermal storage drift; diagnostic figures only."""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.ticker import MaxNLocator

from Audit_HeatDriveECC_SegmentedEvidence import sha256


def plot(source, destination):
    if destination.exists():
        raise FileExistsError('Never overwrite diagnostic figures')
    data=json.loads(source.read_text(encoding='utf-8-sig'))
    if data['independent_exact_identity_count']!=121 or data['periodic_gate_assigned']:
        raise ValueError('Wrong evidence or promoted diagnostic scope')
    destination.mkdir(parents=True)
    plt.rcParams.update({'font.family':'DejaVu Sans','font.size':9,'axes.labelsize':10,
                         'axes.titlesize':10,'pdf.fonttype':42,'ps.fonttype':42})
    fig,axes=plt.subplots(2,2,figsize=(9,6),layout='constrained')
    groups=[('ColdFluidBuffer','HotFluidBuffer'),('SHEXFluidBuffer','SMAHotFluidBuffer')]
    labels={'ColdFluidBuffer':'SE cold buffer','HotFluidBuffer':'SE hot buffer',
            'SHEXFluidBuffer':'SMA SHEX buffer','SMAHotFluidBuffer':'SMA hot buffer'}
    colors={'ColdFluidBuffer':'#0072B2','HotFluidBuffer':'#D55E00',
            'SHEXFluidBuffer':'#009E73','SMAHotFluidBuffer':'#CC79A7'}
    for column,names in enumerate(groups):
        for row,key,scale,ylabel in ((0,'mass_offset_change_kg',1e6,'Net mass change (mg/cycle)'),
                                     (1,'stored_energy_change_J',1,'Stored energy change (J/cycle)')):
            ax=axes[row,column]
            for name in names:
                records=data['buffers'][name]
                ax.plot([r['global_cycle'] for r in records],[r[key]*scale for r in records],
                        color=colors[name],marker='o',markersize=3,linewidth=1.5,label=labels[name])
            ax.axhline(0,color='#999999',linewidth=.6)
            ax.set_xlabel('Completed cycle');ax.set_ylabel(ylabel)
            ax.set_xlim(32.5,42.5);ax.set_xticks([33,36,39,42])
            ax.yaxis.set_major_locator(MaxNLocator(5));ax.grid(axis='y',color='#DDDDDD',linewidth=.5)
            ax.spines[['top','right']].set_visible(False)
            ax.set_title(('a','b','c','d')[row*2+column]+') '+('SE' if column==0 else 'SMA'))
            ax.legend(frameon=True,facecolor='white',edgecolor='none',framealpha=1,fontsize=8,loc='center right')
    fig.savefig(destination/'buffer_mass_and_energy_drift.pdf',bbox_inches='tight')
    fig.savefig(destination/'buffer_mass_and_energy_drift.png',dpi=200,bbox_inches='tight')
    plt.close(fig)
    receipt=dict(source_audit_sha256=sha256(source),figure_scope='C33-C42 empirically crosschecked buffer drift',
                 mass_and_energy_axes_separated=True,periodic_steady_state_claim=False,
                 compiled_state_semantics_claim=False)
    (destination/'figure_receipt.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--audit',type=Path,required=True)
    parser.add_argument('--output-dir',type=Path,required=True)
    args=parser.parse_args();plot(args.audit,args.output_dir)
