"""Independently audit isolated converter heat delivery, timing and BE storage."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field


def ticks(time, step):
    time = np.asarray(time, dtype=float)
    if not np.all(np.isfinite(time)) or np.any(np.diff(time) <= 0):
        raise ValueError('Nonfinite or non-increasing time grid')
    indices = np.rint(time / step).astype(np.int64)
    # Only an isolated-test tick contract, never a replacement for the C200 exact grid gate.
    error = np.abs(time - indices * step)
    if np.any(error > 2 * np.spacing(np.abs(time))):
        raise ValueError('Samples are not on the declared solver ticks')
    return indices


def audit_trace(trace, command_time, command, capacity, step):
    t = trace['time_s']
    grid = ticks(t, step)
    command_grid = ticks(command_time, step)
    if len(grid) > 1 and not np.all(np.diff(grid) == 1):
        raise ValueError('Missing solver sample')
    if not np.array_equal(t, trace['converter_time_s']):
        raise ValueError('Converter and native sample grids differ')
    for key in ('temperature_K', 'mass_Q_W', 'source_Q_W'):
        if trace[key].shape != t.shape or not np.all(np.isfinite(trace[key])):
            raise ValueError('Wrong or nonfinite trace: ' + key)
    if (trace['converter_values'].shape != (2, len(t))
            or not np.all(np.isfinite(trace['converter_values']))):
        raise ValueError('Wrong converter observation shape')
    idx = np.searchsorted(command_grid, grid, side='right') - 1
    if np.any(idx < 0):
        raise ValueError('Input command does not cover trace')
    expected = command[idx]
    input_pass = bool(np.array_equal(trace['source_Q_W'], expected))
    sign_pass = bool(np.array_equal(trace['mass_Q_W'], -trace['source_Q_W']))
    energy = capacity * np.diff(trace['temperature_K'])
    integral = step * trace['mass_Q_W'][1:]
    residual = energy - integral
    # Analytic scalar thermal mass: explicit floating-point roundoff bound, not fitted.
    roundoff = 8 * capacity * float(np.max(np.spacing(np.abs(trace['temperature_K']))))
    energy_pass = bool(np.all(np.abs(residual) <= roundoff))
    return dict(samples=len(t), start_s=float(t[0]), stop_s=float(t[-1]),
                input_delivery_pass=input_pass, port_sign_pass=sign_pass,
                backward_euler_energy_pass=energy_pass,
                max_interval_energy_residual_J=float(np.max(np.abs(residual), initial=0)),
                interval_roundoff_bound_J=roundoff,
                integrated_mass_heat_J=float(np.sum(integral)),
                endpoint_storage_change_J=float(capacity * (trace['temperature_K'][-1] - trace['temperature_K'][0])),
                total_energy_residual_J=float(np.sum(residual)))


def read_trace(group):
    return {k: group[k][:] if k == 'converter_values' else group[k][:].reshape(-1)
            for k in ('time_s', 'temperature_K', 'mass_Q_W', 'source_Q_W',
                      'converter_time_s', 'converter_values')}


def compute(root):
    metadata = root / 'converter_boundary_trial.json'
    producer = json.loads(metadata.read_text(encoding='utf-8-sig'))
    if (not producer['collection_complete'] or producer['error_message']
            or any(producer[k] for k in ('production_model_loaded', 'production_checkpoint_loaded',
                                        'production_recovery_allowed'))):
        raise ValueError('Incomplete or wrong-scope trial')
    paths = sorted(root.glob('case_*.mat'))
    if len(paths) != len(producer['cases']) or len(paths) not in (4, 6):
        raise ValueError('Incomplete case coverage')
    cases = []
    identities = set()
    hashes = {metadata.name: sha256(metadata)}
    for path in paths:
        with h5py.File(path) as f:
            row = f['row']
            waveform, mode = text_field(row['waveform']), text_field(row['mode'])
            identity = (waveform, mode)
            if identity in identities:
                raise ValueError('Duplicate case')
            identities.add(identity)
            command_time = row['command_time_s'][:].reshape(-1)
            command = row['command_values_W'][:].reshape(-1)
            expected = dict(zero=[0]*7, signed_steps=[0,0,0,5,-3,7,0],
                            fall_to_zero=[0,0,5,0,-3,7,0])[waveform]
            if not np.array_equal(command, expected):
                raise ValueError('Test waveform changed')
            capacity = row['capacity_J_K'][()].item()
            step = row['step_s'][()].item()
            if capacity != 1000 or step != .001:
                raise ValueError('Wrong physical test contract')
            traces = {key: read_trace(row[key]) for key in ('prefix', 'seed', 'reference', 'actual')}
            checks = {key: audit_trace(trace, command_time, command, capacity, step)
                      for key, trace in traces.items()}
            ref, actual = traces['reference'], traces['actual']
            if (len(ref['time_s']) != 7 or len(actual['time_s']) != 7
                    or not np.array_equal(ticks(ref['time_s'], step), ticks(actual['time_s'], step))):
                raise ValueError('Wrong restart comparison window')
            equal = {key: bool(np.array_equal(ref[key], actual[key])) for key in ref}
            initial = {key: trace['converter_values'][:, 0].tolist() for key, trace in traces.items()}
            physical_pass = (all(c[k] for c in checks.values() for k in
                                ('input_delivery_pass','port_sign_pass','backward_euler_energy_pass'))
                             and all(equal[k] for k in ('temperature_K','mass_Q_W','source_Q_W'))
                             and all(traces[k]['temperature_K'][0] == traces['prefix']['temperature_K'][-1]
                                     for k in ('seed','reference','actual')))
            cases.append(dict(waveform=waveform, mode=mode, file=path.name, traces=checks,
                              exact_reference_actual=equal, initial_converter_values=initial,
                              max_time_difference_s=float(np.max(np.abs(ref['time_s']-actual['time_s']))),
                              isolated_physical_delivery_pass=bool(physical_pass)))
        hashes[path.name] = sha256(path)
    waveforms = ('zero','signed_steps') + (('fall_to_zero',) if len(paths)==6 else ())
    if identities != {(w,m) for w in waveforms for m in ('seed_op','seed_op_with_converter_logged_state')}:
        raise ValueError('Wrong test coverage')
    return dict(schema='heatdrive_ecc_converter_evidence_v1',execution_commit=producer['execution_commit'],
                input_driver=producer.get('input_driver','direct'),cases=cases,input_sha256=hashes,
                isolated_physical_delivery_pass=all(c['isolated_physical_delivery_pass'] for c in cases),
                all_converter_observations_exact=all(c['exact_reference_actual']['converter_values'] for c in cases),
                all_time_grids_exact=all(c['exact_reference_actual']['time_s'] for c in cases),
                production_recovery_allowed=False,whole_model_state_preservation_verified=False,
                whole_model_first_law_verified=False,
                timing_scope='Isolated test only: report exact grids separately; match solver ticks within two ULPs.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite evidence')
    result = compute(args.root)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('cases','input_sha256')}, indent=2))
    if not result['isolated_physical_delivery_pass']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
