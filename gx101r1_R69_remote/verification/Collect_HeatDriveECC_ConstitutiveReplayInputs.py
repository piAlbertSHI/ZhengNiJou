"""Extract named constitutive inputs with exact causal Unit Delay clock binding."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np
from scipy.io import savemat

from Audit_HeatDriveECC_ObservedStateDrift import matlab_text
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def exact_indices(clock, wanted):
    clock=np.asarray(clock).reshape(-1)
    if clock.size<2 or not np.isfinite(clock).all() or np.any(np.diff(clock)<=0):
        raise ValueError('Require an unambiguous finite source clock')
    dt=float(np.median(np.diff(clock)))
    indices=np.rint((wanted-clock[0])/dt).astype(int)
    if (np.any(indices<0) or np.any(indices>=clock.size)
            or not np.allclose(clock[indices],wanted,rtol=0,atol=1e-9)):
        raise ValueError('Missing exact replay sample; interpolation is forbidden')
    return indices


def collect(root, output):
    if output.exists():raise FileExistsError('Never overwrite a replay input package')
    execution=json.loads((root/'cold_chamber_execution.json').read_text(encoding='utf-8-sig'))
    capture=json.loads((root/'native/diagnostic_state_capture.json').read_text(encoding='utf-8-sig'))
    history=root/'native/diagnostic_state_observation.mat'
    public=root/'native/observations.mat'
    if (not execution['requested_arm_collection_pass'] or execution['error_message']
            or execution['production_recovery_allowed'] or execution['c200_state_imported']
            or sha256(history)!=capture['history_sha256'] or capture['snapshot_time_s']!=execution['stop_time_s']):
        raise ValueError('Require the intact completed diagnostic history')
    dt=.001;stop=execution['stop_time_s'];tau=10.
    wanted=np.sort(np.concatenate([start+half+np.arange(401)*dt
        for start in np.arange(stop-100,stop,tau) for half in (0.,5.)]))
    data={};binding=[]
    identities=(('ECC_Constitutive21_StateDelay','memory',210,'ECC_constitutive21_output',42),
                ('ECC_Constitutive21_SMA_TempDelay','temperature_sma',21,'SMA_Tx21_internal',0),
                ('ECC_Constitutive21_SE_TempDelay','temperature_se',21,'SE_Tx21_internal',0))
    with h5py.File(history) as hf,h5py.File(public) as pf:
        states={}
        for ref in np.asarray(hf['observation/states']).ravel():
            row=hf[ref];name=matlab_text(row['block_path']).rsplit('/',1)[-1]
            if name in {item[0] for item in identities}:
                if name in states:raise ValueError('Duplicate named delay state')
                states[name]=row
        outputs=pf['signals/ECC_constitutive21_output']
        out_indices=exact_indices(outputs['time_s'][:],wanted)
        data['observed_output']=outputs['values'][:,out_indices].T
        for name,key,width,signal,offset in identities:
            row=states[name]
            if row['values'].shape[0]!=width:raise ValueError('Wrong named delay width')
            clock=row['time_s'][:].reshape(-1);selected=exact_indices(clock,wanted)
            current=row['values'][:,selected]
            source=pf['signals/'+signal];public_clock=source['time_s'][:].reshape(-1)
            comparisons={}
            for lag in (0,1):
                previous=source['values'][offset:offset+width,exact_indices(public_clock,wanted-lag*dt)]
                comparisons[lag]=bool(np.array_equal(current,previous))
            if comparisons[1] and not comparisons[0]:
                read_indices=selected;state_clock_shift=0
            elif comparisons[0] and not comparisons[1]:
                read_indices=exact_indices(clock,wanted-dt);state_clock_shift=-dt
            else:raise ValueError('Named delay logging phase is ambiguous or not exact: '+name)
            causal=row['values'][:,read_indices]
            previous=source['values'][offset:offset+width,exact_indices(public_clock,wanted-dt)]
            if not np.array_equal(causal,previous):raise ValueError('Causal input differs from previous physical output')
            data[key]=causal.T
            binding.append(dict(block_name=name,channel_count=width,
                log_value_equals_current_public=comparisons[0],log_value_equals_previous_public=comparisons[1],
                history_clock_shift_for_input_s=state_clock_shift,exact_previous_public_match=True))
    data['time_s']=wanted[:,None]
    output.mkdir(parents=True)
    fixture=output/'constitutive_replay_inputs.mat'
    savemat(fixture,data,do_compression=True)
    record=dict(schema='heatdrive_ecc_constitutive_replay_input_v1',source_root=str(root.resolve()),
        producer=execution['execution_commit'],total_cycles=execution['cycle_count'],
        samples=len(wanted),sample_time_s=dt,per_half_cycle_window_s=[0,.4],half_cycle_offsets_s=[0,5],
        global_cycle_window=[execution['cycle_count']-9,execution['cycle_count']],bindings=binding,
        source_sha256=dict(execution=sha256(root/'cold_chamber_execution.json'),observation=sha256(public),
            history=capture['history_sha256'],configuration=sha256(root/'native/configuration.mat')),
        replay_fixture_sha256=sha256(fixture),source_state_edited=False,operating_point_loaded=False,
        simulation_executed=False,interpolation_used=False,production_recovery_allowed=False)
    (output/'replay_input_contract.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(record,indent=2))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--experiment-root',type=Path,required=True)
    parser.add_argument('--output-root',type=Path,required=True)
    args=parser.parse_args();collect(args.experiment_root,args.output_root)
