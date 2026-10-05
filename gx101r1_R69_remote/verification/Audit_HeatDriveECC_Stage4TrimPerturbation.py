"""Compare two independent Stage-4 trim diagnostics.

This is a read-only diagnostic.  It does not relax the production flow gate
and it never grants seed, recovery, outer-solve, sensitivity, paired-endpoint,
or Table 4 status.  The purpose is to test whether an offline closed-loop
pressure-path trim transfers to a fresh run.  A high correlation inside one
closed-loop trace is not treated as a causal actuator map.
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


def series(handle: h5py.File, name: str) -> tuple[np.ndarray, np.ndarray]:
    group = handle["signals"][name]
    return (np.asarray(group["time_s"][0], dtype=float),
            np.asarray(group["values"][0], dtype=float).reshape(-1))


def arm_metrics(root: Path, window_start_s: float, window_stop_s: float) -> dict:
    path = root / "native" / "observations.mat"
    with h5py.File(path, "r") as handle:
        time_s, flow = series(handle, "mass_flow_v4_hot_inlet_kgps")
        _, pressure = series(handle, "pressure_command_se_MPa")
        _, dynamic_ff = series(handle, "stage4_dynamic_feedforward")
        _, route_integral = series(handle, "stage4_route_integral")
        _, activity = series(handle, "stage4_feedforward_activity")
    mask = (time_s >= window_start_s) & (time_s <= window_stop_s)
    if int(mask.sum()) < 20:
        raise ValueError("Stage-4 trim comparison window is undersampled")
    error = (flow[mask] - TARGET_KGPS) / TARGET_KGPS
    pressure_path = pressure[mask] - dynamic_ff[mask] - route_integral[mask]
    return {
        "observations_sha256": sha256(path),
        "window_start_s": float(time_s[mask][0]),
        "window_stop_s": float(time_s[mask][-1]),
        "samples": int(mask.sum()),
        "mean_flow_kgps": float(np.mean(flow[mask])),
        "signed_bias_kgps": float(np.mean(flow[mask]) - TARGET_KGPS),
        "rms_relative_error": float(np.sqrt(np.mean(error * error))),
        "max_abs_relative_error": float(np.max(np.abs(error))),
        "mean_pressure_command_MPa": float(np.mean(pressure[mask])),
        "median_pressure_command_MPa": float(np.median(pressure[mask])),
        "mean_pressure_path_MPa": float(np.mean(pressure_path)),
        "median_pressure_path_MPa": float(np.median(pressure_path)),
        "mean_feedforward_activity": float(np.mean(activity[mask])),
    }


def execution_contract(root: Path) -> dict:
    path = root / "cold_chamber_execution.json"
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    return {
        "execution_sha256": sha256(path),
        "execution_commit": data.get("execution_commit"),
        "initialization_source_observations_sha256": data.get(
            "initialization_source_observations_sha256"
        ),
        "c200_state_imported": bool(data.get("c200_state_imported", True)),
        "checkpoint_saved": bool(data.get("checkpoint_saved", True)),
        "stage4_pressure_bias_trim_MPa": float(
            data.get("stage4_pressure_bias_trim_MPa", 0.0)
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-experiment", type=Path, required=True)
    parser.add_argument("--candidate-experiment", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--window-start-s", type=float, default=8.801)
    parser.add_argument("--window-stop-s", type=float, default=9.850)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Never overwrite evidence")

    baseline_contract = execution_contract(args.baseline_experiment)
    candidate_contract = execution_contract(args.candidate_experiment)
    same_initialization = (
        baseline_contract["initialization_source_observations_sha256"]
        == candidate_contract["initialization_source_observations_sha256"]
        and not baseline_contract["c200_state_imported"]
        and not candidate_contract["c200_state_imported"]
        and not baseline_contract["checkpoint_saved"]
        and not candidate_contract["checkpoint_saved"]
    )
    baseline = arm_metrics(args.baseline_experiment, args.window_start_s,
                           args.window_stop_s)
    candidate = arm_metrics(args.candidate_experiment, args.window_start_s,
                            args.window_stop_s)
    candidate_flow_worse = (
        candidate["rms_relative_error"] > baseline["rms_relative_error"]
        or abs(candidate["signed_bias_kgps"]) > abs(baseline["signed_bias_kgps"])
    )
    result = {
        "schema": "heatdrive_ecc_stage4_trim_perturbation_audit_v1",
        "diagnostic_only": True,
        "target_flow_kgps": TARGET_KGPS,
        "window": {
            "start_s": args.window_start_s,
            "stop_s": args.window_stop_s,
        },
        "baseline": baseline,
        "candidate": candidate,
        "baseline_execution": baseline_contract,
        "candidate_execution": candidate_contract,
        "same_initialization_contract": same_initialization,
        "candidate_flow_worse": candidate_flow_worse,
        "causal_transfer_pass": bool(same_initialization and not candidate_flow_worse),
        "causal_conclusion": (
            "REJECTED: the closed-loop trim did not transfer; the candidate "
            "increased Stage-4 flow bias. The offline pressure-path fit is "
            "association only and cannot authorize a sign flip or seed."
            if same_initialization and candidate_flow_worse
            else "INCONCLUSIVE: the comparison contract was not satisfied."
        ),
        "production_recovery_allowed": False,
        "diagnostic_20cycle_seed_eligible": False,
        "outer_solve_eligible": False,
        "paired_table4_eligible": False,
        "table4_reproduction_claim": False,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "same_initialization_contract": same_initialization,
        "candidate_flow_worse": candidate_flow_worse,
        "causal_transfer_pass": result["causal_transfer_pass"],
        "production_recovery_allowed": False,
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
