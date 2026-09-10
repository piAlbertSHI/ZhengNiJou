"""Decode bounded valve evidence from the archived profiler composite stream."""
import argparse
import io
import json
from pathlib import Path
import struct
import zipfile
import h5py
import numpy as np
import pyarrow.parquet as pq
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def build(repo):
    root = repo/'outputs_storage_audit'
    path = root/'nonlinear_pre_feedback_profile_20260910/sdi_run_1.mldatx'
    if sha256(path) != 'DCE6D36213AAD270147F658031F3920D13D64FCAE7B9BC9994FEDA2D223C56D1':
        raise ValueError('Archive changed')
    prefix = 'heatdrive_ecc_coupled_se21.'
    pressure = prefix+'SMAPressurePI_SimulinkPS_output0'
    names = [pressure]+[prefix+f'SMAValveCmdPS{k}_output0' for k in range(1, 7)]
    with zipfile.ZipFile(path) as z:
        metadata = json.loads(z.read('runs/sdi_signal_data4.json'))
        selected = []
        for name in names:
            hits = [x for x in metadata if x['SignalSource']['Name'] == name]
            if len(hits) != 1:
                raise ValueError('Ambiguous signal')
            s = hits[0]
            if s['CompositeDataSize'] != 42976 or s['IdOfSignalWhoHasMyData'] != 19270 or s['Dimensions'] != [1]:
                raise ValueError('Unexpected composite layout')
            selected.append(s)
        data = pq.read_table(io.BytesIO(z.read('parquet/run4/119')))['data']
        t = pq.read_table(io.BytesIO(z.read('parquet/run4/0')))['data'].to_numpy()
        values = np.empty((len(t), len(selected)))
        if len(data) != len(t):
            raise ValueError('Different time/data lengths')
        for i in range(len(data)):
            raw = data[i].as_py()
            if len(raw) != 42976:
                raise ValueError('Incomplete composite sample')
            values[i] = [struct.unpack_from('<d', raw, s['CompositeSigByteOffset'])[0] for s in selected]
    with h5py.File(root/'nonlinear_pre_feedback_ramp_20260910/failed_public_observations.mat') as f:
        s = f['signals/cold_observer_pressure']
        if not np.array_equal(t, s['time_s'][()].ravel()) or not np.array_equal(values[:, 0], s['values'][()].ravel()):
            raise ValueError('Independent pressure decoder cross-check failed')
    if not np.isfinite(values).all() or t[-1] != .1:
        raise ValueError('Invalid prefix')
    window = t >= .099
    rows = [dict(name=s['SignalSource']['Name'], metadata_units_unverified=s['Units'],
                 first=float(values[window, j][0]), last=float(values[-1, j]),
                 minimum=float(values[window, j].min()), maximum=float(values[window, j].max()))
            for j, s in enumerate(selected)]
    return dict(archive_sha256=sha256(path), decoder_pressure_crosscheck_pass=True,
                last_observed_time_s=float(t[-1]), window_start_s=.099, samples=int(window.sum()),
                signals=rows, right_event_iteration_observed=False, units_independently_verified=False,
                complete_network_consistency_verified=False, production_recovery_allowed=False)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__);p.add_argument('--output-root', type=Path, required=True)
    args = p.parse_args()
    if args.output_root.exists():
        raise FileExistsError('Never overwrite evidence')
    result = build(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'onset_valve_archive.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
