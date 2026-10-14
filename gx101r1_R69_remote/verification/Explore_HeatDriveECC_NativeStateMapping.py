"""Test exact native/state-coordinate identities; candidate matches are not recovery authority."""
import argparse
import hashlib
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ObservedStateDrift import matlab_text
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field
from HeatDriveECC_ObservationWindow import window_indices


def digest(values):
    values = np.asarray(values, dtype='<f8').copy()
    values[values == 0] = 0
    return hashlib.sha256(values.tobytes()).digest()


def explore(root):
    history = root / 'native/diagnostic_state_observation.mat'
    raw = root / 'native/observations.mat'
    receipt = json.loads((root / 'cold_chamber_execution.json').read_text(encoding='utf-8-sig'))
    stop = receipt['stop_time_s']
    start = stop - 20
    index = {}
    coordinate_rows, coordinate_values = [], []
    with h5py.File(history) as f:
        for reference in f['observation/states'][:].ravel():
            row = f[reference]
            selected = window_indices(row['time_s'][:], start, stop)
            name = matlab_text(row['block_path'])
            state = matlab_text(row['state_name'])
            for begin in range(0, row['values'].shape[0], 32):
                block = row['values'][begin:begin+32, selected]
                for local, values in enumerate(block):
                    identity=dict(block_path=name, state_name=state, coordinate_1based=begin+local+1,
                                  transform='identity', native_delay_s=0)
                    coordinate_rows.append(identity)
                    coordinate_values.append(values.copy())
                    if not np.isfinite(values).all():
                        raise ValueError('Nonfinite state coordinate')
                    if np.ptp(values) == 0:
                        continue
                    index.setdefault(digest(values), []).append(identity)
    coordinates=np.asarray(coordinate_values)
    matches, unmatched, constant = [], [], []
    fields = {'T_I', 'T', 'p_I', 'stored_mass', 'mass_offset', 'stored_energy'}
    with h5py.File(raw) as f:
        for key, row in named_rows(f, f['native']).items():
            if key[1] not in fields:
                continue
            selected = window_indices(row['time_s'][:], start, stop)
            values = row['values'][:].ravel()[selected]
            item = dict(block_path=key[0], variable=key[1], physical_unit=text_field(row['unit']))
            if np.ptp(values) == 0:
                constant.append(item)
                continue
            candidates = index.get(digest(values), [])
            comparison_kind='bitwise identity'
            scale=1
            if not candidates and item['physical_unit']=='MPa':
                scale=1e6
                si=values*scale
                sparse=np.arange(0,si.size,max(1,si.size//128))
                bounds=8*np.finfo(float).eps*np.maximum(1,abs(si[sparse]))
                possible=np.flatnonzero(np.all(abs(coordinates[:,sparse]-si[sparse])<=bounds,axis=1))
                candidates=[coordinate_rows[i] for i in possible if np.all(abs(coordinates[i]-si)<=
                    8*np.finfo(float).eps*np.maximum(1,abs(si)))]
                comparison_kind='explicit MPa-to-Pa conversion, bounded eight-ULP roundoff only'
            if len(candidates) == 1:
                matches.append(dict(**item, coordinate=candidates[0], exact_samples=values.size,
                                    comparison_kind=comparison_kind, native_to_coordinate_scale=scale))
            else:
                unmatched.append(dict(**item, exact_candidate_count=len(candidates)))
    return dict(schema='heatdrive_ecc_native_state_exact_mapping_exploration_v1', source_root=str(root),
        overlap_window_s=[start, stop], uniquely_matched=len(matches), unmatched=len(unmatched),
        constant_unidentifiable=len(constant), matches=matches, unmatched_variables=unmatched,
        constant_variables=constant, numerical_identity_only=True, compiled_physical_semantics_verified=False,
        simulation_executed=False, operating_point_loaded=False, source_state_edited=False,
        production_recovery_allowed=False, outer_solve_eligible=False,
        input_sha256={'history':sha256(history),'native_observation':sha256(raw)})


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--experiment-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Never overwrite mapping evidence')
    result = explore(args.experiment_root.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    print(json.dumps({key: result[key] for key in ('uniquely_matched','unmatched','constant_unidentifiable',
        'compiled_physical_semantics_verified','outer_solve_eligible')}))
