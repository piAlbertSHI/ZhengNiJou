"""Draw distinct measured-cycle and isolated-component panels, not a system performance claim."""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256


def plot(mechanism_path,fixture_path,output):
    mechanism=json.loads(mechanism_path.read_text(encoding='utf-8-sig'))
    fixture=json.loads(fixture_path.read_text(encoding='utf-8-sig'))
    if (mechanism['total_cycles']!=62 or not fixture['isolated_component_equations_pass'] or
            not fixture['observed_area_response_monotone'] or
            fixture['input_sha256']['source_derived_flux_mechanism']!=sha256(mechanism_path)):
        raise ValueError('Require the exact mechanism and a passing component matrix')
    if output.exists():raise FileExistsError('Never overwrite a figure')
    plt.rcParams.update({'font.family':'Arial','font.size':10,'axes.titlesize':11,
        'axes.labelsize':10,'axes.linewidth':.7,'legend.fontsize':9,'xtick.labelsize':9,'ytick.labelsize':9})
    fig,axes=plt.subplots(1,2,figsize=(10.8,4.3),layout='constrained')
    names=['SHEXFluidBuffer','SMAHotFluidBuffer'];labels=['SHEX buffer','SMA hot buffer']
    x=np.arange(2)
    for shift,key,label,color in ((-.2,'advection_J','Advection','#4477AA'),
            (0.,'exact_smoothing_J','Port conduction','#CC6677'),(.2,'exact_flow_work_J','Flow work','#777777')):
        values=[mechanism['buffers'][name]['cycles'][-1]['port_terms'][key] for name in names]
        axes[0].bar(x+shift,values,.19,label=label,color=color)
        if key!='exact_flow_work_J':
            for pos,value in zip(x+shift,values):
                axes[0].text(pos,value+(.12 if value>=0 else -.12),f'{value:.3f}',
                    ha='center',va='bottom' if value>=0 else 'top',fontsize=8.5)
    axes[0].set(xticks=x,xticklabels=labels,ylabel='Port energy per cycle (J)',ylim=(-5.3,6.7),
                title='(a) Measured C62 energy transfer')
    axes[0].axhline(0,color='#444444',lw=.65);axes[0].legend(loc='upper left',frameon=False,ncol=3)
    for name,label,color,marker in zip(names,labels,['#00796B','#BF3B5E'],['o','s']):
        rows=sorted([r for r in fixture['cases'] if r['source_buffer']==name],key=lambda r:r['port_area_m2'])
        axes[1].plot([r['port_area_m2'] for r in rows],
            [1000*abs(r['temperature_change_K']) for r in rows],color=color,marker=marker,
            ms=5,mfc='white',lw=1.4,label=label)
    axes[1].set(xscale='log',yscale='log',xlabel='Port area ($m^2$)',
        ylabel='Absolute temperature change in 1 s (mK)',title='(b) Isolated zero-flow tests')
    axes[1].legend(loc='upper left',frameon=False)
    for ax in axes:
        ax.grid(axis='y',color='#DDDDDD',lw=.5);ax.set_axisbelow(True)
        ax.spines[['top','right']].set_visible(False)
    fig.suptitle('Buffer port conduction: measured mechanism and component test',fontsize=12)
    output.parent.mkdir(parents=True,exist_ok=True);fig.savefig(output,dpi=260,facecolor='white');plt.close(fig)
    receipt=dict(schema='heatdrive_ecc_buffer_port_diagnostic_figure_v1',figure_sha256=sha256(output),
        panel_a='Actual C62; signed per-cycle energy, not a cooling correction',
        panel_b='Independent one-second zero-mass-flow fixtures with tight local residual control; not coupled performance',
        final_paper_figure=False,table4_reproduction_claim=False,
        input_sha256={'mechanism':sha256(mechanism_path),'fixture':sha256(fixture_path)})
    output.with_suffix('.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mechanism',type=Path,required=True)
    parser.add_argument('--fixture',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();plot(args.mechanism,args.fixture,args.output)
