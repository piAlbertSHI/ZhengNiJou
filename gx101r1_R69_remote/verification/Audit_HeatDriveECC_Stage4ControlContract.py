"""Audit the effective Stage-4 control contract from a completed cold run.

This is a read-only diagnostic.  It compares the commanded route-integrator
enable with the observed integrator path and the measured Stage-4 flow.  It
does not change production gates, authorize a seed, or infer causality from a
single response metric.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import h5py
import numpy as np


STRICT_WINDOW = (9.84, 9.85)
TARGET_KGPS = 0.0032


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


def window_mask(time_s: np.ndarray, start: float, stop: float) -> np.ndarray:
    mask = (time_s >= start) & (time_s <= stop)
    if int(mask.sum()) < 2:
        raise ValueError(f"undersampled window {start}:{stop}")
    return mask


def summarize_window(time_s: np.ndarray, signals: dict[str, np.ndarray],
                     start: float, stop: float) -> dict:
    mask = window_mask(time_s, start, stop)
    result = {"start_s": start, "stop_s": stop, "samples": int(mask.sum())}
    for name, values in signals.items():
        selected = values[mask]
        result[name] = {
            "mean": float(np.mean(selected)),
            "min": float(np.min(selected)),
            "max": float(np.max(selected)),
            "nonzero_fraction": float(np.mean(np.abs(selected) > 1.0e-12)),
        }
    return result


def audit_arm(observations: Path, configuration: Path) -> dict:
    with h5py.File(observations, "r") as obs, h5py.File(configuration, "r") as cfg:
        signals = obs["signals"]
        time_s, flow = series(signals, "mass_flow_v4_hot_inlet_kgps")
        names = [
            "stage4_flow_error",
            "stage4_integrator_input",
            "stage4_integrator_state",
            "stage4_integrator_output_gate",
            "stage4_route_integral",
            "stage4_dynamic_feedforward",
            "stage4_bias_sum",
            "stage4_pressure_command",
        ]
        observed = {}
        for name in names:
            signal_time, values = series(signals, name)
            if not np.array_equal(time_s, signal_time):
                raise ValueError(f"signal grid mismatch: {name}")
            observed[name] = values

        command_group = cfg["commands/SE_stage4_pressure_integrator_enable_command"]
        command_time = np.asarray(command_group["time_s"][0], dtype=float)
        command = np.asarray(command_group["values"][0], dtype=float).reshape(-1)
        if not np.allclose(time_s, command_time, rtol=0.0, atol=1.0e-12):
            raise ValueError("integrator command and observations use different grids")

        strict = window_mask(time_s, *STRICT_WINDOW)
        error_from_flow = TARGET_KGPS - flow
        flow_error = observed["stage4_flow_error"]
        flow_error_residual = flow_error - error_from_flow
        p_path_term = (
            observed["stage4_pressure_command"]
            - observed["stage4_dynamic_feedforward"]
            - observed["stage4_route_integral"]
        )
        strict_observed = summarize_window(
            time_s,
            {"flow_kgps": flow,
             "flow_error_kgps": flow_error,
             "flow_error_target_minus_flow_residual_kgps": flow_error_residual,
             "integrator_input": observed["stage4_integrator_input"],
             "integrator_state": observed["stage4_integrator_state"],
             "integrator_output_gate": observed["stage4_integrator_output_gate"],
             "route_integral": observed["stage4_route_integral"],
             "dynamic_feedforward": observed["stage4_dynamic_feedforward"],
             "bias_sum": observed["stage4_bias_sum"],
             "pressure_command": observed["stage4_pressure_command"],
             "derived_p_path_term": p_path_term,
             "integrator_enable_command": command},
            *STRICT_WINDOW,
        )

        outside_mask = (time_s >= 8.5) & (time_s < STRICT_WINDOW[0])
        command_active_outside = float(np.mean(command[outside_mask] > 0.0))
        command_active_strict = float(np.mean(command[strict] > 0.0))
        input_abs_strict = float(np.max(np.abs(observed["stage4_integrator_input"][strict])))
        output_abs_strict = float(np.max(np.abs(observed["stage4_integrator_output_gate"][strict])))
        p_path_strict = p_path_term[strict]
        p_path_error_corr = float(np.corrcoef(p_path_strict, flow_error[strict])[0, 1])
        state_span_strict = float(
            np.max(observed["stage4_integrator_state"][strict])
            - np.min(observed["stage4_integrator_state"][strict])
        )
        return {
            "observations_sha256": sha256(observations),
            "configuration_sha256": sha256(configuration),
            "strict_window": strict_observed,
            "command_activity_fraction_8_5_to_9_84_s": command_active_outside,
            "command_activity_fraction_strict_window": command_active_strict,
            "strict_integrator_input_abs_max": input_abs_strict,
            "strict_integrator_output_abs_max": output_abs_strict,
            "strict_integrator_state_span": state_span_strict,
            "strict_flow_error_target_minus_flow_max_abs_residual": float(
                np.max(np.abs(flow_error_residual[strict]))
            ),
            "strict_route_integral_effective": bool(
                command_active_strict > 0.0
                and (input_abs_strict > 1.0e-12 or output_abs_strict > 1.0e-12)
            ),
            "strict_integrator_memory_frozen": bool(
                command_active_strict == 0.0
                and input_abs_strict <= 1.0e-12
                and output_abs_strict <= 1.0e-12
                and state_span_strict <= 1.0e-12
            ),
            "strict_derived_p_path_abs_max": float(np.max(np.abs(p_path_strict))),
            "strict_derived_p_path_active": bool(
                np.max(np.abs(p_path_strict)) > 1.0e-12
            ),
            "strict_derived_p_path_flow_error_correlation": p_path_error_corr,
            "stage4_alternating_response_requires_separate_p_path_audit": True,
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--experiment", type=Path, action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Never overwrite Stage-4 control-contract evidence")

    arms = {}
    for experiment in args.experiment:
        arms[experiment.name] = audit_arm(
            experiment / "observations.mat", experiment / "configuration.mat"
        )
    result = {
        "schema": "heatdrive_ecc_stage4_control_contract_audit_v1",
        "diagnostic_only": True,
        "strict_window_s": list(STRICT_WINDOW),
        "target_kgps": TARGET_KGPS,
        "arms": arms,
        "interpretation": (
            "The strict-window route integrator is effective only when its "
            "command and observed path are both active.  If frozen, the "
            "strict-window alternating response must be audited on the P/" 
            "feedforward path rather than attributed to route PI memory."
        ),
        "production_recovery_allowed": False,
        "diagnostic_20cycle_seed_eligible": False,
        "outer_solve_eligible": False,
        "paired_table4_eligible": False,
        "table4_reproduction_claim": False,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(json.dumps({
        "strict_integrator_memory_frozen": {
            arm: data["strict_integrator_memory_frozen"]
            for arm, data in arms.items()
        },
        "production_recovery_allowed": False,
    }, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
