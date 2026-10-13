"""Two unambiguous diagnostic figures; no mixed axes or steady-state claims."""
import argparse
import json
from pathlib import Path

import h5py
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

from Audit_HeatDriveECC_ColdChamberCycle import checked_rows, read
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_CoupledEnergyInventory import ROOT, CHAMBER_NAMES
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def decorate(axis, title, ylabel):
    axis.set_title(title, loc='left', fontsize=11, pad=8)
    axis.set_ylabel(ylabel)
    axis.set_xlim(0, 10)
    axis.set_xticks([0, 2, 4, 6, 8, 10])
    axis.grid(axis='y', color='.88', linewidth=.5)
    for time in (3.5, 5, 8.5):
        axis.axvline(time, color='.65', linewidth=.7, linestyle=':', zorder=0)
    axis.spines[['top','right']].set_visible(False)
    axis.tick_params(direction='out', length=3)
    axis.ticklabel_format(axis='y',style='plain',useOffset=False)


def render(analysis, output):
    if output.exists():
        raise FileExistsError('Never overwrite reviewed scientific figures')
    result=read(analysis)
    manifest=read(Path(result['source_root'])/'counterfactual_execution.json')
    traces=[]
    for case, expected in zip(manifest['cases'],result['cases']):
        path=Path(case['case_root'])/'native/observations.mat'
        if sha256(path)!=expected['input_sha256']['observations.mat']:
            raise ValueError('Plot raw evidence changed after analysis')
        with h5py.File(path) as handle:
            rows=checked_rows(handle,'native',1262)
            traces.append({key:scalar_series(rows[ROOT+key,state],unit) for key,state,unit in (
                ('SMAHotFluidBuffer','stored_mass','kg'),('SHEXFluidBuffer','stored_mass','kg'),
                ('ColdFluidBuffer','stored_mass','kg'),('HotFluidBuffer','stored_mass','kg'))})
            for name in CHAMBER_NAMES:
                traces[-1][name]={state:scalar_series(rows[ROOT+name,state],unit)
                    for state,unit in (('stored_mass','kg'),('T_I','K'))}
    plt.rcParams.update({'font.family':'Arial','font.size':10,'axes.linewidth':.8,
        'pdf.fonttype':42,'ps.fonttype':42,'path.simplify':False})
    time=np.arange(10001)*.001
    styles=[dict(color='#252525',linewidth=1.25,linestyle='-',label='Original volume'),
        dict(color='#008477',linewidth=1.25,linestyle='--',label='10% volume (diagnostic only)')]
    output.mkdir(parents=True)
    saved=[]

    def finish(figure,name):
        figure.legend(*figure.axes[0].get_legend_handles_labels(),loc='upper center',ncol=2,
            bbox_to_anchor=(.5,.925),frameon=False,fontsize=10)
        figure.text(.5,.02,'Cycle 1: transient diagnostics, not a steady-state benchmark endpoint.',
            ha='center',fontsize=9)
        figure.subplots_adjust(left=.1,right=.975,bottom=.12,top=.83,wspace=.3,hspace=.45)
        for extension in ('png','pdf'):
            path=output/(name+'.'+extension)
            figure.savefig(path,dpi=300,facecolor='white')
            saved.append(dict(path=str(path.resolve()),bytes=path.stat().st_size,sha256=sha256(path)))
        plt.close(figure)

    figure,axes=plt.subplots(2,2,figsize=(9,6.9))
    figure.suptitle('Buffer inventory response to the SMA chamber-volume intervention',fontsize=13,y=.97)
    for axis,(name,title),letter in zip(axes.ravel(),(
        ('SMAHotFluidBuffer','SMA hot buffer'),('SHEXFluidBuffer','SHEX buffer'),
        ('ColdFluidBuffer','SE cold buffer'),('HotFluidBuffer','SE hot buffer')),'abcd'):
        end=[]
        for data,style in zip(traces,styles):
            change=(data[name]-data[name][0])*1000
            axis.plot(time,change,**style);end.append(change[-1])
        decorate(axis,'('+letter+') '+title+f'\nNet change: {end[0]:.6f} / {end[1]:.6f} g',
            'Mass change from initial state (g)')
    for axis in axes[1]:axis.set_xlabel('Cycle time (s)')
    finish(figure,'buffer_inventory_response')

    figure,axes=plt.subplots(2,2,figsize=(9,6.9))
    figure.suptitle('Connecting-chamber temperature and actual stored mass',fontsize=13,y=.97)
    for column,(name,title) in enumerate(zip(CHAMBER_NAMES,('Pump inlet chamber','Pump outlet chamber'))):
        for row,(state,ylabel) in enumerate((('T_I','Fluid temperature (K)'),
            ('stored_mass','Mass change from initial state (g)'))):
            axis=axes[row,column]
            for data,style in zip(traces,styles):
                values=data[name][state]
                if state=='stored_mass':values=(values-values[0])*1000
                axis.plot(time,values,**style)
            decorate(axis,'('+chr(97+2*row+column)+') '+title,ylabel)
    for axis in axes[1]:axis.set_xlabel('Cycle time (s)')
    finish(figure,'chamber_temperature_and_inventory')
    receipt=dict(schema='heatdrive_ecc_manifold_diagnostic_figures_v1',analysis_sha256=sha256(analysis),
        plot_source_sha256=sha256(Path(__file__)),files=saved,periodic_performance_claim=False,
        plotted_samples_per_trace=10001,stage_boundary_times_s=[3.5,5,8.5],
        interpretation='Separate units and independent panel scales; all original samples, no fill or extrapolation.')
    (output/'plot_receipt.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    return receipt


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--analysis',type=Path,required=True)
    parser.add_argument('--output-root',type=Path,required=True)
    args=parser.parse_args()
    print(json.dumps(render(args.analysis.resolve(),args.output_root.resolve())))
