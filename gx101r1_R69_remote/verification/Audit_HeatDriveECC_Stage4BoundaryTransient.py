"""Diagnose Stage-4 boundary transients without changing production gates."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import h5py
import numpy as np


TARGET_KGPS = 3.2e-3
GATE_WINDOW = (8.801, 9.850)
STAGE_WINDOW = (8.5, 10.0)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def series(group, name: str) -> tuple[np.ndarray, np.ndarray]:
    row = group[name]
    return (np.asarray(row["time_s"][:], dtype=float).reshape(-1),
            np.asarray(row["values"][:], dtype=float).reshape(-1))


def interval(time: np.ndarray, values: np.ndarray, start: float,
             stop: float) -> dict:
    mask = (time >= start) & (time <= stop)
    if int(mask.sum()) < 2:
        raise ValueError("Stage-4 boundary interval is undersampled")
    t = time[mask]
    q = values[mask]
    rel = q / TARGET_KGPS - 1.0
    return {
        "start_s": float(t[0]),
        "stop_s": float(t[-1]),
        "samples": int(mask.sum()),
        "mean_flow_kgps": float(np.mean(q)),
        "min_flow_kgps": float(np.min(q)),
        "max_flow_kgps": float(np.max(q)),
        "rms_relative_error": float(np.sqrt(np.mean(rel ** 2))),
        "max_abs_relative_error": float(np.max(np.abs(rel))),
        "signed_mass_g": float(1000.0 * np.trapezoid(q, t)),
        "reverse_flow_fraction": float(np.mean(q < 0.0)),
    }


def first_continuous_band(time: np.ndarray, flow: np.ndarray, start: float,
                          stop: float, tolerance: float,
                          hold_s: float = 0.10) -> float | None:
    mask = (time >= start) & (time <= stop)
    indices = np.flatnonzero(mask)
    if indices.size < 2:
        return None
    inside = np.abs(flow[indices] / TARGET_KGPS - 1.0) <= tolerance
    samples = max(2, int(round(hold_s / np.median(np.diff(time[indices])))))
    if samples > inside.size:
        return None
    for idx in range(inside.size - samples + 1):
        if bool(np.all(inside[idx:idx + samples])):
            return float(time[indices[idx]] - start)
    return None


def audit_arm(observations: Path, cycle_index: int) -> dict:
    offset = 10.0 * cycle_index
    with h5py.File(observations, "r") as handle:
        time, flow = series(handle["signals"], "mass_flow_v4_hot_inlet_kgps")
    stage_start = offset + STAGE_WINDOW[0]
    stage_stop = offset + STAGE_WINDOW[1]
    gate_start = offset + GATE_WINDOW[0]
    gate_stop = offset + GATE_WINDOW[1]
    return {
        "observations_sha256": sha256(observations),
        "analysis_cycle_index": cycle_index,
        "analysis_cycle_start_s": offset,
        "stage4_full_interval": interval(time, flow, stage_start, stage_stop),
        "pre_gate_interval": interval(time, flow, stage_start, gate_start),
        "strict_gate_interval": interval(time, flow, gate_start, gate_stop),
        "post_gate_interval": interval(time, flow, gate_stop, stage_stop),
        "first_continuous_in_band_from_boundary_s": {
            "within_5pct": first_continuous_band(
                time, flow, stage_start, stage_stop, 0.05),
            "within_15pct": first_continuous_band(
                time, flow, stage_start, stage_stop, 0.15),
        },
        "boundary_transient_dominates_gate": bool(
            np.mean(flow[(time >= gate_start) & (time <= gate_start + 0.10)])
            < 0.85 * TARGET_KGPS
            and np.mean(flow[(time >= gate_stop - 0.10) & (time <= gate_stop)])
            > 1.05 * TARGET_KGPS
        ),
        "production_gate_unchanged": True,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--experiment", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Never overwrite boundary-transient evidence")
    root = args.experiment.resolve()
    execution = json.loads((root / "cold_chamber_execution.json").read_text(
        encoding="utf-8-sig"))
    cycle_count = int(execution.get("cycle_count", 0))
    if cycle_count < 1:
        raise ValueError("Execution contract has no complete cycle")
    cycle_index = cycle_count - 1
    arms = [audit_arm(root / arm / "observations.mat", cycle_index)
            for arm in ("native", "conservative")]
    result = {
        "schema": "heatdrive_ecc_stage4_boundary_transient_audit_v1",
        "diagnostic_only": True,
        "execution_commit": execution.get("execution_commit"),
        "cycle_count": cycle_count,
        "analysis_cycle_index": cycle_index,
        "arms": arms,
        "production_recovery_allowed": False,
        "seed_eligible": False,
        "outer_solve_eligible": False,
        "paired_table4_eligible": False,
        "table4_reproduction_claim": False,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n",
                           encoding="utf-8")
    print(json.dumps({
        "cycle_index": cycle_index,
        "boundary_transient_dominates_gate": [
            arm["boundary_transient_dominates_gate"] for arm in arms],
        "production_recovery_allowed": False,
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
