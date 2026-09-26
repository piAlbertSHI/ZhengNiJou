"""Analyze causal response and transport time scales for Stage 4 diagnostics.

This is a read-only diagnostic. It does not alter the model and cannot grant
seed, recovery, outer-solve, sensitivity, paired-endpoint, or Table 4 status.
The purpose is to distinguish a controller tuning problem from a plant-memory
problem before another expensive cold run is started.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import h5py
import numpy as np


TARGET_FLOW_KGPS = 3.2e-3
ACTIVE_SE_MASS_KG = 0.04181683646625444
WINDOW = (8.801, 9.850)
LAG_LIMIT_S = 0.5


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def read_series(group, name: str) -> tuple[np.ndarray, np.ndarray]:
    row = group[name]
    return (np.asarray(row["time_s"][:], dtype=float).reshape(-1),
            np.asarray(row["values"][:], dtype=float).reshape(-1))


def corr(a: np.ndarray, b: np.ndarray) -> float | None:
    if a.size < 3 or np.std(a) <= 1.0e-14 or np.std(b) <= 1.0e-14:
        return None
    value = float(np.corrcoef(a, b)[0, 1])
    return value if np.isfinite(value) else None


def lagged_correlation(a: np.ndarray, b: np.ndarray, dt: float,
                       limit_s: float = LAG_LIMIT_S) -> dict:
    """Return the lag of b that best correlates with a.

    Positive lag means b is shifted later relative to a. This is descriptive
    only; it is deliberately not used as a production acceptance criterion.
    """
    max_shift = max(1, int(round(limit_s / dt)))
    best = None
    for shift in range(-max_shift, max_shift + 1):
        if shift < 0:
            value = corr(a[-shift:], b[:shift])
        elif shift > 0:
            value = corr(a[:-shift], b[shift:])
        else:
            value = corr(a, b)
        if value is not None and (best is None or value > best["correlation"]):
            best = {"lag_s": float(shift * dt), "correlation": value}
    result = best or {"lag_s": None, "correlation": None}
    result["search_limit_s"] = float(limit_s)
    result["boundary_limited"] = bool(
        result["lag_s"] is not None
        and abs(abs(result["lag_s"]) - limit_s) <= max(dt, 1.0e-12)
    )
    return result


def remove_linear_trend(values: np.ndarray) -> np.ndarray:
    x = np.linspace(-1.0, 1.0, values.size)
    coefficients = np.polyfit(x, values, 1)
    return values - np.polyval(coefficients, x)


def window_slice(time_s: np.ndarray) -> np.ndarray:
    mask = (time_s >= WINDOW[0]) & (time_s <= WINDOW[1])
    if int(mask.sum()) < 20:
        raise ValueError("Stage-4 causal window is undersampled")
    return mask


def audit_arm(observations: Path) -> dict:
    with h5py.File(observations, "r") as handle:
        signals = handle["signals"]
        probes = handle["stage4_controller_probe_signals"]
        time_s, flow = read_series(signals, "mass_flow_v4_hot_inlet_kgps")
        _, pressure = read_series(signals, "pressure_command_se_MPa")
        _, dynamic_ff = read_series(probes, "stage4_dynamic_feedforward")
        _, integrator = read_series(probes, "stage4_integrator_state")
        _, route_integral = read_series(probes, "stage4_route_integral")
        _, inlet_temp = read_series(probes, "stage4_inlet_temperature_delay")
        _, outlet_temp = read_series(probes, "stage4_outlet_temperature_delay")
        if not np.array_equal(time_s, _):
            raise ValueError("Stage-4 probe grids differ")
        dt = float(np.median(np.diff(time_s)))
        mask = window_slice(time_s)
        t = time_s[mask]
        q = flow[mask]
        error = q / TARGET_FLOW_KGPS - 1.0
        residence_s = ACTIVE_SE_MASS_KG / max(abs(float(np.mean(q))), 1.0e-12)
        peak_index = int(np.argmax(np.abs(error)))
        slopes = np.diff(q) / np.diff(t)
        return {
            "observations_sha256": sha256(observations),
            "grid_dt_s": dt,
            "window": {
                "start_s": float(t[0]),
                "stop_s": float(t[-1]),
                "duration_s": float(t[-1] - t[0]),
                "samples": int(t.size),
            },
            "transport_time_scale": {
                "active_se_mass_kg": ACTIVE_SE_MASS_KG,
                "mean_window_flow_kgps": float(np.mean(q)),
                "estimated_residence_s": float(residence_s),
                "window_to_residence_ratio": float((t[-1] - t[0]) / residence_s),
                "window_shorter_than_residence": bool((t[-1] - t[0]) < residence_s),
            },
            "flow_shape": {
                "mean_kgps": float(np.mean(q)),
                "rms_relative_error": float(np.sqrt(np.mean(error ** 2))),
                "max_abs_relative_error": float(np.max(np.abs(error))),
                "peak_abs_error_time_s": float(t[peak_index]),
                "mean_abs_slope_kgps2": float(np.mean(np.abs(slopes))),
                "reverse_flow_fraction": float(np.mean(q < 0.0)),
            },
            "lagged_correlations": {
                "pressure_to_flow_error": lagged_correlation(
                    pressure[mask], error, dt),
                "dynamic_feedforward_to_flow_error": lagged_correlation(
                    dynamic_ff[mask], error, dt),
                "inlet_temperature_to_flow_error": lagged_correlation(
                    inlet_temp[mask], error, dt),
                "outlet_temperature_to_flow_error": lagged_correlation(
                    outlet_temp[mask], error, dt),
                "integrator_to_flow_error": lagged_correlation(
                    integrator[mask], error, dt),
                "route_integral_to_flow_error": lagged_correlation(
                    route_integral[mask], error, dt),
            },
            "detrended_zero_lag_correlations": {
                "pressure_to_flow_error": corr(
                    remove_linear_trend(pressure[mask]),
                    remove_linear_trend(error)),
                "dynamic_feedforward_to_flow_error": corr(
                    remove_linear_trend(dynamic_ff[mask]),
                    remove_linear_trend(error)),
                "outlet_temperature_to_flow_error": corr(
                    remove_linear_trend(outlet_temp[mask]),
                    remove_linear_trend(error)),
                "integrator_to_flow_error": corr(
                    remove_linear_trend(integrator[mask]),
                    remove_linear_trend(error)),
            },
            "controller_state_ranges": {
                "pressure_command_MPa": [float(np.min(pressure[mask])),
                                          float(np.max(pressure[mask]))],
                "dynamic_feedforward": [float(np.min(dynamic_ff[mask])),
                                         float(np.max(dynamic_ff[mask]))],
                "integrator_state": [float(np.min(integrator[mask])),
                                      float(np.max(integrator[mask]))],
                "route_integral": [float(np.min(route_integral[mask])),
                                    float(np.max(route_integral[mask]))],
                "inlet_temperature_K": [float(np.min(inlet_temp[mask])),
                                         float(np.max(inlet_temp[mask]))],
                "outlet_temperature_K": [float(np.min(outlet_temp[mask])),
                                          float(np.max(outlet_temp[mask]))],
            },
        }


def audit_experiment(root: Path) -> dict:
    execution = json.loads((root / "cold_chamber_execution.json").read_text(
        encoding="utf-8-sig"))
    arms = [audit_arm(root / arm / "observations.mat")
            for arm in ("native", "conservative")]
    return {
        "experiment": root.name,
        "execution_commit": execution.get("execution_commit"),
        "diagnostic_branch_overrides": execution.get("diagnostic_branch_overrides", {}),
        "arms": arms,
        "architectural_interpretation": {
            "transport_window_is_quasi_steady": False,
            "reason": "The Stage-4 evaluation window is shorter than the estimated active-SE residence time; this is evidence for a dynamic route-memory problem, not permission to relax the flow gate.",
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--experiment", type=Path, action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Never overwrite causal-response evidence")
    result = {
        "schema": "heatdrive_ecc_stage4_causal_response_audit_v1",
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
        "experiments": len(result["experiments"]),
        "production_recovery_allowed": False,
        "diagnostic_20cycle_seed_eligible": False,
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
