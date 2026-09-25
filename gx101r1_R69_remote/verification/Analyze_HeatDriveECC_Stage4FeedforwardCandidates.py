"""Quantify alternative Stage-4 viscosity closures from one cold diagnostic.

This is an offline diagnostic only.  It does not alter the Simulink model and
never grants seed, recovery, outer-solve, paired-endpoint, or Table 4 status.
The candidate closures are compared against the exact tabulated log-viscosity
law used by the controller, so this script does not silently introduce a new
fluid-property source.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import h5py
import numpy as np


EXPECTED = (
    "stage4_inlet_temperature_delay",
    "stage4_outlet_temperature_delay",
    "stage4_inlet_viscosity",
    "stage4_outlet_viscosity",
    "stage4_endpoint_viscosity_mean",
    "stage4_blended_viscosity",
    "stage4_viscosity_ratio",
    "mass_flow_v4_hot_inlet_kgps",
    "pressure_command_se_MPa",
)
TABLE_T_K = np.array([255.05, 283.15, 313.15, 338.15, 363.15, 393.15])
TABLE_RHO = np.array([1066.03926666667, 1055.38, 1039.77, 1023.55, 1004.39, 977.53])
TABLE_MU_MPA_S = np.array([43.3230278575076, 7.2173, 2.2389, 1.1762, 0.7462, 0.5084])
TABLE_NU = TABLE_MU_MPA_S / TABLE_RHO * 1000.0
REFERENCE_T_K = 303.15
TARGET_FLOW_KGPS = 3.2e-3


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def controller_mu(temperature: np.ndarray) -> np.ndarray:
    dense_t = np.arange(TABLE_T_K[0], TABLE_T_K[-1] + 0.125, 0.25)
    rho = np.interp(dense_t, TABLE_T_K, TABLE_RHO)
    nu = np.interp(dense_t, TABLE_T_K, TABLE_NU)
    mu = rho * nu * 1.0e-6
    return np.exp(np.interp(
        np.clip(temperature, dense_t[0], dense_t[-1]),
        dense_t, np.log(mu)))


def harmonic_log_mean(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    ratio = np.divide(b, a, out=np.ones_like(a), where=a > 0.0)
    denominator = np.log(ratio)
    quotient = np.divide(
        b - a,
        denominator,
        out=0.5 * (a + b),
        where=np.abs(denominator) > 1.0e-12,
    )
    return quotient


def read_series(group, name: str) -> tuple[np.ndarray, np.ndarray]:
    row = group[name]
    return np.asarray(row["time_s"][:], dtype=float).reshape(-1), np.asarray(
        row["values"][:], dtype=float
    ).reshape(-1)


def audit_arm(path: Path, start: float, stop: float, blend_weight: float) -> dict:
    with h5py.File(path, "r") as handle:
        signals = handle["signals"]
        probes = handle["stage4_controller_probe_signals"]
        names = set(signals.keys()) | set(probes.keys())
        missing = [name for name in EXPECTED if name not in names]
        if missing:
            raise ValueError(f"Missing candidate-analysis signals: {missing}")

        source = signals if "mass_flow_v4_hot_inlet_kgps" in signals else probes
        time, flow = read_series(source, "mass_flow_v4_hot_inlet_kgps")
        temperatures = {}
        for name in ("stage4_inlet_temperature_delay", "stage4_outlet_temperature_delay"):
            _, temperatures[name] = read_series(probes, name)
        _, inlet_mu = read_series(probes, "stage4_inlet_viscosity")
        _, outlet_mu = read_series(probes, "stage4_outlet_viscosity")
        _, current_mean = read_series(probes, "stage4_endpoint_viscosity_mean")
        _, current_blend = read_series(probes, "stage4_blended_viscosity")
        _, current_ratio = read_series(probes, "stage4_viscosity_ratio")
        _, pressure = read_series(signals, "pressure_command_se_MPa")
        mask = (time >= start) & (time <= stop)
        if int(mask.sum()) < 2:
            raise ValueError("Stage-4 candidate window is undersampled")

        tin = temperatures["stage4_inlet_temperature_delay"]
        tout = temperatures["stage4_outlet_temperature_delay"]
        # The reference is a fixed property-table quantity.  Inferring it from
        # the arithmetic endpoint mean is wrong when this diagnostic deliberately
        # uses a non-unit blend weight.
        mu_ref = float(controller_mu(np.array([REFERENCE_T_K]))[0])
        mean_temperature_mu = controller_mu(0.5 * (tin + tout))
        arithmetic = 0.5 * (inlet_mu + outlet_mu)
        geometric = np.sqrt(inlet_mu * outlet_mu)
        logarithmic = harmonic_log_mean(inlet_mu, outlet_mu)
        candidates = {
            "arithmetic_endpoint": arithmetic,
            "geometric_endpoint": geometric,
            "logarithmic_endpoint": logarithmic,
            "viscosity_at_arithmetic_temperature": mean_temperature_mu,
        }
        result = {}
        for name, viscosity in candidates.items():
            ratio = viscosity / mu_ref
            result[name] = {
                "mean_viscosity_ratio": float(np.mean(ratio[mask])),
                "min_viscosity_ratio": float(np.min(ratio[mask])),
                "max_viscosity_ratio": float(np.max(ratio[mask])),
                "mean_relative_to_arithmetic": float(
                    np.mean(ratio[mask] / (arithmetic[mask] / mu_ref))
                ),
                "correlation_with_flow": float(np.corrcoef(ratio[mask], flow[mask])[0, 1]),
                "correlation_with_pressure_command": float(
                    np.corrcoef(ratio[mask], pressure[mask])[0, 1]
                ),
            }

        return {
            "arm": path.parent.name,
            "window_start_s": float(time[mask][0]),
            "window_stop_s": float(time[mask][-1]),
            "samples": int(mask.sum()),
            "target_flow_kgps": TARGET_FLOW_KGPS,
            "observed_mean_flow_kgps": float(np.mean(flow[mask])),
            "observed_integrated_flow_relative_error": float(
                np.trapezoid(flow[mask], time[mask])
                / (TARGET_FLOW_KGPS * (time[mask][-1] - time[mask][0]))
                - 1.0
            ),
            "reference_temperature_K": REFERENCE_T_K,
            "reference_viscosity_Pa_s": mu_ref,
            "current_formula_checks": {
                "arithmetic_endpoint_max_abs_residual_Pa_s": float(
                    np.max(np.abs(current_mean - arithmetic))
                ),
                "blended_equals_endpoint_mean_max_abs_residual_Pa_s": float(
                    np.max(np.abs(
                        current_blend
                        - (mean_temperature_mu
                           + blend_weight * (arithmetic - mean_temperature_mu))))
                ),
                "ratio_equals_blended_reference_max_abs_residual": float(
                    np.max(np.abs(current_ratio - current_blend / mu_ref))
                ),
                "blend_weight": blend_weight,
            },
            "candidates": result,
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--experiment-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--window-start-s", type=float, default=8.801)
    parser.add_argument("--window-stop-s", type=float, default=9.850)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Never overwrite candidate-analysis evidence")
    root = args.experiment_root.resolve()
    execution = json.loads((root / "cold_chamber_execution.json").read_text(encoding="utf-8-sig"))
    overrides = execution.get("diagnostic_branch_overrides", {})
    blend_weight = float(overrides.get(
        "se_stage4_endpoint_viscosity_blend_final", 1.0))
    if not 0.0 <= blend_weight <= 1.0:
        raise ValueError("Stage4 endpoint-viscosity blend weight is outside [0,1]")
    arms = [audit_arm(root / arm / "observations.mat", args.window_start_s,
                      args.window_stop_s, blend_weight)
            for arm in ("native", "conservative")]
    result = {
        "schema": "heatdrive_ecc_stage4_feedforward_candidate_analysis_v1",
        "diagnostic_only": True,
        "execution_commit": execution.get("execution_commit"),
        "c200_state_imported": execution.get("c200_state_imported"),
        "production_recovery_allowed": False,
        "seed_eligible": False,
        "outer_solve_eligible": False,
        "paired_table4_eligible": False,
        "table4_reproduction_claim": False,
        "arms": arms,
        "input_sha256": {
            "cold_chamber_execution.json": sha256(root / "cold_chamber_execution.json"),
            "native_observations.mat": sha256(root / "native/observations.mat"),
            "conservative_observations.mat": sha256(root / "conservative/observations.mat"),
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({
        "arms": len(arms),
        "candidate_names": list(arms[0]["candidates"]),
        "production_recovery_allowed": False,
        "seed_eligible": False,
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
