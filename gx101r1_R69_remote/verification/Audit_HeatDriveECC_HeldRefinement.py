"""Compare two passing short windows without claiming full-cycle convergence."""
import argparse
import json
from pathlib import Path
import numpy as np
from Audit_HeatDriveECC_ColdPassivePSObserver import read,sha256
from Audit_HeatDriveECC_CommandIntervals import command_intervals


def endpoint_comparison(coarse,fine):
    fields={'mass_endpoint_change_kg':1e-15,'integrated_mass_input_kg':1e-15,
            'energy_endpoint_change_J':1e-8,'integrated_energy_input_J':1e-8}
    differences={k:abs(fine[k]-coarse[k]) for k in fields}
    if not np.isfinite(list(differences.values())).all():raise ValueError('Nonfinite endpoint evidence')
    return dict(differences=differences,limits=fields,within_limits=all(differences[k]<=fields[k] for k in fields))


def build(repo):
    root=repo/'outputs_storage_audit';audits=[];inputs=[]
    for step in ('20us','10us'):
        path=root/f'nonlinear_cold_held_{step}_audit_20260910/nonlinear_cold_held_audit.json';r=read(path);inputs.append(path)
        if (not r['evidence_audit_pass'] or not r['local_balance_gate'] or r['passing_joint_balances']!=6
                or r['observed_interval_s']!=[0,.04] or r['production_recovery_allowed']):raise ValueError('Unqualified step')
        for f in r['files']:
            if sha256(repo/f['path'])!=f['sha256']:raise ValueError('Underlying step evidence changed')
        audits.append(r)
    by_path=[{c['block_path']:c for c in a['local_balances']} for a in audits]
    if set(by_path[0])!=set(by_path[1]):raise ValueError('Component coverage differs')
    rows=[dict(block_path=p,**endpoint_comparison(by_path[0][p],by_path[1][p])) for p in sorted(by_path[0])]
    record_path=root/'nonlinear_inventory_cold_held_10us_20260910/compiled_states_inspection.json';r=read(record_path)
    command_path=root/'sma_derivative_contract_20260909_v3/sma_derivative_contract.json';archive=read(command_path)
    if sha256(command_path)!='EE5C16D580693FCA925D24D0DB2A8E021BAC65E36F0A77A8E12AE795070ACEE2':raise ValueError('Archive changed')
    if r['actual_command_schedule']!=archive['commands']:raise ValueError('Actual command schedule differs')
    grid=np.array(r['nonlinear_coordinate_states'][0]['time_s']);h=np.diff(grid)
    inputs.extend([record_path,command_path])
    return dict(bounded_endpoint_refinement_pass=all(c['within_limits'] for c in rows),components=rows,
        observed_interval_s=[0,.04],coarse_step_s=.00002,fine_step_s=.00001,
        actual_full_command_schedule_verified=True,command_intervals=[command_intervals(c) for c in r['actual_command_schedule']],
        fine_grid_min_interval_s=float(min(h)),fine_grid_max_interval_s=float(max(h)),
        fine_grid_interval_ratio=float(max(h)/min(h)),
        scope='Two-step endpoint and integrated-input stability with original mass/energy limits, not an asymptotic or whole-cycle proof.',
        simpson_estimate_conditioning_verified=False,quadrature_independence_proven=False,
        full_dynamic_derivative_verified=False,production_recovery_allowed=False,table4_reproduction_claim=False,
        input_sha256={str(p.relative_to(repo)):sha256(p) for p in inputs})


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output-root',type=Path,required=True);args=parser.parse_args()
    if args.output_root.exists():raise FileExistsError('Never overwrite evidence')
    r=build(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'held_refinement_audit.json').write_text(json.dumps(r,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in r.items() if k!='command_intervals'},indent=2))
