"""Read-only coverage audit of states outside the declared periodic gate.

Requires h5py and numpy. Does not promote a checkpoint or change tolerances.
"""
import argparse
import hashlib
import json
from pathlib import Path

import h5py
import numpy as np


def drift_metrics(values, stride):
    values = np.asarray(values, dtype=float)
    if values.ndim != 1 or stride <= 0 or values.size <= stride:
        raise ValueError("Need a scalar time series and at least two cycle phases")
    delta = values[stride:] - values[:-stride]
    if not np.isfinite(delta).all():
        return {"complete_comparison_coverage": False}
    return {
        "complete_comparison_coverage": True,
        "max_K": float(np.max(np.abs(delta))),
        "p99_K": float(np.percentile(np.abs(delta), 99)),
        "rms_K": float(np.sqrt(np.mean(delta**2))),
    }


def audit(contract_path):
    repo = Path(__file__).resolve().parent.parent
    contract = json.loads(contract_path.read_text(encoding="utf-8-sig"))
    source = repo / contract["result_relative_path"]
    with source.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest().upper()
    if digest != contract["result_sha256"]:
        raise ValueError("Frozen result hash mismatch")
    with h5py.File(source, "r") as f:
        p = f["physical"]
        t = p["time_s"][0, :]
        tau = float(f["options/schedule/tau_cycle_s"][0, 0])
        dt = float(t[-1] - t[-2])
        stride = int(round(tau / dt))
        start = int(np.searchsorted(t, t[-1] - 10 * tau - 1e-8))
        if not np.allclose(np.diff(t[start:]), dt, rtol=0, atol=1e-8):
            raise ValueError("The phase comparison requires a uniform time grid")
        buffers = {}
        for name in ("SHEX_buffer_T_K", "HHEX_buffer_T_K",
                     "SMA_HHEX_buffer_T_K", "CHEX_buffer_T_K"):
            buffers[name] = drift_metrics(p[name][0, start:], stride)
        inventory = {}
        for name in sorted(k for k in p if "_inventory_" in k):
            values = p[name][0, start:]
            finite = np.flatnonzero(np.isfinite(values))
            inventory[name] = {
                "samples": int(values.size), "finite_samples": int(finite.size),
                "first_finite_time_s": float(t[start + finite[0]]) if finite.size else None,
                "last_finite_time_s": float(t[start + finite[-1]]) if finite.size else None,
                "ten_cycle_coverage": bool(np.isfinite(values).all()),
            }
        result = {
            "schema": "heatdrive_ecc_internal_state_coverage_v1",
            "source_result": str(source), "source_sha256": digest,
            "window_s": [float(t[start]), float(t[-1])],
            "cycle_period_s": tau, "buffer_same_phase_drift": buffers,
            "native_inventory_coverage": inventory,
            "PI_route_memory_timeseries_recorded": False,
            "complete_internal_state_periodicity_verified": False,
            "steady_parameter_study_allowed": False,
            "scope": "Diagnostic only. Full PI memory trajectories are not exported. "
                     "Buffer drift is not currently included in the production periodic gate. "
                     "Finite inventory coverage is necessary but does not prove periodicity.",
        }
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract", type=Path,
                        default=Path(__file__).with_name("runtime_c180_recovery_contract.json"))
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = audit(args.contract)
    payload = json.dumps(result, indent=2, allow_nan=False)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload + "\n", encoding="utf-8")
    print(payload)
