"""Cross-check numerical native identities on independent C22, then report latest buffer drift."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ObservedStateDrift import matlab_text
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from HeatDriveECC_ObservationWindow import window_indices


def states(f):
    result = {}
    for reference in f['observation/states'][:].ravel():
        row=f[reference]
        key=(matlab_text(row['block_path']),matlab_text(row['state_name']))
        if key in result:
            raise ValueError('Duplicate numerical state identity')
        result[key]=row
    return result


def cycle_window(cycle_count, stop):
    if (not isinstance(cycle_count,int) or isinstance(cycle_count,bool) or
            cycle_count<42 or cycle_count>200 or stop!=cycle_count*10):
        raise ValueError('Require a complete qualified-model warmup window')
    return stop-100,stop,cycle_count-9


def audit(mapping_path, independent):
    mapping=json.loads(mapping_path.read_text(encoding='utf-8-sig'))
    root=Path(mapping['source_root'])
    current=json.loads((root/'cold_chamber_execution.json').read_text(encoding='utf-8-sig'))
    window_start,window_stop,first_cycle=cycle_window(current['cycle_count'],current['stop_time_s'])
    if (root.resolve()==independent.resolve() or not current['requested_arm_collection_pass'] or
            current['error_message'] or current['diagnostic_state_options']['mode']!='diagnostic_resume'):
        raise ValueError('Require a completed mapped segment and an independent C22 run')
    if (sha256(root/'native/observations.mat')!=mapping['input_sha256']['native_observation'] or
            sha256(root/'native/diagnostic_state_observation.mat')!=mapping['input_sha256']['history']):
        raise ValueError('Mapping inputs changed')
    execution=json.loads((independent/'cold_chamber_execution.json').read_text(encoding='utf-8-sig'))
    if execution['cycle_count']!=22 or execution['stop_time_s']!=220:
        raise ValueError('Independent validation must use the unchanged-model C22 data')
    stop=execution['stop_time_s'];start=stop-20
    verified=[]
    with h5py.File(independent/'native/observations.mat') as native, \
            h5py.File(independent/'native/diagnostic_state_observation.mat') as history:
        physical=named_rows(native,native['native']);numerical=states(history)
        for item in mapping['matches']:
            coordinate=item['coordinate']
            key=(coordinate['block_path'],coordinate['state_name'])
            if key not in numerical:
                raise ValueError('Fixed numerical coordinate identity changed on independent run')
            row=numerical[key];selected=window_indices(row['time_s'][:],start,stop)
            actual=row['values'][coordinate['coordinate_1based']-1,selected]
            row=physical[item['block_path'],item['variable']]
            selected=window_indices(row['time_s'][:],start,stop)
            expected=row['values'][:].ravel()[selected]
            if not np.array_equal(actual,expected):
                raise ValueError('Independent native identity failed: '+item['block_path']+'/'+item['variable'])
            verified.append(item)
    buffers={}
    with h5py.File(root/'native/diagnostic_state_observation.mat') as f:
        numerical=states(f)
        for name in ('ColdFluidBuffer','HotFluidBuffer','SHEXFluidBuffer','SMAHotFluidBuffer'):
            columns={}
            for variable in ('mass_offset','stored_energy'):
                rows=[item for item in verified if item['block_path'].endswith('/'+name) and item['variable']==variable]
                if len(rows)!=1:
                    raise ValueError('Buffer coordinate identity incomplete')
                c=rows[0]['coordinate'];row=numerical[c['block_path'],c['state_name']]
                time=row['time_s'][:].ravel();values=row['values'][c['coordinate_1based']-1,:]
                endpoints=np.arange(window_start,window_stop+1,10)
                endpoint_indices=[int(np.argmin(abs(time-t))) for t in endpoints]
                if not np.allclose(time[endpoint_indices],endpoints,rtol=0,atol=1e-9):
                    raise ValueError('Ten physical-cycle endpoints missing')
                columns[variable]=np.diff(values[endpoint_indices])
            buffers[name]=[dict(global_cycle=cycle,mass_offset_change_kg=float(columns['mass_offset'][cycle-first_cycle]),
                stored_energy_change_J=float(columns['stored_energy'][cycle-first_cycle]))
                for cycle in range(first_cycle,current['cycle_count']+1)]
    return dict(schema='heatdrive_ecc_empirically_crosschecked_buffer_drift_v1', source_root=str(root),
        independent_root=str(independent),independent_exact_identity_count=len(verified),
        independent_native_overlap_window_s=[start,stop],buffer_comparison_window_s=[window_start,window_stop],
        buffers=buffers,identity_validation_kind='Fixed coordinate bitwise identity on two independent warmup runs',
        compiled_physical_semantics_verified=False,full_native_source_energy_window_available=False,
        numerical_closure_tolerance_used_as_periodic_threshold=False,periodic_gate_assigned=False,
        operating_point_loaded=False,source_state_edited=False,simulation_executed=False,
        production_recovery_allowed=False,outer_solve_eligible=False,
        input_sha256={'mapping':sha256(mapping_path),'independent_history':sha256(independent/'native/diagnostic_state_observation.mat'),
            'independent_native':sha256(independent/'native/observations.mat')})


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mapping',type=Path,required=True)
    parser.add_argument('--independent-root',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Never overwrite identity evidence')
    result=audit(args.mapping,args.independent_root.resolve())
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps(dict(independent_exact_identity_count=result['independent_exact_identity_count'],
        buffer_comparison_window_s=result['buffer_comparison_window_s'],buffers=result['buffers']),indent=2))
