"""Share only verified identical datasets with the pinned retained native arm."""
import argparse
import json
from pathlib import Path

import h5py

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Archive_HeatDriveECC_ObsoleteArm import write_json


def native_object(file, archive_path):
    parts = archive_path.strip('/').split('/')
    if parts[0] == 'native_key_traces':
        parts[0] = 'native'
    obj = file
    try:
        for part in parts:
            if isinstance(obj, h5py.Dataset) and h5py.check_dtype(ref=obj.dtype) is not None:
                if not part.startswith('row_'):
                    return None
                obj = file[obj[:].reshape(-1)[int(part[4:])]]
            else:
                obj = obj[part]
        return obj if isinstance(obj, h5py.Dataset) else None
    except (KeyError, IndexError, ValueError, TypeError):
        return None


def share(old_path, native_path, output, expected_old, expected_native):
    if output.exists() or sha256(old_path) != expected_old or sha256(native_path) != expected_native:
        raise ValueError('Fresh output and pinned inputs required')
    native_relative = '../native/observations.mat'
    if (output.parent.parent / 'native/observations.mat').resolve() != native_path.resolve():
        raise ValueError('External link escaped the retained arm')
    datasets, linked, shared_bytes, local_bytes = [], 0, 0, 0
    with h5py.File(old_path) as old, h5py.File(native_path) as native, h5py.File(output, 'x') as out:
        def copy(group, target):
            nonlocal linked, shared_bytes, local_bytes
            for key, value in group.attrs.items():
                target.attrs[key] = value
            for name, obj in group.items():
                if isinstance(obj, h5py.Group):
                    copy(obj, target.create_group(name))
                    continue
                data = obj[()]
                other = native_object(native, obj.name)
                identical = (other is not None and other.dtype == obj.dtype and other.shape == obj.shape
                             and other[()].tobytes() == data.tobytes())
                if identical:
                    target[name] = h5py.ExternalLink(native_relative, other.name)
                    linked += 1
                    shared_bytes += data.nbytes
                else:
                    target.create_dataset(name, data=data, dtype=obj.dtype)
                    for key, value in obj.attrs.items():
                        target[name].attrs[key] = value
                    local_bytes += data.nbytes
                datasets.append(obj.name)
        copy(old, out)
        out.attrs['identical_numeric_storage_shared_with_retained_native'] = True
        out.attrs['pinned_native_sha256'] = expected_native
        out.attrs['native_dependency_relative'] = native_relative
    with h5py.File(old_path) as old, h5py.File(output) as out:
        for key in datasets:
            a, b = old[key], out[key]
            if a.shape != b.shape or a.dtype != b.dtype or a[()].tobytes() != b[()].tobytes():
                raise ValueError('Shared archive does not preserve every retained dataset exactly')
    if sha256(old_path) != expected_old or sha256(native_path) != expected_native:
        raise ValueError('Pinned input changed')
    return dict(old_archive_path=str(old_path), old_archive_sha256=expected_old,
                old_archive_bytes=old_path.stat().st_size, archive_path=str(output),
                archive_sha256=sha256(output), archive_bytes=output.stat().st_size,
                retained_native_path=str(native_path), retained_native_sha256=expected_native,
                compared_datasets=len(datasets), identical_datasets_shared=linked,
                identical_dataset_logical_bytes_shared=shared_bytes, local_numeric_bytes=local_bytes,
                all_retained_datasets_bitwise_equal=True, compression_or_resampling_used=False,
                original_arms_claimed_identical=False, production_recovery_allowed=False)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--plan', type=Path, required=True)
    p.add_argument('--expected-sha256', required=True)
    p.add_argument('--index', type=int, required=True)
    a = p.parse_args()
    if sha256(a.plan) != a.expected_sha256:
        raise ValueError('Reviewed plan SHA required')
    plan = json.loads(a.plan.read_text(encoding='utf-8-sig'))
    row = plan['arms'][a.index]
    result = share(Path(row['old_key_archive']), Path(row['native_path']), Path(row['key_archive']),
                   row['old_key_archive_sha256'], row['native_sha256'])
    result['source_path'] = row['source']
    result['source_sha256'] = row['source_sha256']
    result['source_bytes'] = row['source_bytes']
    result['retained_bytes_exact'] = True
    write_json(a.plan.with_name(f'key_sharing_{a.index:02d}.json'), result)
    print(json.dumps({k: result[k] for k in ('archive_bytes', 'compared_datasets', 'identical_datasets_shared')}))
