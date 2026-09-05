"""Audit per-coordinate drift in the saved numerical state observation.

No thresholds are invented for packed solver states or PI memory. This audit
never promotes a checkpoint or equates finite logged states with full coverage.
"""
import argparse
import hashlib
import json
from pathlib import Path

import h5py
import numpy as np


PI_NAMES = ("SEStage2PressurePI_Integrator", "SEStage4PressurePI_Integrator",
            "SMAPressurePI_Integrator")


def comparison_grid(time, tau, cycles=10):
    time = np.asarray(time, dtype=float)
    if (time.ndim != 1 or time.size < 2 or not np.isfinite(time).all()
            or not np.isfinite(tau) or tau <= 0 or cycles < 1):
        raise ValueError("Finite time vector, period and positive window are required")
    dt = float(np.median(np.diff(time)))
    if dt <= 0 or not np.allclose(np.diff(time), dt, rtol=0, atol=1e-8):
        raise ValueError("State comparison requires a strictly increasing uniform grid")
    stride = round(tau / dt)
    if stride < 1 or abs(stride * dt - tau) > 1e-7:
        raise ValueError("Cycle period must contain an integer number of state samples")
    if time[-1] - time[0] < (cycles + 1) * tau - 1e-7:
        return None
    start = int(np.searchsorted(time, time[-1] - cycles * tau - 1e-8))
    if start < stride:
        return None
    current = np.arange(start, time.size)
    if not np.allclose(time[current] - time[current - stride], tau, rtol=0, atol=1e-8):
        raise ValueError("State time alignment is not one physical cycle")
    return current, current - stride


def coordinate_metrics(values, current, prior):
    values = np.asarray(values, dtype=float)
    if values.ndim != 2 or not np.isfinite(values).all():
        raise ValueError("Each state coordinate must be finite")
    delta = values[:, current] - values[:, prior]
    return {
        "max_abs": np.max(np.abs(delta), axis=1).tolist(),
        "p99_abs": np.percentile(np.abs(delta), 99, axis=1).tolist(),
        "rms": np.sqrt(np.mean(delta**2, axis=1)).tolist(),
        "last_endpoint_signed": delta[:, -1].tolist(),
        "observed_min": np.min(values[:, current], axis=1).tolist(),
        "observed_max": np.max(values[:, current], axis=1).tolist(),
    }


def matlab_text(dataset):
    if dataset.attrs.get("MATLAB_empty", 0):
        return ""
    return np.asarray(dataset, dtype="<u2").tobytes(order="F").decode("utf-16le")


def audit(path):
    with path.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest().upper()
    rows = []
    with h5py.File(path, "r") as file:
        observation = file["observation"]
        if matlab_text(observation["schema"]) != "heatdrive_ecc_observed_state_traces_v1":
            raise ValueError("Unsupported observation schema")
        tau = float(observation["cycle_period_s"][0, 0])
        for reference in np.asarray(observation["states"]).ravel():
            source = file[reference]
            time = np.asarray(source["time_s"]).ravel()
            data = source["values"]
            count = int(source["channel_count"][0, 0])
            if data.shape != (count, time.size):
                raise ValueError("MATLAB state dimensions do not match channel/time counts")
            row = {
                "block_path": matlab_text(source["block_path"]),
                "state_name": matlab_text(source["state_name"]),
                "logged_unit": matlab_text(source["unit"]),
                "channel_count": count,
                "sample_count": int(time.size),
                "available_window_s": [float(time[0]), float(time[-1])],
                "ten_cycle_comparison_coverage": False,
                "physical_tolerance_declared": False,
            }
            pair = comparison_grid(time, tau)
            if pair is not None:
                row["ten_cycle_comparison_coverage"] = True
                row["comparison_window_s"] = [float(time[pair[0][0]]), float(time[-1])]
                metrics = {}
                for start in range(0, count, 32):
                    block = coordinate_metrics(data[start:start + 32, :], *pair)
                    for name, values in block.items():
                        metrics.setdefault(name, []).extend(values)
                row["per_coordinate_drift_native_units"] = metrics
            else:
                row["reason"] = "At least eleven cycles are required for ten lagged comparisons"
            rows.append(row)
    names = [row["block_path"].rsplit("/", 1)[-1] for row in rows]
    pi_rows = {name: rows[names.index(name)] for name in PI_NAMES if name in names}
    return {
        "schema": "heatdrive_ecc_observed_state_drift_v1",
        "observation_path": str(path.resolve()), "observation_sha256": digest,
        "cycle_period_s": tau, "comparison_cycles": 10,
        "logged_group_count": len(rows),
        "logged_coordinate_count": sum(row["channel_count"] for row in rows),
        "all_logged_groups_have_ten_cycle_comparisons": bool(rows) and all(
            row["ten_cycle_comparison_coverage"] for row in rows),
        "all_three_PI_memories_observed": len(pi_rows) == len(PI_NAMES) and all(
            row["ten_cycle_comparison_coverage"] for row in pi_rows.values()),
        "PI_memory": pi_rows, "states": rows,
        "complete_internal_state_periodicity_verified": False,
        "steady_parameter_study_allowed": False,
        "scope": "Per-coordinate numerical drift, not a pass/fail physical periodic gate. "
                 "Packed Solver Configuration coordinates still require a physical mapping; "
                 "native fluid inventory and buffer temperatures require independent audits. "
                 "No joint norm combines coordinates with different units.",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("observation", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = audit(args.observation)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({key: result[key] for key in (
        "logged_group_count", "logged_coordinate_count", "observation_sha256",
        "all_logged_groups_have_ten_cycle_comparisons", "all_three_PI_memories_observed",
        "complete_internal_state_periodicity_verified", "steady_parameter_study_allowed")}, indent=2))
