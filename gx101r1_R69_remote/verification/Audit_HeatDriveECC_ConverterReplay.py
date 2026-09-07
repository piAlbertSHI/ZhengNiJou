"""Audit the rejected 42-channel replay without authorizing recovery."""
import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile

import h5py
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field


def compute(repo):
    base=repo/'outputs_storage_audit'
    root=base/'c200_converter_history_replay_20260908_v2'
    producer_path=root/'converter_history_replay.json'
    producer=json.loads(producer_path.read_text(encoding='utf-8-sig'))
    command_path=base/'c200_converter_input_history_20260908.json'
    commands=json.loads(command_path.read_text(encoding='utf-8-sig'))
    if (producer['computation_complete'] or not producer['collection_complete']
            or producer['exact_input_delivery'] or producer['production_recovery_allowed']
            or producer['production_checkpoint_loaded'] or not producer['error_message']):
        raise ValueError('Rejected replay scope changed')
    rows=[]
    mat_path=root/'converter_history_snapshots.mat'
    with h5py.File(mat_path) as f:
        raw_command=f['command'][:]
        if not np.array_equal(raw_command,[r['values_W'] for r in commands['rows']]):
            raise ValueError('MAT/JSON input history differs')
        refs=f['snapshots'][:].reshape(-1)
        if len(refs)!=42 or len(producer['delivery'])!=42 or len(producer['snapshots'])!=42:
            raise ValueError('Incomplete converter coverage')
        for k,ref in enumerate(refs):
            raw=f[ref]; meta=producer['delivery'][k]; snap=producer['snapshots'][k]; item=commands['rows'][k]
            name=text_field(raw['block_path']);t=raw['time_s'][:].reshape(-1);q=raw['heat_W'][:].reshape(-1)
            if (not name==meta['block_path']==snap['block_path']==item['block_path']
                    or not np.array_equal(q,meta['heat_W']) or not np.array_equal(t,commands['time_s'])
                    or not np.all(np.isfinite(q))):
                raise ValueError('Replay record mismatch')
            expected=raw_command[k];delta=q-expected
            if np.any((expected==0)&(q!=0)):
                raise ValueError('Unexpected nonzero heat at zero input')
            nz=expected!=0
            ulp=np.abs(delta[nz])/np.spacing(np.abs(expected[nz]))
            rows.append(dict(block_path=name,exact_time=True,exact_heat=bool(np.array_equal(q,expected)),
                max_heat_error_W=float(np.max(np.abs(delta))),max_heat_error_ULP=float(np.max(ulp,initial=0)),
                reported_snapshot_values=snap['snapshot_values'],
                reported_snapshot_previous_input_exact=bool(snap['snapshot_values'][1]==expected[-2]),
                snapshot_scope='Public snapshot JSON; opaque MATLAB timeseries bytes protected by MAT hash, not decoded.'))
        temperature=f['mass_temperature_K'][:].reshape(-1);heat=f['mass_heat_W'][:].reshape(-1)
        residual=1000*np.diff(temperature)-.001*heat[1:]
        energy=dict(initial_temperature_K=float(temperature[0]),capacity_J_K=1000,
                    max_BE_residual_J=float(np.max(np.abs(residual))),
                    note='Observed initial T is 300 K: the replay did not enable the requested 340 K block target.')
    slx=base/'c200_source_compatibility_20260907/source/gx101r1_R69_remote/heatdrive_ecc_coupled_se21.slx'
    if sha256(slx)!='F1D07FDE12F442AFB2F735D5A9A833269CF433437896E2096F23AE984575EA5E':
        raise ValueError('Archived physical model changed')
    expected_params=dict(Unit='W',FilteringAndDerivatives='provide',UdotUserProvided='0',
                         SimscapeFilterOrder='1',InputFilterTimeConstant='0.001',AffineConversion='off')
    parameters=[]
    with zipfile.ZipFile(slx) as z:
        for file in z.namelist():
            if file.startswith('simulink/systems/') and file.endswith('.xml'):
                for b in ET.fromstring(z.read(file)).iter('Block'):
                    if b.get('Name','').startswith('ConstitutiveHeatPS_'):
                        p={x.get('Name'):x.text for x in b.iter('P')}
                        actual={key:p.get(key) for key in expected_params}
                        parameters.append(dict(xml=file,name=b.get('Name'),parameters=actual))
    if len(parameters)!=42 or any(r['parameters']!=expected_params for r in parameters):
        raise ValueError('Archived converter configuration coverage mismatch')
    return dict(schema='heatdrive_ecc_converter_replay_independent_v1',rows=rows,thermal_mass=energy,
                exact_time_count=sum(r['exact_time'] for r in rows),exact_heat_count=sum(r['exact_heat'] for r in rows),
                reported_snapshot_previous_input_exact_count=sum(r['reported_snapshot_previous_input_exact'] for r in rows),
                archived_converter_parameters=parameters,strict_replay_gate_pass=False,
                production_recovery_allowed=False,whole_model_migration_verified=False,
                input_sha256=dict(producer=sha256(producer_path),input=sha256(command_path),
                                  raw=sha256(mat_path),archived_model=sha256(slx)))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():raise FileExistsError('Do not overwrite evidence')
    result=compute(args.repo)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('rows','input_sha256','archived_converter_parameters')},indent=2))
    raise SystemExit(1)  # The strict scientific outcome remains rejected.


if __name__=='__main__':main()
