"""Retain exact diagnostic key traces before retiring a reviewed obsolete arm raw file."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field


NATIVE_KEYS = {'T', 'T_I', 'p_A', 'p_I', 'mdot_A', 'mdot_B', 'Phi_A', 'Phi_B',
               'stored_mass', 'stored_energy', 'auxiliary_energy', 'environment_pv_energy'}
STREAMS = ('signals', 'source_traces', 'pressure_probe_signals',
           'stage4_controller_probe_signals', 'thermal_boundary_signals', 'boundary_metadata')


def retained_mask(time):
    time = np.asarray(time).reshape(-1)
    if not len(time) or not np.isfinite(time).all() or np.any(np.diff(time) < 0):
        raise ValueError('Invalid source time axis')
    tolerance = 16 * np.spacing(max(1.0, abs(float(time[-1]))))
    return (time <= time[0] + 10 + tolerance) | (time >= time[-1] - 20 - tolerance)


def selected_data(data, mask):
    axes = [axis for axis, size in enumerate(data.shape) if size == len(mask)]
    if len(axes) != 1:
        raise ValueError('Ambiguous time dimension; do not guess')
    return np.take(data, np.flatnonzero(mask), axis=axes[0]), axes[0]


def write_json(path, value):
    with path.open('x', encoding='utf-8', newline='\n') as out:
        json.dump(value, out, indent=2, ensure_ascii=False, allow_nan=False)
        out.write('\n')


def export(source, output, expected_sha):
    if output.exists() or sha256(source) != expected_sha:
        raise ValueError('Fresh archive and exact source SHA required')
    records = []
    with h5py.File(source, 'r') as src, h5py.File(output, 'x') as dst:
        dst.attrs['schema'] = 'heatdrive_ecc_retired_arm_key_evidence_v1'
        dst.attrs['source_sha256'] = expected_sha
        dst.attrs['recovery_allowed'] = False
        dst.attrs['full_original_raw_reverification_available'] = False
        dst.attrs['compression_or_resampling_used'] = False
        dst.attrs['public_history_policy'] = 'First 10 s and last 20 s of each recorded axis; original sample grid, no interpolation'

        def copy(obj, target, name, address):
            if isinstance(obj, h5py.Group):
                group = target.create_group(name)
                if 'time_s' in obj and 'values' in obj:
                    time = obj['time_s'][()]
                    mask = retained_mask(time)
                    if len(mask) > 1 and not np.all(mask):
                        group.attrs['middle_time_history_retired'] = True
                        for key, value in obj.items():
                            if key in ('time_s', 'values'):
                                data, axis = selected_data(value[()], mask)
                                group.create_dataset(key, data=data, dtype=value.dtype)
                                records.append(dict(source_dataset=value.name,
                                                    archive_dataset=group[key].name,
                                                    selection_time_dataset=obj['time_s'].name,
                                                    selection_axis=axis))
                            else:
                                copy(value, group, key, address + '/' + key)
                        return
                for key, value in obj.items():
                    copy(value, group, key, address + '/' + key)
            elif h5py.check_dtype(ref=obj.dtype) is not None:
                group = target.create_group(name)
                group.attrs['reference_array_shape'] = obj.shape
                for index, ref in enumerate(obj[:].flat):
                    if not ref:
                        raise ValueError('Unexpected null MATLAB reference')
                    copy(src[ref], group, f'row_{index:04d}', address + f'@{index}')
            else:
                data = obj[()]
                target.create_dataset(name, data=data, dtype=obj.dtype)
                records.append(dict(source_dataset=obj.name, archive_dataset=target[name].name,
                                    shape=list(obj.shape), dtype=str(obj.dtype)))

        for stream in STREAMS:
            if stream in src:
                copy(src[stream], dst, stream, '/' + stream)
        native = dst.create_group('native_key_traces')
        identities = set()
        for index, ref in enumerate(src['native'][:].flat):
            row = src[ref]
            block, variable = text_field(row['block_path']), text_field(row['state_name'])
            if variable not in NATIVE_KEYS:
                continue
            if (block, variable) in identities:
                raise ValueError('Duplicate native identity')
            identities.add((block, variable))
            copy(row, native, f'row_{index:04d}', '/native')
        if not identities or not records or 'signals' not in dst:
            raise ValueError('Missing key diagnostic evidence')
        dst.attrs['native_key_trace_count'] = len(identities)
    # Reopen both independent files and compare every retained numeric/character byte.
    with h5py.File(source, 'r') as src, h5py.File(output, 'r') as dst:
        for row in records:
            a, b = src[row['source_dataset']][()], dst[row['archive_dataset']][()]
            if 'selection_time_dataset' in row:
                mask = retained_mask(src[row['selection_time_dataset']][()])
                a, axis = selected_data(a, mask)
                if axis != row['selection_axis']:
                    raise ValueError('Changed time dimension')
            if a.shape != b.shape or a.dtype != b.dtype or a.tobytes() != b.tobytes():
                raise ValueError('Retained trace bytes differ')
            if dst[row['archive_dataset']].compression is not None:
                raise ValueError('Unexpected compression')
    if sha256(source) != expected_sha:
        raise ValueError('Source changed during evidence extraction')
    return dict(schema='heatdrive_ecc_retired_arm_key_evidence_v1', source_path=str(source),
                source_sha256=expected_sha, archive_path=str(output), archive_sha256=sha256(output),
                source_bytes=source.stat().st_size, archive_bytes=output.stat().st_size,
                verified_retained_datasets=len(records), native_key_traces=len(identities),
                all_public_signal_and_available_source_and_probe_identities_retained=True,
                public_time_history='First recorded 10 s and last recorded 20 s, original samples only',
                full_original_time_history_retained=False,
                retained_bytes_exact=True, compression_or_resampling_used=False,
                omitted_native_variables='Other native variables not in the explicit NATIVE_KEYS set',
                original_raw_is_not_replaced_by_a_restore_source=True, production_recovery_allowed=False)


def run(plan_path, expected_sha, apply):
    if sha256(plan_path) != expected_sha:
        raise ValueError('Reviewed exact plan SHA required')
    plan = json.loads(plan_path.read_text(encoding='utf-8-sig'))
    if plan['schema'] != 'heatdrive_ecc_obsolete_arm_relief_v1':
        raise ValueError('Wrong plan')
    evidence_path = plan_path.with_name('arm_key_evidence_receipt.json')
    if not apply:
        if evidence_path.exists():
            raise FileExistsError('Do not repeat export')
        rows = []
        for row in plan['arms']:
            source = Path(row['source'])
            if source.name != 'observations.mat' or source.parent.name != 'conservative':
                raise ValueError('Only the exact obsolete conservative arm is admitted')
            rows.append(export(source, Path(row['key_archive']), row['source_sha256']))
        receipt = dict(plan_sha256=expected_sha, arms=rows, raw_deleted_bytes=0)
        write_json(evidence_path, receipt)
        return dict(mode='export', arms=len(rows), retained_trace_bytes=sum(r['archive_bytes'] for r in rows))
    receipt = json.loads(evidence_path.read_text(encoding='utf-8'))
    if receipt['plan_sha256'] != expected_sha:
        raise ValueError('Evidence receipt belongs to another plan')
    # Deletion itself is performed by the literal-path PowerShell executor.
    for row in receipt['arms']:
        if (not row['retained_bytes_exact'] or
                sha256(Path(row['archive_path'])) != row['archive_sha256'] or
                sha256(Path(row['source_path'])) != row['source_sha256']):
            raise ValueError('Changed archived or original evidence')
    return dict(mode='verified_before_retirement', arms=len(receipt['arms']), all_evidence_hashes_pass=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', type=Path, required=True)
    parser.add_argument('--expected-sha256', required=True)
    parser.add_argument('--verify-before-retirement', action='store_true')
    args = parser.parse_args()
    print(json.dumps(run(args.plan, args.expected_sha256, args.verify_before_retirement), indent=2))
