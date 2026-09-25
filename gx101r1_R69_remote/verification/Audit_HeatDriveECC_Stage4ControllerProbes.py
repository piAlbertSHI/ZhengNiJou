"""Audit diagnostic Stage-4 controller-chain probe coverage.

The probes are observational only.  This audit never grants a cold seed,
recovery, outer-solve, sensitivity, paired-endpoint, or Table 4 status.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256


EXPECTED = (
    "stage4_inlet_temperature_delay",
    "stage4_outlet_temperature_delay",
    "stage4_inlet_viscosity",
    "stage4_outlet_viscosity",
    "stage4_endpoint_viscosity_mean",
    "stage4_blended_viscosity",
    "stage4_viscosity_ratio",
    "stage4_weighted_viscosity_delta",
    "stage4_feedforward_ratio_sum",
    "stage4_dynamic_feedforward",
    "stage4_flow_error",
    "stage4_integrator_input",
    "stage4_integrator_state",
    "stage4_integrator_output_gate",
    "stage4_route_integral",
    "stage4_bias_sum",
    "stage4_pressure_command",
)


def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def normalized(time: np.ndarray, values: np.ndarray, start: float, stop: float):
    time = np.asarray(time, dtype=float).reshape(-1)
    values = np.asarray(values, dtype=float).reshape(-1)
    expected = round((stop - start) / 0.001) + 1
    if start > 0.0 and time.size == round(stop / 0.001) + 1:
        first = round(start / 0.001)
        time = time[first:first + expected]
        values = values[first:first + expected]
    elif (start > 0.0 and time.size == expected + 1
          and abs(time[0] - (start - 0.001)) <= 1e-9):
        time = time[1:]
        values = values[1:]
    expected_time = start + np.arange(expected) * 0.001
    valid = bool(
        time.size == expected
        and values.size == expected
        and np.allclose(time, expected_time, rtol=0.0, atol=1e-9)
        and np.isfinite(values).all()
    )
    return time, values, valid


def audit_arm(root: Path, arm: str, start: float, stop: float) -> dict:
    folder = root / arm
    contract = read(folder / "stage4_controller_probe_contract.json")
    names = tuple(contract.get("observation_signal_names", ()))
    contract_gate = bool(
        contract.get("schema") == "heatdrive_ecc_stage4_controller_probe_contract_v1"
        and contract.get("probe_count") == len(EXPECTED)
        and contract.get("simulation_run") is True
        and contract.get("state_imported") is False
        and contract.get("production_recovery_allowed") is False
        and set(names) == set(EXPECTED)
    )
    rows = []
    with h5py.File(folder / "observations.mat", "r") as handle:
        group = handle["stage4_controller_probe_signals"]
        for name in EXPECTED:
            if name not in group:
                raise ValueError(f"Missing Stage-4 controller probe: {arm}/{name}")
            time, values, valid = normalized(
                group[name]["time_s"][:], group[name]["values"][:], start, stop
            )
            rows.append({
                "signal": name,
                "samples": int(values.size),
                "min": float(np.min(values)) if values.size else float("nan"),
                "max": float(np.max(values)) if values.size else float("nan"),
                "finite": bool(np.isfinite(values).all()) if values.size else False,
                "time_grid_pass": valid,
            })
    signal_gate = bool(all(row["finite"] and row["time_grid_pass"] for row in rows))
    return {
        "arm": arm,
        "contract_gate": contract_gate,
        "signal_gate": signal_gate,
        "probe_count": len(rows),
        "signals": rows,
    }


def audit(root: Path) -> dict:
    execution = read(root / "cold_chamber_execution.json")
    start = float(execution.get("simscape_log_window_start_s", 0.0))
    stop = float(execution.get("stop_time_s", 0.0))
    provenance_gate = bool(
        execution.get("schema") == "heatdrive_ecc_independent_cold_chamber_v2"
        and execution.get("collection_pass") is True
        and execution.get("c200_state_imported") is False
        and execution.get("checkpoint_saved") is False
        and execution.get("production_recovery_allowed") is False
        and [case.get("arm") for case in execution.get("cases", [])]
        == ["native", "conservative"]
    )
    arms = [audit_arm(root, arm, start, stop) for arm in ("native", "conservative")]
    case_probe_gate = all(
        case.get("stage4_controller_probe_count") == len(EXPECTED)
        and set(case.get("stage4_controller_probe_signal_names", ())) == set(EXPECTED)
        for case in execution.get("cases", [])
    )
    coverage_gate = bool(
        provenance_gate
        and case_probe_gate
        and all(arm["contract_gate"] and arm["signal_gate"] for arm in arms)
    )
    return {
        "schema": "heatdrive_ecc_stage4_controller_probe_audit_v1",
        "diagnostic_only": True,
        "logged_window_start_s": start,
        "logged_window_stop_s": stop,
        "expected_probe_count": len(EXPECTED),
        "provenance_gate": provenance_gate,
        "case_probe_gate": case_probe_gate,
        "arms": arms,
        "coverage_gate": coverage_gate,
        "production_recovery_allowed": False,
        "seed_eligible": False,
        "outer_solve_eligible": False,
        "paired_table4_eligible": False,
        "table4_reproduction_claim": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--experiment-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Do not overwrite diagnostic evidence")
    root = args.experiment_root.resolve()
    result = audit(root)
    result["input_sha256"] = {
        "cold_chamber_execution.json": sha256(root / "cold_chamber_execution.json"),
        "native_observations.mat": sha256(root / "native/observations.mat"),
        "conservative_observations.mat": sha256(root / "conservative/observations.mat"),
        "native_probe_contract": sha256(root / "native/stage4_controller_probe_contract.json"),
        "conservative_probe_contract": sha256(root / "conservative/stage4_controller_probe_contract.json"),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps({
        key: result[key]
        for key in ("provenance_gate", "case_probe_gate", "coverage_gate",
                    "production_recovery_allowed", "seed_eligible")
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
