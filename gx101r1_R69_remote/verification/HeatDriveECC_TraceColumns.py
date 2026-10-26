"""Strict, zero-interpolation reader for lossless native observation packets."""
from pathlib import Path

import numpy as np
from scipy.io import loadmat


def records(value):
    if isinstance(value, dict):
        return [value]
    if isinstance(value, np.ndarray):
        return list(value.ravel())
    return list(value)


def scalar_text(value,allow_empty=False):
    if allow_empty and isinstance(value,np.ndarray) and value.size==0 and value.dtype.kind in 'US':
        return ''
    if not isinstance(value,str) or (not value and not allow_empty):
        raise ValueError('Expected scalar MATLAB text, not a numeric or multi-string field')
    return value


def unpack(packet):
    if packet["schema"] != "heatdrive_ecc_shared_clock_trace_columns_v1" or packet["time_interpolation_performed"] or packet["state_values_modified"] or not packet["not_an_OP_or_restart_state"]:
        raise ValueError("Not an unmodified, non-resumable trace-column packet")
    grids = {}
    for row in records(packet["time_grids"]):
        i = int(row["grid_index"])
        t = np.asarray(row["time_s"], dtype=np.float64).reshape(-1)
        if i in grids or not len(t) or not np.isfinite(t).all() or np.any(np.diff(t)<0):
            raise ValueError("Invalid or duplicate raw time-grid identity")
        grids[i] = t
    if set(grids) != set(range(1,len(grids)+1)):
        raise ValueError("Noncontiguous time-grid IDs")
    out = {}
    for r in records(packet["rows"]):
        key = (scalar_text(r["block_path"]),scalar_text(r["state_name"],True))
        if key in out or int(r["grid_index"]) not in grids:
            raise ValueError("Duplicate trace or unresolved original clock")
        t = grids[int(r["grid_index"])]
        v = np.asarray(r["values"],dtype=np.float64)
        if v.ndim == 0:
            v = v.reshape(1,1)
        elif v.ndim == 1:
            v = v.reshape(1,-1) if len(t)==1 else v.reshape(-1,1)
        if v.ndim != 2 or v.shape != (len(t),int(r["channel_count"])) or not np.isfinite(v).all():
            raise ValueError("Trace time/channel shape or finite-value coverage changed")
        out[key] = {"block_path":key[0],"state_name":key[1],"unit":scalar_text(r["unit"],True),
                    "time_s":t,"values":v,"grid_index":int(r["grid_index"])}
    return out


def load(path):
    return unpack(loadmat(Path(path),simplify_cells=True,variable_names=["packet"])["packet"])
