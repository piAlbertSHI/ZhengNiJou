"""Compare recorded prefixes exactly, without interpolation or a physical pass."""
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256


def compare(a, b):
    same_shape = a.shape == b.shape
    finite = bool(np.isfinite(a).all() and np.isfinite(b).all())
    return dict(same_shape=same_shape, finite=finite,
                exactly_equal=bool(same_shape and np.array_equal(a, b)),
                max_abs_difference=float(np.max(np.abs(a-b)))
                if same_shape and finite and a.size else None)


def build(repo):
    root = repo / 'outputs_storage_audit'
    paths = [root / name / 'failed_public_observations.mat' for name in (
        'nonlinear_ramp_direct_bias_dynamic_20260910',
        'nonlinear_ramp_hold_gate_delay_20260911')]
    rows = []
    with h5py.File(paths[0]) as a, h5py.File(paths[1]) as b:
        sa, sb = a['signals'], b['signals']
        assert set(sa) == set(sb), 'Signal inventory changed'
        for name in sorted(sa):
            x, y = sa[name], sb[name]
            assert 'time_s' in x and 'time_s' in y
            assert 'values' in x and 'values' in y
            rows.append(dict(signal=name,
                             time=compare(x['time_s'][()], y['time_s'][()]),
                             values=compare(x['values'][()], y['values'][()])))
    return dict(schema='heatdrive_ecc_hold_delay_prefix_v1',
                files=[dict(path=str(p), sha256=sha256(p)) for p in paths],
                signal_count=len(rows),
                exact_time_count=sum(r['time']['exactly_equal'] for r in rows),
                exact_value_count=sum(r['values']['exactly_equal'] for r in rows),
                nonfinite_signal_count=sum(not r['values']['finite'] for r in rows),
                interpolation_used=False, event_right_side_verified=False,
                production_recovery_allowed=False, signals=rows)


if __name__ == '__main__':
    repo = Path(__file__).resolve().parents[1]
    out = repo / 'outputs_storage_audit/hold_delay_prefix_20260911'
    if out.exists():
        raise FileExistsError('Never overwrite evidence; build(repo) is read-only')
    result = build(repo)
    out.mkdir()
    (out / 'prefix_comparison.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in result.items() if k not in ('signals', 'files')}, indent=2))
