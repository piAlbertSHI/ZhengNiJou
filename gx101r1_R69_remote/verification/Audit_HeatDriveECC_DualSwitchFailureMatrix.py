"""Retain invalid terminal samples as failure evidence, never as valid states."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_DualChamberSwitchResult import read_case
from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_NativeWindowLedger import validate_grid
from Audit_HeatDriveECC_SegmentedEvidence import sha256,text_field


def read_leaves(path):
    with h5py.File(path,'r') as f:
        meta = json.loads(text_field(f['diagnostic_json']))
        traces = {}
        for ref in f['traces'][:].flat:
            row = f[ref]
            name,unit = text_field(row['name']),text_field(row['unit'])
            t,v = row['time_s'][:].reshape(-1),row['values'][:].reshape(-1)
            validate_grid(t,0,.5,meta['local_step_s'])
            if name in traces or v.shape != t.shape or not np.isfinite(v).all():
                raise ValueError('Malformed partial scalar leaf')
            traces[name] = dict(unit=unit,time=t,value=v)
    return meta,traces


def failure_metrics(meta,traces):
    def si(name,unit):
        trace = traces[name]
        return convert(trace['value'],trace['unit'],unit)
    t = traces['/V3/B/T']['time']
    tb = si('/V3/B/T','K')
    opening = si('/V3/L','1')
    if (meta['production_recovery_allowed'] or not meta['separate_boundaries'] or t[-1] != .5
            or opening[-1] != 0 or np.any(opening[:-1] != 1) or tb[-1] >= 273.16 or np.any(tb[:-1] < 273.16)):
        raise ValueError('Expected first V3 cold-port violation at the actual closing event')
    selected = dict(temperature_A_K=('/V3/A/T','K'),temperature_B_K=('/V3/B/T','K'),
                    pressure_A_Pa=('/V3/A/p','Pa'),pressure_B_Pa=('/V3/B/p','Pa'),
                    mass_flow_A_kg_s=('/V3/mdot_A','kg/s'),energy_flow_A_W=('/V3/Phi_A','W'),
                    inlet_temperature_K=('/Inlet/T_I','K'),outlet_temperature_K=('/Outlet/T_I','K'))
    tail = {key:si(*entry)[-3:].tolist() for key,entry in selected.items()}
    return dict(meta,trace_count=len(traces),sample_count=len(t),final_time_s=float(t[-1]),
                tail_times_s=t[-3:].tolist(),tail=tail,first_out_of_domain_temperature_K=float(tb[-1]),
                pre_event_min_V3_B_temperature_K=float(tb[:-1].min()),
                invalid_terminal_sample_retained=True,valid_physical_solution_at_terminal_sample=False,
                simulation_completion_pass=False,production_recovery_allowed=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--retirement-summary',type=Path)
    args = parser.parse_args()
    if args.output.exists() or (args.retirement_summary and args.retirement_summary.exists()):
        raise FileExistsError('Do not overwrite diagnostic evidence')
    base = args.repo/'outputs_storage_audit'
    root = base/'dual_chamber_switch_20260907_v4/trial'
    contract = json.loads((root/'dual_switch_result.json').read_text(encoding='utf-8-sig'))
    if (contract['collection_pass'] or len(contract['cases']) != 0 or contract['attempted_cases'] != 12
            or len(contract['failed_cases']) != 12 or not contract['collect_failure_matrix']
            or contract['execution_commit'] != '390a734598c991467e09ef5a8a29a73353995190'
            or contract['production_model_changed'] or contract['production_checkpoint_loaded']):
        raise ValueError('Failure matrix scope changed')
    rows,hashes = [],dict(contract=sha256(root/'dual_switch_result.json'))
    keys = [(f,p,s) for f in ('native','conservative') for p in ('none','isentropic') for s in (.001,.0005,.00025)]
    for i,key in enumerate(keys,1):
        path = root/f'failed_case_{i}.mat'
        meta,traces = read_leaves(path)
        if (meta != contract['failed_cases'][i-1] or meta['attempted_case_index'] != i
                or tuple(meta[k] for k in ('formulation','power_mode','local_step_s')) != key):
            raise ValueError('Failure matrix contains mismatched cases')
        rows.append(failure_metrics(meta,traces))
        hashes[f'failed_case_{i}'] = sha256(path)
    result = dict(schema='heatdrive_ecc_dual_switch_failure_matrix_v1',diagnostic_audit_complete=True,
                  execution_commit=contract['execution_commit'],cases=rows,input_sha256=hashes,
                  attempted_independent_cases=12,completed_simulations=0,all_fail_at_route_switch=True,
                  minimum_failed_V3_B_temperature_K=min(r['first_out_of_domain_temperature_K'] for r in rows),
                  maximum_failed_V3_B_temperature_K=max(r['first_out_of_domain_temperature_K'] for r in rows),
                  physical_temperature_lower_bound_K=273.16,physical_temperature_gate_relaxed=False,
                  production_model_changed=False,production_recovery_allowed=False,whole_model_first_law_verified=False,
                  table4_reproduction_claim=False)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('cases','input_sha256')},indent=2))
    if not args.retirement_summary:
        return
    prior = base/'dual_chamber_switch_20260907/trial'
    records = []
    for i in range(1,13):
        path = prior/f'case_{i}.mat'
        meta,t,packets = read_case(path)
        summaries = {role:{name:dict(first=float(v[0]),last=float(v[-1]),min=float(v.min()),max=float(v.max()))
                           for name,v in traces.items()} for role,traces in packets.items()}
        records.append(dict(relative_path=str(path.relative_to(args.repo)),sha256=sha256(path),bytes=path.stat().st_size,
                            retain_raw=i in (1,7,10),case=meta,sample_count=len(t),all_SI_trace_summaries=summaries))
    retirement = dict(schema='heatdrive_ecc_dual_switch_superseded_raw_summary_v1',cases=records,
                      retained_raw_indices=[1,7,10],reason='Shared single-port reservoir experiment lacks intended thermal excitation; preserve paired representatives plus every case metric, trace range and hash.',
                      original_audit_sha256=sha256(prior.parent/'dual_switch_audit_v1.json'),
                      new_failure_matrix_raw_must_be_retained=True,production_raw_deletion_allowed=False)
    args.retirement_summary.write_text(json.dumps(retirement,indent=2,allow_nan=False)+'\n',encoding='utf-8')


if __name__=='__main__':
    main()
