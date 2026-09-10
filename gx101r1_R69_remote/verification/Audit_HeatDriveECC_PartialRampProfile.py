"""Recover bounded scalar evidence from an incomplete profiler SDI archive."""
import argparse
import io
import json
from pathlib import Path
import zipfile

import h5py
import numpy as np
import pyarrow.parquet as pq
from Audit_HeatDriveECC_ColdPassivePSObserver import sha256


def build(repo):
    root = repo / 'outputs_storage_audit'
    folder = root / 'nonlinear_pre_feedback_profile_20260910'
    archive = folder / 'sdi_run_1.mldatx'
    prior = root / 'nonlinear_pre_feedback_ramp_20260910/failed_public_observations.mat'
    comparisons = []
    with zipfile.ZipFile(archive) as z, h5py.File(prior) as f:
        if z.testzip() is not None:
            raise ValueError('Archive CRC failed')
        runs = json.loads(z.read('runs/sdi_run_data.json'))
        if len(runs) != 1 or runs[0]['id'] != 4:
            raise ValueError('Unexpected run identity')
        meta = runs[0]['OutputMetaData']
        if (meta['StopEvent'] != 'DiagnosticError' or meta['StopTime'] != .10000000000000037
                or meta['InitialStopTime'] != .14 or meta['SolverName'] != 'ode23t'
                or float(meta['SolverMaxStepSize']) != .00001):
            raise ValueError('Different failure requires separate diagnosis')
        signals = json.loads(z.read('runs/sdi_signal_data4.json'))
        storage = {x['signalId']: x for x in json.loads(z.read('runs/parquetSignalStorageMetadataRun4.json'))}
        for name, old in [('ColdObserver_pressure_Output', 'cold_observer_pressure'),
                          ('ColdPreFeedbackPressureDerivative', 'cold_pre_feedback_derivative_MPa_s')]:
            selected = [x for x in signals if x['SignalSource']['Name'] == name]
            if len(selected) != 1:
                raise ValueError('Ambiguous signal')
            s = selected[0]
            if s['Dimensions'] != [1] or s['CompositeDataSize'] != 8 or s['CompositeSigByteOffset'] != 0:
                raise ValueError('Only standalone double scalars supported')
            loc = storage[s['id']]
            arrays = []
            for key in ('timeStorageId', 'dataStorageId'):
                ids = loc[key]
                if len(ids) != 1 or ids[0] < 0:
                    raise ValueError('Unsupported storage layout')
                table = pq.read_table(io.BytesIO(z.read(f'parquet/run4/{ids[0]}')))
                if table.column_names != ['data']:
                    raise ValueError('Unexpected parquet columns')
                arrays.append(table['data'].to_numpy())
            t, v = arrays
            old_signal = f['signals/' + old]
            equal = np.array_equal(t, old_signal['time_s'][()].ravel()) and np.array_equal(v, old_signal['values'][()].ravel())
            if not equal or not np.isfinite(t).all() or not np.isfinite(v).all():
                raise ValueError('Profiler prefix differs from archived failure')
            comparisons.append(dict(name=name, samples=len(t), last_time_s=float(t[-1]),
                                    last_value=float(v[-1]), exact_prior_prefix_match=True))
    missing = [name for name in ('solver_profile.mat', 'compiled_states_inspection.json', 'sdi_scalar_observations.mat')
               if not (folder / name).exists()]
    return dict(partial_evidence_audit_pass=True, terminal_session_id=96207, terminal_exit_code=None,
                terminal_exit_status_known=False, simulation_metadata=meta, signal_count=len(signals),
                archive_crc_pass=True, archive_bytes=archive.stat().st_size, archive_sha256=sha256(archive),
                prior_public_observations_sha256=sha256(prior), comparisons=comparisons,
                missing_outputs=missing, profiler_capture_complete=False, full_jacobian_analyzed=False,
                failed_right_iteration_observed=False, production_recovery_allowed=False,
                science_gate_pass=False, table4_reproduction_claim=False)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-root', type=Path, required=True)
    args = parser.parse_args()
    if args.output_root.exists():
        raise FileExistsError('Never overwrite evidence')
    result = build(Path(__file__).resolve().parents[1])
    args.output_root.mkdir(parents=True)
    (args.output_root / 'partial_ramp_profile_audit.json').write_text(
        json.dumps(result, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
