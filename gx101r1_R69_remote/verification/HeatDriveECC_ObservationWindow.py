"""Exact absolute-time solver grids, including a nonzero restored origin."""
import numpy as np


def window_indices(time, start, stop):
    time = np.asarray(time, dtype=float).reshape(-1)
    if (time.size < 2 or not np.isfinite(time).all()
            or not np.isfinite([start, stop]).all() or start < 0 or stop <= start
            or any(abs(value/.001-round(value/.001)) > 1e-7 for value in (time[0], start, stop))
            or not np.allclose(time, time[0]+np.arange(time.size)*.001, rtol=0, atol=1e-9)):
        raise ValueError('Invalid complete integer-millisecond clock')
    selected = np.flatnonzero((time >= start-1e-9) & (time <= stop+1e-9))
    expected = start+np.arange(round((stop-start)/.001)+1)*.001
    if selected.size != expected.size or not np.allclose(time[selected], expected, rtol=0, atol=1e-9):
        raise ValueError('Missing full absolute-time observation window')
    return selected
