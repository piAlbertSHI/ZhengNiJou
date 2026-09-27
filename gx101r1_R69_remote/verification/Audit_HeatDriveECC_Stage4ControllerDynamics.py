"""Diagnose Stage-4 controller dynamics without changing any production gate.

The audit separates two failure modes that a single RMS number hides:
sample-to-sample alternating instability and slow scheduled-flow bias.  It
never authorizes a seed, recovery, outer solve, sensitivity run, or Table 4
claim.  Raw observations remain the source of truth; no smoothing is used for
the production decision.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import h5py
import numpy as np


TARGET_KGPS = 0.0032
WINDOW = (8.801, 9.850)
MAX_RELATIVE_ERROR = 0.15
RMS_RELATIVE_ERROR = 0.05


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def read_series(group, name: str) -> tuple[np.ndarray, np.ndarray]:
    row = group[name]
    return (np.asarray(row["time_s"][0], dtype=float),
            np.asarray(row["values"][0], dtype=float))


def window_metrics(time_s: np.ndarray, flow: np.ndarray,
                   offset_s: float = 0.0,
                   start: float = WINDOW[0], stop: float = WINDOW[1]) -> dict:
    start += offset_s
    stop += offset_s
    mask = (time_s >= start) & (time_s <= stop)
    if int(mask.sum()) < 2:
        raise ValueError("Stage-4 controller window is undersampled")
    t = time_s[mask]
    q = flow[mask]
    relative = q / TARGET_KGPS - 1.0
    expected = TARGET_KGPS * (t[-1] - t[0])
    signed = float(np.trapezoid(q, t))
    return {
        "start_s": float(t[0]),
        "stop_s": float(t[-1]),
        "samples": int(mask.sum()),
        "mean_flow_kgps": float(np.mean(q)),
        "rms_relative_error": float(np.sqrt(np.mean(relative ** 2))),
        "max_abs_relative_error": float(np.max(np.abs(relative))),
        "signed_transport_mass_g": 1000.0 * signed,
        "expected_transport_mass_g": 1000.0 * expected,
        "integrated_signed_mass_relative_error": float(signed / expected - 1.0),
        "reverse_flow_fraction": float(np.mean(q < 0.0)),
        "production_instantaneous_gate_pass": bool(
            np.max(np.abs(relative)) <= MAX_RELATIVE_ERROR
            and np.sqrt(np.mean(relative ** 2)) <= RMS_RELATIVE_ERROR
        ),
    }


def alternating_mode(time_s: np.ndarray, flow: np.ndarray,
                     command: np.ndarray, offset_s: float = 0.0) -> dict:
    mask = (time_s >= 9.84 + offset_s) & (time_s <= 9.90 + offset_s)
    indices = np.arange(time_s.size)
    even = mask & (indices % 2 == 0)
    odd = mask & (indices % 2 == 1)
    if even.sum() < 2 or odd.sum() < 2:
        raise ValueError("Alternating-mode diagnostic is undersampled")
    flow_delta = abs(float(flow[even].mean() - flow[odd].mean()))
    command_delta = abs(float(command[even].mean() - command[odd].mean()))
    return {
        "window_start_s": float(time_s[mask][0]),
        "window_stop_s": float(time_s[mask][-1]),
        "flow_even_mean_kgps": float(flow[even].mean()),
        "flow_odd_mean_kgps": float(flow[odd].mean()),
        "command_even_mean_MPa": float(command[even].mean()),
        "command_odd_mean_MPa": float(command[odd].mean()),
        "flow_even_odd_delta_kgps": flow_delta,
        "command_even_odd_delta_MPa": command_delta,
        "alternating_mode_detected": bool(flow_delta > 1.0e-4
                                           and command_delta > 1.0e-3),
    }


def audit_arm(observations: Path, cycle_offset_s: float = 0.0,
              cycle_index: int = 0) -> dict:
    with h5py.File(observations, "r") as handle:
        group = handle["signals"]
        time_s, flow = read_series(group, "mass_flow_v4_hot_inlet_kgps")
        command_time, command = read_series(group, "pressure_command_se_MPa")
        if not np.array_equal(time_s, command_time):
            raise ValueError("Flow and pressure-command grids differ")
        if not np.isfinite(flow).all() or not np.isfinite(command).all():
            raise ValueError("Non-finite controller observation")
        metrics = window_metrics(time_s, flow, offset_s=cycle_offset_s)
        mode = alternating_mode(time_s, flow, command, offset_s=cycle_offset_s)
        full_mask = (time_s >= 8.5 + cycle_offset_s) & (time_s <= 10.0 + cycle_offset_s)
        full_relative = flow[full_mask] / TARGET_KGPS - 1.0
        return {
            "observations_sha256": sha256(observations),
            "grid_samples": int(time_s.size),
            "grid_dt_s": float(np.diff(time_s).min()),
            "analysis_cycle_index": int(cycle_index),
            "analysis_cycle_start_s": float(cycle_offset_s),
            "stage4_production_window": metrics,
            "full_stage4_observation": {
                "mean_flow_kgps": float(flow[full_mask].mean()),
                "rms_relative_error": float(np.sqrt(np.mean(full_relative ** 2))),
                "max_abs_relative_error": float(np.max(np.abs(full_relative))),
                "reverse_flow_fraction": float(np.mean(flow[full_mask] < 0.0)),
            },
            "alternating_mode": mode,
        }


def audit_experiment(root: Path) -> dict:
    execution = json.loads((root / "cold_chamber_execution.json").read_text(
        encoding="utf-8-sig"))
    overrides = execution.get("diagnostic_branch_overrides", {})
    cycle_count = int(execution.get("cycle_count", 1))
    if cycle_count < 1:
        raise ValueError("Execution contract has no complete cycle")
    analysis_cycle_index = cycle_count - 1
    cycle_offset_s = 10.0 * analysis_cycle_index
    rows = [audit_arm(root / arm / "observations.mat", cycle_offset_s,
                      analysis_cycle_index)
            for arm in ("native", "conservative")]
    high_gain = all(row["alternating_mode"]["alternating_mode_detected"]
                    for row in rows)
    low_gain_bias = (not high_gain and any(
        row["stage4_production_window"]["production_instantaneous_gate_pass"] is False
        for row in rows))
    return {
        "schema": "heatdrive_ecc_stage4_controller_dynamics_audit_v1",
        "diagnostic_only": True,
        "execution_commit": execution.get("execution_commit"),
        "cycle_count": cycle_count,
        "analysis_cycle_index": analysis_cycle_index,
        "analysis_cycle_start_s": cycle_offset_s,
        "stage4_kp": overrides.get("se_stage4_pressure_pi_kp_MPa_per_kgps"),
        "stage4_ki": overrides.get("se_stage4_pressure_pi_ki_MPa_per_kgps_s"),
        "arms": rows,
        "failure_mode": (
            "high_gain_discrete_alternating_instability" if high_gain else
            "low_gain_slow_tracking_bias" if low_gain_bias else
            "no_stage4_controller_failure_detected"
        ),
        "production_recovery_allowed": False,
        "diagnostic_20cycle_seed_eligible": False,
        "outer_solve_eligible": False,
        "paired_table4_eligible": False,
        "table4_reproduction_claim": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--experiment", type=Path, action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Never overwrite controller-dynamics evidence")
    result = {
        "schema": "heatdrive_ecc_stage4_controller_dynamics_audit_collection_v1",
        "diagnostic_only": True,
        "experiments": [audit_experiment(path.resolve()) for path in args.experiment],
        "production_recovery_allowed": False,
        "diagnostic_20cycle_seed_eligible": False,
        "outer_solve_eligible": False,
        "paired_table4_eligible": False,
        "table4_reproduction_claim": False,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n",
                           encoding="utf-8")
    print(json.dumps({
        "failure_modes": [row["failure_mode"] for row in result["experiments"]],
        "production_recovery_allowed": False,
        "diagnostic_20cycle_seed_eligible": False,
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
