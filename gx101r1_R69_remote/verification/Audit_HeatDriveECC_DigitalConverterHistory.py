"""Qualify converter digital-memory observations, not a physical restart."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256,text_field


def check_channel(command,observed,snapshot,heat):
    if command.shape!=(4,) or observed.shape!=(2,4) or snapshot.shape!=(2,) or heat.shape!=(4,):
        raise ValueError('Wrong digital observation shape')
    if not all(np.all(np.isfinite(v)) for v in (command,observed,snapshot,heat)):
        raise ValueError('Nonfinite converter record')
    error=np.abs(heat-command)
    return dict(digital_observation_exact=bool(np.array_equal(observed[1],command)),
                snapshot_previous_input_exact=bool(snapshot[1]==command[-2]),
                native_heat_bitwise_exact=bool(np.array_equal(heat,command)),
                max_native_heat_difference_W=float(np.max(error)),
                native_heat_existing_tolerance_pass=bool(np.all(error<=1e-10+1e-11*np.maximum(np.abs(heat),np.abs(command)))),
                snapshot_values=snapshot.tolist(),observed_final_values=observed[:,-1].tolist())


def compute(repo,root):
    producer_path=root/'converter_history_replay.json';producer=json.loads(producer_path.read_text(encoding='utf-8-sig'))
    if (producer['audit_scope']!='digital_state_observation' or not producer['computation_complete']
            or not producer['digital_state_observation_pass'] or producer['error_message']
            or producer['production_recovery_allowed'] or producer['production_checkpoint_loaded']):
        raise ValueError('Digital-only observation scope failed')
    input_path=repo/'outputs_storage_audit/c200_converter_input_history_20260908.json'
    inputs=json.loads(input_path.read_text(encoding='utf-8-sig'))
    if inputs['source_sha256']!='0BEE740B0B1298B939F5644FD6BEE44296AE1D7BA121A5C5E7C55573FEAB97DD':
        raise ValueError('Wrong frozen input source')
    raw=root/'converter_history_snapshots.mat';rows=[]
    with h5py.File(raw) as f:
        command=f['command'][:]
        digital=f['digital_input']['values_W'][:];t=f['digital_input']['time_s'][:].reshape(-1)
        if (not np.array_equal(command,[r['values_W'] for r in inputs['rows']])
                or not np.array_equal(digital,command) or not np.array_equal(t,inputs['time_s'])):
            raise ValueError('Actual digital inputs differ from frozen commands')
        refs=f['snapshots'][:].reshape(-1)
        if len(refs)!=42:raise ValueError('Require all 42 converters')
        for k,ref in enumerate(refs):
            r=f[ref];name=text_field(r['block_path'])
            if name!=inputs['rows'][k]['block_path'] or not np.array_equal(r['time_s'][:].reshape(-1),t):
                raise ValueError('Wrong converter identity or time')
            row=check_channel(command[k],r['observed_values'][:],r['snapshot_values'][:].reshape(-1),r['heat_W'][:].reshape(-1))
            row['block_path']=name;rows.append(row)
        temperature=f['mass_temperature_K'][:].reshape(-1);heat=f['mass_heat_W'][:].reshape(-1)
        if (temperature.shape!=(4,) or heat.shape!=(4,) or temperature[0]!=340
                or not np.all(np.isfinite(temperature)) or not np.all(np.isfinite(heat))):
            raise ValueError('Thermal control target was not applied')
        residual=1000*np.diff(temperature)-.001*heat[1:]
        bound=8*1000*np.spacing(np.max(np.abs(temperature)))
        energy_pass=bool(np.all(np.abs(residual)<=bound))
    qualified=energy_pass and all(r[k] for r in rows for k in
        ('digital_observation_exact','snapshot_previous_input_exact','native_heat_existing_tolerance_pass'))
    return dict(schema='heatdrive_ecc_digital_converter_history_audit_v1',rows=rows,
        digital_input_exact=True,initial_temperature_K=340,thermal_control_energy_pass=energy_pass,
        max_interval_energy_residual_J=float(np.max(np.abs(residual))),interval_energy_bound_J=float(bound),
        diagnostic_digital_memory_observation_pass=qualified,
        exact_native_heat_count=sum(r['native_heat_bitwise_exact'] for r in rows),
        strict_bitwise_native_heat_gate_pass=all(r['native_heat_bitwise_exact'] for r in rows),
        production_recovery_allowed=False,whole_model_migration_verified=False,
        qualification_scope='Only converter digital records for a new diagnostic probe; no physical OP transfer.',
        native_heat_tolerance='Existing 1e-10 + 1e-11*max(abs(a),abs(b)); bitwise equality is retained separately.',
        input_sha256=dict(producer=sha256(producer_path),raw=sha256(raw),input=sha256(input_path)),
        execution_commit=producer['execution_commit'])


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--repo',type=Path,required=True)
    p.add_argument('--root',type=Path,required=True);p.add_argument('--output',type=Path,required=True);args=p.parse_args()
    if args.output.exists():raise FileExistsError('Do not overwrite evidence')
    r=compute(args.repo,args.root)
    args.output.write_text(json.dumps(r,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in r.items() if k not in ('rows','input_sha256')},indent=2))
    if not r['diagnostic_digital_memory_observation_pass']:raise SystemExit(1)


if __name__=='__main__':main()
