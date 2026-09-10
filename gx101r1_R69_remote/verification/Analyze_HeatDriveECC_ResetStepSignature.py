"""Test reset-step quadrature signatures without replacing conservation gates."""
import argparse
import json
from pathlib import Path
import h5py
import numpy as np
from Audit_HeatDriveECC_ColdPassivePSObserver import read,sha256,CHAMBERS,BUFFERS
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_HybridHeldResult import sampled_rows


def signature(t,inventory,flux,resets):
    t,y,f,resets=[np.asarray(x,dtype=float) for x in (t,inventory,flux,resets)]
    if (t.ndim!=1 or len(t)<3 or y.shape!=t.shape or f.shape!=t.shape or resets.ndim!=1
            or not all(np.isfinite(x).all() for x in (t,y,f,resets)) or np.any(np.diff(t)<=0)):
        raise ValueError('Finite aligned histories required')
    h=np.diff(t);trap=.5*h*(f[:-1]+f[1:]);defect=np.diff(y)-trap
    right_minus_trap=.5*h*np.diff(f)
    after=np.array([np.any(abs(resets-time)<=1e-14) for time in t[:-1]])
    groups={}
    for name,mask in (('after_reset',after),('other',~after)):
        x=right_minus_trap[mask];d=defect[mask];den=float(x@x)
        slope=float(x@d/den) if den else None
        fit=d-slope*x if slope is not None else None
        groups[name]=dict(interval_count=int(mask.sum()),
            right_rectangle_signature_coefficient=slope,
            coefficient_is_inferred_not_actual_solver_formula=True,
            fit_relative_l2=float(np.linalg.norm(fit)/np.linalg.norm(d)) if fit is not None and np.linalg.norm(d) else None,
            max_abs_trapezoid_defect=float(np.max(abs(d))) if len(d) else None,
            max_abs_right_rectangle_defect=float(np.max(abs(d-x))) if len(d) else None,
            max_abs_left_rectangle_defect=float(np.max(abs(d+x))) if len(d) else None)
    mixed=trap+np.where(after,right_minus_trap,0)
    return dict(groups=groups,intervals= [dict(start_s=float(a),end_s=float(b),after_reset=bool(c),
        observed_inventory_increment=float(d),trapezoid_increment=float(e),
        right_minus_trapezoid=float(g),trapezoid_defect=float(v))
        for a,b,c,d,e,g,v in zip(t[:-1],t[1:],after,np.diff(y),trap,right_minus_trap,defect)],
        largest_inventory_float64_spacing=float(np.max(abs(np.spacing(y)))),
        original_max_abs_cumulative_trapezoid_residual=float(np.max(abs(y-y[0]-np.r_[0,np.cumsum(trap)]))),
        hypothetical_mixed_rectangle_trapezoid_max_residual=float(np.max(abs(y-y[0]-np.r_[0,np.cumsum(mixed)]))),
        hypothetical_mixed_rule_is_not_a_scientific_gate=True,
        actual_event_left_right_limits_observed=False,actual_solver_first_step_formula_verified=False)


def build(repo):
    root=repo/'outputs_storage_audit'
    ap=root/'hybrid_held_ode23t_audit_20260910/held_interval_audit.json'
    rp=root/'hybrid_held_profiler_reset_association_audit_20260910/profiler_diagnostics_audit.json'
    if sha256(ap)!='BB1136088658C84AD15F6A369FF087C617D2F5349F1EE00B0FAEECCFED0F1C21':raise ValueError('Held reference changed')
    if sha256(rp)!='A7C46FF8CD4D6C611DFD1D8F30B2BA3EA6613FB0492D02F199A1E7DCC2C58732':raise ValueError('Reset diagnosis changed')
    audit=read(ap);reset_audit=read(rp)
    for report in (audit,reset_audit):
        for relative,digest in report['input_sha256'].items():
            if sha256(repo/relative)!=digest:raise ValueError('Input evidence changed: '+relative)
    dp=root/'hybrid_held_profiler_diagnostics_20260910/profiler_diagnostics.json'
    resets=read(dp)['reset_times_s'];raw=root/'specific_inventory_hybrid_held_ode23t_after_restart_20260910/observations.mat'
    rows_out=[]
    with h5py.File(raw) as f:
        rows,t=sampled_rows(f,'native',1258)
        for name in sorted(CHAMBERS|BUFFERS):
            path='heatdrive_ecc_coupled_se21/'+name
            get=lambda var,unit:scalar_series(rows[path,var],unit)
            mdot=get('mdot_A','kg/s');power=get('Phi_A','W')+get('Q_H','W')
            if name in CHAMBERS:mdot+=get('mdot_B','kg/s');power+=get('Phi_B','W')
            rows_out.append(dict(block_path=path,mass=signature(t,get('stored_mass','kg'),mdot,resets),
                                 energy=signature(t,get('stored_energy','J'),power,resets)))
    return dict(evidence_analysis_pass=True,components=rows_out,local_balance_gate=audit['local_balance_gate'],
        passing_local_balances=audit['passing_local_balances'],production_recovery_allowed=False,
        actual_solver_formula_verified=False,table4_reproduction_claim=False,
        input_sha256={str(p.relative_to(repo)):sha256(p) for p in (ap,rp,dp,raw,Path(__file__))})


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output-root',type=Path,required=True);args=parser.parse_args()
    if args.output_root.exists():raise FileExistsError('Never overwrite evidence')
    result=build(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'reset_step_signature.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps([dict(block=r['block_path'],mass=r['mass']['groups'],energy=r['energy']['groups']) for r in result['components']],indent=2))
