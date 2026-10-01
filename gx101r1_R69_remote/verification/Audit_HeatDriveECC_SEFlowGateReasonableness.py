"""Audit whether the SE flow gate measures a settled control quantity.

This is a read-only meta-audit.  It never changes the production gate and
never authorizes a seed, recovery, outer solve, or Table 4 claim.  It separates
instantaneous tracking from transported mass and explicitly reports overlap
with a controller Kp transition.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import h5py
import numpy as np


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def trapz(values: np.ndarray, time_s: np.ndarray) -> float:
    return float(np.trapezoid(values, time_s))


def window_metrics(time_s: np.ndarray, flow: np.ndarray, start_s: float,
                   stop_s: float, target_kg_s: float,
                   max_relative_error: float,
                   rms_relative_error: float) -> dict:
    mask = (time_s >= start_s) & (time_s <= stop_s)
    if int(mask.sum()) < 2:
        raise ValueError(f"empty or undersampled window {start_s}:{stop_s}")
    t = time_s[mask]
    q = flow[mask]
    relative = q / target_kg_s - 1.0
    expected_mass_kg = target_kg_s * (t[-1] - t[0])
    signed_mass_kg = trapz(q, t)
    absolute_mass_kg = trapz(np.abs(q), t)
    rms = float(np.sqrt(np.mean(relative ** 2)))
    max_abs = float(np.max(np.abs(relative)))
    return {
        "start_s": float(t[0]),
        "stop_s": float(t[-1]),
        "duration_s": float(t[-1] - t[0]),
        "samples": int(mask.sum()),
        "mean_signed_kg_s": float(np.mean(q)),
        "mean_relative_error": float(np.mean(relative)),
        "mean_absolute_relative_error": float(np.mean(np.abs(relative))),
        "rms_relative_error": rms,
        "max_abs_relative_error": max_abs,
        "signed_transport_mass_g": 1000.0 * signed_mass_kg,
        "absolute_transport_mass_g": 1000.0 * absolute_mass_kg,
        "expected_transport_mass_g": 1000.0 * expected_mass_kg,
        "integrated_signed_mass_relative_error": float(
            signed_mass_kg / expected_mass_kg - 1.0
        ),
        "reverse_flow_fraction": float(np.mean(q < 0.0)),
        "near_zero_flow_fraction": float(np.mean(np.abs(q) < target_kg_s * 0.01)),
        "instantaneous_tracking_gate_pass": bool(
            max_abs <= max_relative_error and rms <= rms_relative_error
        ),
    }


def transition_overlap(execution: dict, start_s: float, stop_s: float) -> dict:
    overrides = execution.get("diagnostic_branch_overrides", {})
    transition_start = float(
        overrides.get("se_stage4_pressure_pi_transition_start_s", 0.0)
    )
    transition_duration = float(
        overrides.get("se_stage4_pressure_pi_transition_duration_s", 0.0)
    )
    transition_stop = transition_start + transition_duration
    overlap_start = max(start_s, transition_start)
    overlap_stop = min(stop_s, transition_stop)
    overlap = max(0.0, overlap_stop - overlap_start)
    return {
        "transition_start_s": transition_start,
        "transition_stop_s": transition_stop,
        "window_start_s": start_s,
        "window_stop_s": stop_s,
        "overlap_s": overlap,
        "overlap_fraction_of_window": overlap / (stop_s - start_s),
        "transition_overlaps_window": bool(overlap > 0.0),
        "transition_covers_window": bool(
            transition_start <= start_s and transition_stop >= stop_s
        ),
    }


def audit_arm(observations: Path, execution: dict, target_kg_s: float,
              ramp_s: float, settled_guard_s: float,
              max_relative_error: float, rms_relative_error: float) -> dict:
    with h5py.File(observations, "r") as handle:
        group = handle["signals"]
        time_s = np.asarray(group["mass_flow_v4_hot_inlet_kgps/time_s"][0], dtype=float)
        stage_specs = {
            "stage2": ("mass_flow_v1_cold_inlet_kgps", 3.5, 5.0),
            "stage4": ("mass_flow_v4_hot_inlet_kgps", 8.5, 10.0),
        }
        stages = {}
        for name, (signal, stage_start, stage_stop) in stage_specs.items():
            half_width = max(ramp_s, settled_guard_s)
            start = stage_start + half_width
            stop = stage_stop - half_width
            metrics = window_metrics(
                time_s,
                np.asarray(group[f"{signal}/values"][0], dtype=float),
                start,
                stop,
                target_kg_s,
                max_relative_error,
                rms_relative_error,
            )
            metrics["controller_transition"] = transition_overlap(
                execution, start, stop
            )
            metrics["tracking_gate_interpretation"] = (
                "non_settled_transition_window"
                if metrics["controller_transition"]["transition_overlaps_window"]
                else "settled_window_candidate"
            )
            metrics["transport_gate_decision"] = "not_defined_by_current_contract"
            stages[name] = metrics
    return {
        "observations_sha256": sha256(observations),
        "stages": stages,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--observations", type=Path, required=True)
    parser.add_argument("--execution", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--target-kgps", type=float, required=True)
    parser.add_argument("--ramp-s", type=float, default=0.15)
    parser.add_argument("--settled-guard-s", type=float, default=0.30)
    parser.add_argument("--max-relative-error", type=float, default=0.15)
    parser.add_argument("--rms-relative-error", type=float, default=0.05)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Never overwrite a reasonableness audit")
    execution = read_json(args.execution)
    result = {
        "schema": "heatdrive_ecc_se_flow_gate_reasonableness_v1",
        "diagnostic_only": True,
        "gate_thresholds_unchanged": True,
        "input_contract": {
            "target_kg_s": args.target_kgps,
            "stage_command_ramp_s": args.ramp_s,
            "se_settled_guard_s": args.settled_guard_s,
            "max_instantaneous_relative_error": args.max_relative_error,
            "max_rms_relative_error": args.rms_relative_error,
        },
        "execution_sha256": sha256(args.execution),
        "arm": audit_arm(
            args.observations,
            execution,
            args.target_kgps,
            args.ramp_s,
            args.settled_guard_s,
            args.max_relative_error,
            args.rms_relative_error,
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
    print(json.dumps(result["arm"], indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
