"""Separate port-length and finite-resistance effects in frozen diagnostics."""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists() or args.output.with_suffix('.pdf').exists():
        raise FileExistsError('Do not overwrite figures')
    base=args.repo/'outputs_storage_audit'
    source={k:json.loads((base/f'ablation_{k}_20260907/ablation_audit_v1.json').read_text())
            for k in ('no_friction_long_port','friction_short_port','no_friction_short_port')}
    prior=json.loads((base/'dual_pipe_hard_switch_20260907/pipe_hard_audit_v1.json').read_text())
    plt.rcParams.update({'font.family':'DejaVu Sans','font.size':10,'axes.spines.top':False,
                         'axes.spines.right':False,'pdf.fonttype':42})
    fig,axes=plt.subplots(1,2,figsize=(10,5),layout='constrained')
    for ax,metric,gate,title,unit in [(axes[0],'conservative_mass_max_residual_kg',1e-15,'(a) Mass inventory','kg'),
                                    (axes[1],'conservative_energy_max_residual_J',1e-8,'(b) Energy inventory','J')]:
        no_friction=[source['no_friction_short_port'][metric],source['no_friction_long_port'][metric]]
        friction=[source['friction_short_port'][metric],prior[metric]]
        ax.semilogy([0,1],no_friction,'s-',color='#CC3311',label='No friction: failed')
        ax.semilogy([0,1],friction,'o-',color='#0072B2',label='Finite friction: passed')
        ax.scatter([1],[friction[1]],s=105,facecolors='none',edgecolors='#0072B2',zorder=4,label='Stage29 retained control')
        ax.axhline(gate,color='#555555',linestyle=':',label='Unchanged inventory gate')
        ax.set(title=title,ylabel=f'Max. all-time residual ({unit})',xlabel='Port convection length',
               xticks=[0,1],xticklabels=['3.2 mm','100 mm'],xlim=(-.18,1.18))
        ax.legend(frameon=False,fontsize=8,loc='center right')
        ax.grid(axis='y',alpha=.18)
    fig.suptitle('Hard-switch conservative pipe: both pump modes and three BE steps per point',fontsize=11)
    fig.savefig(args.output,dpi=240)
    fig.savefig(args.output.with_suffix('.pdf'))
    plt.close(fig)


if __name__=='__main__':
    main()
