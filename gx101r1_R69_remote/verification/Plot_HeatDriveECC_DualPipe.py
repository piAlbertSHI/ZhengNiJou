"""Plot paired pipe inventory evidence separately from production performance."""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

from Audit_HeatDriveECC_DualChamberSwitchResult import read_case
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists() or args.output.with_suffix('.pdf').exists():
        raise FileExistsError('Do not overwrite figures')
    base=args.repo/'outputs_storage_audit'
    root=base/'dual_pipe_hard_switch_20260907'
    hard=json.loads((root/'pipe_hard_audit_v1.json').read_text())
    finite=json.loads((base/'dual_pipe_friction_20260907_v2/pipe_friction_audit_v1.json').read_text())
    path=root/'trial/case_7.mat'
    if sha256(path)!=hard['input_sha256']['case_7']:
        raise ValueError('Hard-switch trajectory changed')
    _,t,p=read_case(path,finite_transition=True,pipe_model=True)
    plt.rcParams.update({'font.family':'DejaVu Sans','font.size':10,'axes.spines.top':False,
                         'axes.spines.right':False,'pdf.fonttype':42})
    fig,axes=plt.subplots(2,2,figsize=(11,8),layout='constrained')
    for role,label,color in [('inlet','Inlet pipe','#0072B2'),('outlet','Outlet pipe','#009E73')]:
        axes[0,0].plot(t,p[role]['T_I'],label=label,color=color)
    axes[0,0].plot(t,p['v3']['B.T'],color='#CC3311',linestyle='--',label='V3 outlet port')
    axes[0,0].axvline(.5,color='#777777',linestyle=':')
    axes[0,0].set(title='(a) Hard-switch response: conservative, 1 ms',xlabel='Time (s)',ylabel='Temperature (K)')
    axes[0,0].legend(frameon=False,fontsize=8,loc='lower left')
    for role,label,color in [('v1','Hot supply V1','#0072B2'),('v2','Cold supply V2','#CC3311')]:
        axes[0,1].plot(t,p[role]['mdot_A']*1000,color=color,label=label)
    axes[0,1].axvline(.5,color='#777777',linestyle=':')
    axes[0,1].set(title='(b) Measured route exchange, unchanged 260 Pa',xlabel='Time (s)',ylabel='Mass flow (g/s)')
    axes[0,1].legend(frameon=False,fontsize=8,loc='center right')
    for ax,metric,gate,label,title in [(axes[1,0],'mass_max_abs_residual_kg',1e-15,'Mass residual (kg)','(c) All-time mass inventory residual'),
                                      (axes[1,1],'energy_max_abs_residual_J',1e-8,'Energy residual (J)','(d) All-time energy inventory residual')]:
        for rows,name,color,marker,style in [(hard['cases'][:3],'Native, hard switch','#CC3311','s','-'),
                                             (hard['cases'][6:9],'Conservative, hard switch','#0072B2','o','-'),
                                             (finite['cases'][6:9],'Conservative, 10 ms','#009E73','^','--')]:
            ax.semilogy([r['local_step_s']*1000 for r in rows],
                        [max(v[metric] for v in r['ledgers'].values()) for r in rows],
                        color=color,marker=marker,linestyle=style,label=name)
        ax.axhline(gate,color='#555555',linestyle=':',label='Unchanged inventory gate')
        ax.set(title=title,xlabel='Local BE step (ms)',ylabel=label,xticks=[.25,.5,1])
        ax.legend(frameon=False,fontsize=8,loc='center right')
    for ax in axes.flat:
        ax.grid(axis='y',alpha=.18)
    fig.suptitle('Geometric pipe diagnostic: 0.2 m length, 3.2 mm diameter; pump power none',fontsize=12)
    fig.savefig(args.output,dpi=240)
    fig.savefig(args.output.with_suffix('.pdf'))
    plt.close(fig)


if __name__=='__main__':
    main()
