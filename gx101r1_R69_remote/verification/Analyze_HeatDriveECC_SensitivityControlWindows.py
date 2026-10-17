"""Disjoint public/metric repeatability with native inventories, never an asymptotic claim."""
import argparse
from pathlib import Path
from statistics import mean

import h5py

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Analyze_HeatDriveECC_RecordedTenCycles import join_measured, native_statistics
from Close_HeatDriveECC_SplitObservation import read
from Close_HeatDriveECC_SensitivityColdCase import write
from Compare_HeatDriveECC_SameTcRepeatability import compare_metrics
from HeatDriveECC_ObservationWindow import window_indices
from HeatDriveECC_PublicPeriodicity import audit_public_statistics


def window_metrics(rows):
    if len(rows)!=10 or any(b['cycle']!=a['cycle']+1 for a,b in zip(rows,rows[1:])):
        raise ValueError('Require ten equally long consecutive cycle means')
    fields=('temperature_lift_eq9_K','cooling_power_eq10_W','SCP_W_per_g','CHEX_sensor_mean_W','positive_SHEX_heat_mean_W')
    if any(r['window_s'][1]-r['window_s'][0]!=10 for r in rows):raise ValueError('Unequal cycle duration')
    r={k:mean(c[k] for c in rows) for k in fields}
    r['heat_driven_COP']=r['cooling_power_eq10_W']/r['positive_SHEX_heat_mean_W']
    return r


def analyze(closeout,output):
    if output.exists():raise FileExistsError('Never overwrite a window decision')
    q=read(closeout);frozen=Path(q['frozen_result_path']);r=read(frozen)
    if sha256(frozen)!=q['frozen_result_sha256'] or q['completed_cycles']<40:raise ValueError('Changed completed collection')
    root=Path(r['last_verified_packet_root']).parent;stop=r['last_verified_snapshot_time_s'];records=[];dependencies=[]
    for end in (stop-100,stop):
        paths=list(root.glob(f'periodicity_C{int(end/10):03d}_attempt*/target_window_stability.json'))
        if len(paths)!=1:raise ValueError('Ambiguous actual window observation')
        target=read(paths[0]);folder=paths[0].parent
        index_path=folder/'measured_window.json';index=read(index_path);thermal_path=folder/'original_thermal_statistics.json';thermal=read(thermal_path)
        if (index['window_s']!=[end-100,end] or target['window_s']!=index['window_s'] or
                sha256(index_path)!=target['measured_window_sha256'] or sha256(index_path)!=thermal['measured_window_sha256']):
            raise ValueError('Changed window clock or binding')
        review=audit_public_statistics(thermal['statistics']);parts={}
        for p in index['packets']:
            raw,cfg=Path(p['observation_path']),Path(p['configuration_path'])
            if sha256(raw)!=p['observation_sha256'] or sha256(cfg)!=p['configuration_sha256']:raise ValueError('Changed native source')
            manifest=read(Path(p['packet_root'])/'packet_manifest.json')
            if manifest['sensitivity_case_contract_sha256']!=q['case_contract_sha256'] or manifest['prescribed_Tc_K']!=276.95:
                raise ValueError('Mixed case or temperature')
            with h5py.File(raw) as f:
                selected={k:v for k,v in named_rows(f,f['native']).items() if k[1] in ('T','T_I','stored_mass','stored_energy')}
                if parts and set(selected)!=set(parts):raise ValueError('Changed native identities')
                for key,row in selected.items():
                    unit='K' if key[1] in ('T','T_I') else 'kg' if key[1]=='stored_mass' else 'J'
                    ix=window_indices(row['time_s'][:],*p['window_s'])
                    parts.setdefault(key,[]).append((row['time_s'][:].ravel()[ix],scalar_series(row,unit)[ix][None,:]))
        temperatures=[];inventories=[]
        for (block,variable),values in parts.items():
            time,data=join_measured(values)
            row=dict(block_path=block,variable=variable,**native_statistics(time,data))
            (temperatures if variable in ('T','T_I') else inventories).append(row)
        if len(temperatures)!=119 or len(inventories)!=12:raise ValueError('Incomplete native storage coverage')
        with h5py.File(index['packets'][0]['configuration_path']) as cfg:
            mass=float(cfg['options/equilibrium/m_r_kg'][0,0])
        records.append(dict(window_s=index['window_s'],public_predicates=review,target_precision_pass=target['precision_pass'],
            lift_span_K=target['lift_span_K'],SCP_span_W_per_g=target['SCP_span_W_per_g'],performance=window_metrics(target['cycles']),
            active_SE_mass_kg=mass,native_temperatures=temperatures,native_explicit_inventories=inventories,
            native_drift_tolerance_invented=False))
        dependencies.extend(dict(path=str(p),sha256=sha256(p)) for p in (index_path,thermal_path,paths[0]))
    decision=compare_metrics(records[0]['performance'],records[1]['performance'],.1,.01)
    public=all(x['public_predicates']['original_public_flag'] for x in records)
    precision=all(x['target_precision_pass'] for x in records)
    record=dict(schema='heatdrive_ecc_sensitivity_disjoint_control_windows_v1',source_closeout_sha256=sha256(closeout),
        case_contract_sha256=q['case_contract_sha256'],temperature_K=276.95,windows=records,files=dependencies,
        **decision,public_predicates_both_pass=public,target_precision_both_pass=precision,
        finite_precision_nominal_control_qualified=public and precision and decision['disjoint_metric_repeatability_pass'],
        performance_window_definition='Full ten-cycle window; arithmetic mean of equally long cycle trapezoidal means',
        performance_mass_basis='active SE mass only; SCP in W/g',
        full_internal_state_periodicity_verified=False,steady_L8_effects_evaluated=False,
        C200_gap_attribution_authorized=False,production_recovery_allowed=False,table4_reproduction_claim=False)
    output.parent.mkdir(parents=True,exist_ok=True);write(output,record)
    return {k:v for k,v in record.items() if k not in ('windows','files')}


if __name__=='__main__':
    import json
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--closeout',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    print(json.dumps(analyze(**vars(p.parse_args())),indent=2))
