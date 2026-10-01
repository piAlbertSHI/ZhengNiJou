"""Estimate a Stage-4 pressure-path trim from one cold diagnostic.

This is an offline identification diagnostic.  It does not change the model,
replace a mechanism gate, or authorize a seed.  The fit is deliberately
reported as a candidate trim because closed-loop correlation is not a proof of
causality; the candidate must be tested in a fresh independent cold run.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import h5py
import numpy as np


TARGET_KGPS = 3.2e-3


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def series(group, name: str) -> tuple[np.ndarray, np.ndarray]:
    row = group[name]
    return (np.asarray(row["time_s"][0], dtype=float),
            np.asarray(row["values"][0], dtype=float).reshape(-1))


def fit_arm(path: Path, start_s: float, stop_s: float) -> dict:
    with h5py.File(path, "r") as handle:
        signals = handle["signals"]
        probes = handle["stage4_controller_probe_signals"]
        time_s, flow = series(signals, "mass_flow_v4_hot_inlet_kgps")
        _, pressure = series(signals, "pressure_command_se_MPa")
        _, dynamic_ff = series(probes, "stage4_dynamic_feedforward")
        _, route_integral = series(probes, "stage4_route_integral")
        mask = (time_s >= start_s) & (time_s <= stop_s)
        if int(mask.sum()) < 20:
            raise ValueError("Stage-4 flow-pressure window is undersampled")
        p_path = pressure - dynamic_ff - route_integral
        x = p_path[mask]
        y = flow[mask]
        slope, intercept = np.polyfit(x, y, 1)
        if not np.isfinite(slope) or slope <= 0.0:
            raise ValueError("Pressure-path slope is non-positive or non-finite")
        target_p_path = (TARGET_KGPS - intercept) / slope
        current_median = float(np.median(x))
        trim = float(target_p_path - current_median)
        prediction = intercept + slope * x
        return {
            "observations_sha256": sha256(path),
            "window_start_s": float(time_s[mask][0]),
            "window_stop_s": float(time_s[mask][-1]),
            "samples": int(mask.sum()),
            "target_flow_kgps": TARGET_KGPS,
            "observed_mean_flow_kgps": float(np.mean(y)),
            "observed_integrated_flow_relative_error": float(
                np.trapezoid(y, time_s[mask])
                / (TARGET_KGPS * (time_s[mask][-1] - time_s[mask][0])) - 1.0
            ),
            "pressure_path_definition": "pressure_command - dynamic_feedforward - route_integral",
            "pressure_path_median_MPa": current_median,
            "pressure_path_slope_kgps_per_MPa": float(slope),
            "pressure_path_intercept_kgps": float(intercept),
            "pressure_path_r2": float(np.corrcoef(x, y)[0, 1] ** 2),
            "target_pressure_path_MPa": float(target_p_path),
            "candidate_pressure_bias_trim_MPa": trim,
            "fit_rmse_kgps": float(np.sqrt(np.mean((y - prediction) ** 2))),
        }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--experiment-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--window-start-s", type=float, default=8.801)
    parser.add_argument("--window-stop-s", type=float, default=9.850)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Never overwrite flow-pressure-map evidence")
    root = args.experiment_root.resolve()
    execution = json.loads((root / "cold_chamber_execution.json").read_text(encoding="utf-8-sig"))
    arms = [fit_arm(root / arm / "observations.mat", args.window_start_s, args.window_stop_s)
            for arm in ("native", "conservative")]
    result = {
        "schema": "heatdrive_ecc_stage4_flow_pressure_map_diagnostic_v1",
        "diagnostic_only": True,
        "execution_commit": execution.get("execution_commit"),
        "cycle_count": int(execution.get("cycle_count", 1)),
        "arms": arms,
        "arm_candidate_trim_difference_MPa": abs(
            arms[0]["candidate_pressure_bias_trim_MPa"]
            - arms[1]["candidate_pressure_bias_trim_MPa"]),
        "interpretation": "A candidate trim is actionable only through a fresh cold diagnostic; closed-loop regression does not authorize gate relaxation or causal claims.",
        "production_recovery_allowed": False,
        "diagnostic_20cycle_seed_eligible": False,
        "outer_solve_eligible": False,
        "paired_table4_eligible": False,
        "table4_reproduction_claim": False,
        "input_sha256": {
            "native_observations": sha256(root / "native" / "observations.mat"),
            "conservative_observations": sha256(root / "conservative" / "observations.mat"),
            "execution": sha256(root / "cold_chamber_execution.json"),
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"candidate_trim_MPa": arms[0]["candidate_pressure_bias_trim_MPa"],
                      "production_recovery_allowed": False}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
