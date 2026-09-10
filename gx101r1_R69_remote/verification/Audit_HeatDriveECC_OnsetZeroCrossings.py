"""Recover recorded valve zero-crossing channels without interpreting private predicates."""
import argparse
import io
import json
from pathlib import Path
import struct
import zipfile
import numpy as np
import pyarrow.parquet as pq
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def build(repo):
    source = repo/'outputs_storage_audit/nonlinear_pre_feedback_profile_20260910/sdi_run_1.mldatx'
    if sha256(source) != 'DCE6D36213AAD270147F658031F3920D13D64FCAE7B9BC9994FEDA2D223C56D1':
        raise ValueError('Archive changed')
    rows = []
    with zipfile.ZipFile(source) as z:
        metadata = json.loads(z.read('runs/sdi_signal_data4.json'))
        t = pq.read_table(io.BytesIO(z.read('parquet/run4/0')))['data'].to_numpy()
        window = t >= .099
        for suffix, owner, storage in [('values', 938, 116), ('crossings', 10018, 117)]:
            selected = [s for s in metadata if '.SMA_V' in s['SignalSource']['Name'] and
                        '.SimulationStatistics.zc_' in s['SignalSource']['Name'] and
                        s['SignalSource']['Name'].endswith('.'+suffix)]
            if len(selected) != 24:
                raise ValueError('Expected four channels for each of six valves')
            data = pq.read_table(io.BytesIO(z.read(f'parquet/run4/{storage}')))['data']
            if len(data) != len(t):
                raise ValueError('Mismatched grids')
            for s in selected:
                if s['IdOfSignalWhoHasMyData'] != owner or s['CompositeDataSize'] != 7200:
                    raise ValueError('Unexpected layout')
            decoded = np.empty((len(t), len(selected)))
            for i in range(len(data)):
                raw = data[i].as_py()
                if len(raw) != 7200:
                    raise ValueError('Incomplete record')
                decoded[i] = [struct.unpack_from('<d', raw, s['CompositeSigByteOffset'])[0] for s in selected]
            if not np.isfinite(decoded).all():
                raise ValueError('Nonfinite diagnostics')
            for j, s in enumerate(selected):
                v = decoded[:, j];near = v[window]
                rows.append(dict(name=s['SignalSource']['Name'], first=float(near[0]), last=float(near[-1]),
                                 minimum=float(near.min()), maximum=float(near.max()),
                                 nonzero_samples_near_event=int(np.count_nonzero(near)),
                                 sign_changes_near_event=int(np.count_nonzero(np.diff(np.sign(near))))))
    return dict(source_sha256=sha256(source), last_recorded_time_s=float(t[-1]), window_start_s=.099,
                channels=rows, predicate_definitions_verified=False, right_iteration_observed=False,
                failure_root_cause_proven=False, production_recovery_allowed=False)


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output-root', type=Path, required=True)
    args=p.parse_args()
    if args.output_root.exists():
        raise FileExistsError('Never overwrite evidence')
    result=build(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'onset_zero_crossings.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
