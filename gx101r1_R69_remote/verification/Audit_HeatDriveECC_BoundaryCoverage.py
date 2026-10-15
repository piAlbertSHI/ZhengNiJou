"""Distinguish an exported clock from finite measured thermal-boundary coverage."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256


def coverage(time,values,start,stop):
    time=np.asarray(time,dtype=float);values=np.asarray(values,dtype=float)
    if (time.ndim!=1 or values.ndim!=2 or values.shape[-1]!=time.size or not np.isfinite(time).all() or
            np.any(np.diff(time)<=0) or start>=stop):raise ValueError('Invalid saved boundary grid')
    selected=(time>=start-1e-9)&(time<=stop+1e-9)
    if not selected.any():raise ValueError('Requested window not represented on clock')
    valid=np.isfinite(values).all(axis=0);indices=np.flatnonzero(valid)
    return dict(clock_window_s=[float(time[0]),float(time[-1])],clock_samples=int(time.size),
        finite_sample_count=int(valid.sum()),invalid_sample_count=int((~valid).sum()),
        finite_support_endpoints_s=[float(time[indices[0]]),float(time[indices[-1]])] if indices.size else [],
        finite_support_contiguous=bool(indices.size and np.all(np.diff(indices)==1)),
        requested_window_s=[start,stop],requested_sample_count=int(selected.sum()),
        requested_window_all_finite=bool(time[0]<=start+1e-9 and time[-1]>=stop-1e-9 and valid[selected].all()))


def audit(root):
    execution=json.loads((root/'cold_chamber_execution.json').read_text(encoding='utf-8-sig'))
    if not execution['requested_arm_collection_pass'] or execution['error_message']:
        raise ValueError('Require a complete diagnostic observation')
    stop=execution['stop_time_s'];rows={}
    with h5py.File(root/'native/observations.mat') as f:
        boundary=f['thermal_boundary_signals'];time=boundary['time_s'][:].ravel()
        for name,row in boundary['fields'].items():
            if not np.array_equal(time,row['time_s'][:].ravel()):raise ValueError('Boundary clocks disagree')
            rows[name]=coverage(time,row['values'][:],stop-100,stop)
    return dict(schema='heatdrive_ecc_observed_boundary_finite_coverage_v1',source_root=str(root),
        total_cycles=execution['cycle_count'],fields=rows,
        exported_clock_is_not_measured_native_coverage=True,
        all_boundaries_have_requested_ten_cycle_coverage=all(r['requested_window_all_finite'] for r in rows.values()),
        missing_historical_observation_is_not_mechanism_failure=True,
        engineering_pump_proxies_must_not_be_injected_as_native_heat=True,
        simulation_executed=False,source_state_edited=False,production_recovery_allowed=False,
        input_sha256={'observations':sha256(root/'native/observations.mat'),
            'execution':sha256(root/'cold_chamber_execution.json')})


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--experiment-root',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True);args=p.parse_args()
    if args.output.exists():raise FileExistsError('Never overwrite boundary coverage evidence')
    result=audit(args.experiment_root.resolve());args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({name:row for name,row in result['fields'].items() if not row['requested_window_all_finite']},indent=2))
