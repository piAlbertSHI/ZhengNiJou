"""Separate inventory rounding from sampled-step defects; no substitute gate."""
import argparse
import json
from pathlib import Path
import h5py
import numpy as np
from Audit_HeatDriveECC_ColdPassivePSObserver import read,sha256,CHAMBERS,BUFFERS
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_HybridHeldResult import sampled_rows
from Analyze_HeatDriveECC_ResetStepSignature import signature


def analyze(repo):
    root=repo/'outputs_storage_audit'
    audit_path=root/'nonlinear_cold_held_audit_20260910/nonlinear_cold_held_audit.json'
    audit=read(audit_path)
    if (not audit['evidence_audit_pass'] or audit['local_balance_gate'] or audit['production_recovery_allowed']):
        raise ValueError('Requires a rejected nonlinear held result')
    for row in audit['files']:
        if sha256(repo/row['path'])!=row['sha256']:raise ValueError('Trial evidence changed')
    raw=root/'nonlinear_inventory_cold_held_20260910/observations.mat'
    prior_path=root/'hybrid_held_ode23t_audit_20260910/held_interval_audit.json'
    if sha256(prior_path)!='BB1136088658C84AD15F6A369FF087C617D2F5349F1EE00B0FAEECCFED0F1C21':
        raise ValueError('Original failed reference changed')
    prior={r['block_path']:r for r in read(prior_path)['local_balances']}
    current={r['block_path']:r for r in audit['local_balances']}
    results=[]
    with h5py.File(raw) as f:
        rows,t=sampled_rows(f,'native',1276)
        for name in sorted(CHAMBERS|BUFFERS):
            p='heatdrive_ecc_coupled_se21/'+name
            get=lambda n,u:scalar_series(rows[p,n],u)
            mf=get('mdot_A','kg/s');q=get('Phi_A','W')+get('Q_H','W')
            if name in CHAMBERS:mf=mf+get('mdot_B','kg/s');q=q+get('Phi_B','W')
            diagnostics={}
            for label,variable,unit,flux in [('mass','mass_delta','kg',mf),('energy','energy_delta','J',q)]:
                # The 1ms grid is a diagnostic hypothesis, not measured reset events for this run.
                s=signature(t,get(variable,unit),flux,np.arange(40)*.001)
                after=np.array([i['after_reset'] for i in s['intervals']])
                defect=np.array([i['trapezoid_defect'] for i in s['intervals']])
                total=float(np.sum(abs(defect)))
                diagnostics[label]=dict(coordinate=variable,
                    increment_coordinate_trapezoid_residual=s['original_max_abs_cumulative_trapezoid_residual'],
                    hypothetical_mixed_rule_residual=s['hypothetical_mixed_rectangle_trapezoid_max_residual'],
                    after_nominal_1ms_grid_abs_defect_fraction=float(np.sum(abs(defect[after]))/total) if total else None,
                    after_grid_signature=s['groups']['after_reset'],other_signature=s['groups']['other'])
            results.append(dict(block_path=p,old_mass_residual_kg=prior[p]['mass_max_abs_residual_kg'],
                new_mass_residual_kg=current[p]['mass_max_abs_residual_kg'],
                old_energy_residual_J=prior[p]['energy_max_abs_residual_J'],
                new_energy_residual_J=current[p]['energy_max_abs_residual_J'],diagnostics=diagnostics))
    return dict(analysis_complete=True,components=results,actual_reset_events_observed_this_run=False,
        grouping='First sampled interval after nominal t=0, .001, ..., .039; not current-run profiler evidence.',
        original_mass_gate_kg=1e-15,original_energy_gate_J=1e-8,local_balance_gate=False,
        mixed_rule_is_not_a_scientific_gate=True,actual_solver_formula_verified=False,
        production_recovery_allowed=False,table4_reproduction_claim=False,
        input_sha256={str(p.relative_to(repo)):sha256(p) for p in (audit_path,raw,prior_path,Path(__file__))})


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output-root',type=Path,required=True)
    args=parser.parse_args()
    if args.output_root.exists():raise FileExistsError('Never overwrite diagnostic evidence')
    r=analyze(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'nonlinear_held_failure_analysis.json').write_text(json.dumps(r,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps(r,indent=2))
