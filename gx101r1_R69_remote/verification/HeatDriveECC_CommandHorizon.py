"""Independent checks for explicit, comparison-only future-command extension."""
import hashlib
import json
from pathlib import Path
import re

import h5py
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256


def contract(c, window):
    if (c['schema'] != 'heatdrive_ecc_command_horizon_comparison_v1' or
            c['case'] not in ('reference', 'extended') or
            c['source_horizon_cycles'] != 200 or c['future_horizon_cycles'] != 1000 or
            c['actual_horizon_cycles'] != (200 if c['case'] == 'reference' else 1000) or
            c['runtime_metadata_horizon_cycles'] != c['actual_horizon_cycles'] or
            c['source_snapshot_s'] < 400 or c['source_snapshot_s'] % 20 or
            c['source_snapshot_s']+20 >= 1990 or not 255.05 <= c['source_Tc_K'] <= 393.15 or
            window != [c['source_snapshot_s'], c['source_snapshot_s']+20] or
            c['source_state_edited'] is not False or c['comparison_only'] is not True or
            any(not re.fullmatch('[A-F0-9]{64}', c[key]) for key in (
                'source_OP_sha256', 'source_qualification_sha256', 'prefix_proof_sha256', 'payload_sha256'))):
        raise ValueError('Not a declared comparison-only horizon experiment')
    return True


def prefix_arrays(old_time, old, new_time, new, through):
    a, b = np.asarray(old_time).ravel(), np.asarray(new_time).ravel()
    x, y = np.asarray(old), np.asarray(new)
    if (a.ndim != 1 or b.ndim != 1 or a.size < 2 or b.size < 2 or
            any(v.dtype != np.dtype('float64') for v in (a, b, x, y)) or
            not all(np.isfinite(v).all() for v in (a, b, x, y)) or
            np.any(np.diff(a) <= 0) or np.any(np.diff(b) <= 0) or
            x.ndim != 2 or y.ndim != 2 or x.shape[0] != y.shape[0] or
            x.shape[1] != a.size or y.shape[1] != b.size or
            a[0] != 0 or b[0] != 0 or a[-1] != 2000 or b[-1] != 10000):
        raise ValueError('Invalid source/future command coordinates')
    ai, bi = np.flatnonzero(a > through), np.flatnonzero(b > through)
    if not ai.size or not bi.size or ai[0] != bi[0]:
        raise ValueError('Interpolation bracket differs')
    end = int(ai[0])+1
    exact = lambda v, w: v.shape == w.shape and np.array_equal(np.ascontiguousarray(v).view(np.uint64),
                                                              np.ascontiguousarray(w).view(np.uint64))
    if not exact(a[:end], b[:end]) or not exact(x[:, :end], y[:, :end]):
        raise ValueError('Past command or next interpolation knot changed')
    return end


def audit_prefix(root, c):
    path = root.parent/'command_prefix.json'; payload = root.parent/'command_payload.mat'
    if sha256(path) != c['prefix_proof_sha256'] or sha256(payload) != c['payload_sha256']:
        raise ValueError('Changed command proof or actual array payload')
    p = json.loads(path.read_text(encoding='utf-8-sig'))
    if (p['schema'] != 'heatdrive_ecc_future_command_prefix_v1' or
            p['source_snapshot_s'] != c['source_snapshot_s'] or p['comparison_stop_s'] != c['source_snapshot_s']+20 or
            p['old_horizon_cycles'] != 200 or p['new_horizon_cycles'] != 1000 or
            p['source_state_edited'] or p['resampling_used'] or p['physical_parameters_changed'] or
            p['payload_sha256'] != c['payload_sha256']):
        raise ValueError('Changed command extension scope')
    names = [r['variable'] for r in p['commands']]
    if (len(names) != len(set(names)) or len(names) != p['unique_command_variables'] or
            len(p['bindings']) != p['actual_command_blocks'] or
            {r['variable'] for r in p['bindings']} != set(names)):
        raise ValueError('Incomplete actual command inventory')
    with h5py.File(payload) as f:
        for r in p['commands']:
            if (r['prefix_and_interpolation_bracket_bitwise_equal'] is not True or r['resampling_used'] is not False or
                    r['first_possible_changed_interval_s'] <= p['comparison_stop_s'] or
                    r['interpolation_method'] not in ('linear', 'zoh')):
                raise ValueError('Unsupported or changed source-command prefix')
            arrays = []
            for group, prefix in (('reference', 'old'), ('extended', 'new')):
                g = f['payload/'+group+'/'+r['variable']]
                t, v = np.asarray(g['time_s']), np.asarray(g['values'])
                for data, key in ((t, 'time'), (v, 'values')):
                    if hashlib.sha256(data.tobytes(order='C')).hexdigest().upper() != r[prefix+'_'+key+'_sha256']:
                        raise ValueError('Command payload array identity changed')
                arrays.extend((t, v))
            prefix_arrays(*arrays, p['comparison_stop_s'])
    return dict(actual_command_blocks=p['actual_command_blocks'], unique_command_variables=len(names),
                prefix_with_interpolation_bracket_exact=True, future_end_s=10000,
                actual_future_boundary_crossing_verified=False)
