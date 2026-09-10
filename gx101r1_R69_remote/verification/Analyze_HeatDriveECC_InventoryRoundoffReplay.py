"""Replay measured increments to distinguish large-offset rounding; not a simulation."""
import argparse
import json
from pathlib import Path
import h5py
import numpy as np
from Audit_HeatDriveECC_ColdPassivePSObserver import read,sha256,CHAMBERS,BUFFERS
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_HybridHeldResult import sampled_rows


def replay(t,initial,flux,resets,scale):
    t=np.asarray(t,dtype=float);flux=np.asarray(flux,dtype=float);resets=np.asarray(resets,dtype=float)
    if (t.ndim!=1 or len(t)<2 or flux.shape!=t.shape or resets.ndim!=1
            or not np.all(np.isfinite(t)) or not np.all(np.isfinite(flux))
            or not np.all(np.isfinite(resets)) or np.any(np.diff(t)<=0)
            or np.any(np.diff(resets)<=0) or not np.isscalar(initial)
            or not np.isfinite(initial) or not np.isscalar(scale) or not np.isfinite(scale) or scale<=0):
        raise ValueError('Require finite ordered series, scalar initial inventory and positive scale')
    h=np.diff(t);trap=.5*h*(flux[1:]+flux[:-1])
    mask=np.array([np.any(abs(resets-time)<=1e-14) for time in t[:-1]])
    increment=np.where(mask,h*flux[1:],trap)
    absolute=np.empty(len(t));shifted=np.empty(len(t));absolute[0]=shifted[0]=initial
    x=np.float64(initial/scale);delta=np.float64(0)
    for k,step in enumerate(increment):
        x=np.float64(x+step/scale);delta=np.float64(delta+step/scale)
        absolute[k+1]=x*scale;shifted[k+1]=initial+delta*scale
    reference=initial+np.r_[0,np.cumsum(increment)]
    return absolute,shifted,reference,trap


def build(repo):
    root=repo/'outputs_storage_audit';ap=root/'hybrid_held_ode23t_audit_20260910/held_interval_audit.json';a=read(ap)
    if sha256(ap)!='BB1136088658C84AD15F6A369FF087C617D2F5349F1EE00B0FAEECCFED0F1C21':raise ValueError('Reference changed')
    for p,digest in a['input_sha256'].items():
        if sha256(repo/p)!=digest:raise ValueError('Physical input changed')
    dp=root/'hybrid_held_profiler_diagnostics_20260910/profiler_diagnostics.json'
    if sha256(dp)!='8E294F45896F0B575ABC504A02A45F82F8BAC8CA60C97766A815EAA1E314547F':raise ValueError('Reset metadata changed')
    resets=np.asarray(read(dp)['reset_times_s'])
    path=root/'specific_inventory_hybrid_held_ode23t_after_restart_20260910';record=read(path/'compiled_states_inspection.json')
    nominal={(n['block_path'],n['state_name']):float(n['value']) for n in record['runtime_callbacks'][0]['chamber_nominals']}
    results=[]
    with h5py.File(path/'observations.mat') as f:
        rows,t=sampled_rows(f,'native',1258)
        for name in sorted(CHAMBERS|BUFFERS):
            block='heatdrive_ecc_coupled_se21/'+name;get=lambda n,u:scalar_series(rows[block,n],u)
            massflow=get('mdot_A','kg/s');power=get('Phi_A','W')+get('Q_H','W')
            if name in CHAMBERS:massflow+=get('mdot_B','kg/s');power+=get('Phi_B','W')
            for var,unit,flux in (('stored_mass','kg',massflow),('stored_energy','J',power)):
                actual=get(var,unit);scale=nominal.get((block,var),1.)
                absolute,shifted,reference,trap=replay(t,actual[0],flux,resets,scale)
                cases=[]
                for step in (.00025,.00002):
                    grid=np.linspace(0,.04,round(.04/step)+1);values=np.interp(grid,t,flux)
                    ab,sh,ref,tr=replay(grid,actual[0],values,resets,scale)
                    integral=np.r_[0,np.cumsum(tr)]
                    cases.append(dict(step_s=step,flux_interpolation='linear between existing samples; dynamics not recomputed',
                        absolute_replay_trapezoid_residual=float(np.max(abs(ab-actual[0]-integral))),
                        shifted_replay_trapezoid_residual=float(np.max(abs(sh-actual[0]-integral))),
                        absolute_replay_rounding_vs_increment_sum=float(np.max(abs(ab-ref))),
                        shifted_replay_rounding_vs_increment_sum=float(np.max(abs(sh-ref)))))
                results.append(dict(block_path=block,variable=var,unit=unit,scale=scale,
                    same_grid_absolute_replay_difference_from_actual=float(np.max(abs(absolute-actual))),
                    same_grid_shifted_replay_difference_from_actual=float(np.max(abs(shifted-actual))),
                    absolute_replay_rounding_vs_increment_sum=float(np.max(abs(absolute-reference))),
                    scenarios=cases))
    return dict(read_only_replay=True,mixed_startup_rule_assumed_not_full_solver_verified=True,results=results,
        new_coupled_trajectory_generated=False,production_recovery_allowed=False,scientific_gates_recomputed_from_replay=False,
        input_sha256={str(p.relative_to(repo)):sha256(p) for p in (ap,dp,path/'observations.mat',Path(__file__))})


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output-root',type=Path,required=True);args=parser.parse_args()
    if args.output_root.exists():raise FileExistsError('Never overwrite evidence')
    r=build(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'inventory_roundoff_replay.json').write_text(json.dumps(r,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps(r['results'],indent=2))
