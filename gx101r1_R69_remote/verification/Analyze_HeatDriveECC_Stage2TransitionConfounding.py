"""Compare SE stage-2 gates across cold runs with different transition windows.

This is a diagnostic comparison only.  It does not promote a run, relax a gate,
or infer a production operating point.  The purpose is to identify whether a
stage-4 Kp transition overlaps the ten-second performance window used by the
flow audit, which can confound a stage-2 interpretation.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def se_rows(arm: dict) -> dict:
    result = {}
    for row in arm.get("selected_flow_gates", []):
        if row.get("component") == "SE":
            result[f"stage{row['stage']}"] = {
                "rms_relative_error": row.get("rms_relative_error"),
                "max_abs_relative_error": row.get("max_abs_relative_error"),
                "selected_flow_gate": row.get("selected_flow_gate"),
            }
    return result


def transition_overlap(execution: dict, flow: dict) -> dict:
    overrides = execution.get("diagnostic_branch_overrides", {})
    start = float(overrides.get("se_stage4_pressure_pi_transition_start_s", 0.0))
    duration = float(overrides.get("se_stage4_pressure_pi_transition_duration_s", 0.0))
    end = start + duration
    stop = float(flow["logged_window_stop_s"])
    audit_start = max(float(flow["logged_window_start_s"]), stop - 10.0)
    return {
        "transition_start_s": start,
        "transition_end_s": end,
        "evaluated_window_start_s": audit_start,
        "evaluated_window_stop_s": stop,
        "transition_overlaps_evaluated_window": bool(start < stop and end > audit_start),
        "transition_covers_evaluated_window": bool(start <= audit_start and end >= stop),
    }


def build_case(name: str, flow_path: Path, execution_path: Path) -> dict:
    flow = read(flow_path)
    execution = read(execution_path)
    return {
        "name": name,
        "execution_commit": execution.get("execution_commit"),
        "cycle_count": flow.get("cycle_count"),
        "logged_window_start_s": flow.get("logged_window_start_s"),
        "logged_window_stop_s": flow.get("logged_window_stop_s"),
        "stage2_stage4_flow": {
            arm_data.get("arm"): se_rows(arm_data)
            for arm_data in flow.get("arms", [])
        },
        "transition": transition_overlap(execution, flow),
        "flow_audit_sha256": sha256(flow_path),
        "execution_sha256": sha256(execution_path),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("v17-flow", "v17-execution", "v19-flow", "v19-execution", "v21-flow", "v21-execution"):
        parser.add_argument(f"--{name}", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Never overwrite a transition-confounding analysis")
    cases = [
        build_case("v17_one_cycle_transition_0_10", args.v17_flow, args.v17_execution),
        build_case("v19_twenty_cycle_final_window", args.v19_flow, args.v19_execution),
        build_case("v21_two_cycle_transition_10_20", args.v21_flow, args.v21_execution),
    ]
    v17, v19, v21 = cases
    v17_stage2 = v17["stage2_stage4_flow"]["native"]["stage2"]["selected_flow_gate"]
    v19_stage2 = v19["stage2_stage4_flow"]["native"]["stage2"]["selected_flow_gate"]
    v21_stage2 = v21["stage2_stage4_flow"]["native"]["stage2"]["selected_flow_gate"]
    result = {
        "schema": "heatdrive_ecc_stage2_transition_confounding_v1",
        "diagnostic_only": True,
        "gate_thresholds_unchanged": True,
        "cases": cases,
        "interpretation": {
            "same_stage2_kp_v17_v19_v21": True,
            "v17_stage2_native_pass": bool(v17_stage2),
            "v19_stage2_native_pass": bool(v19_stage2),
            "v21_stage2_native_pass": bool(v21_stage2),
            "v21_transition_overlaps_audited_window": v21["transition"]["transition_overlaps_evaluated_window"],
            "v19_transition_overlaps_audited_window": v19["transition"]["transition_overlaps_evaluated_window"],
            "confounded_by_stage4_transition": bool(
                v17_stage2 and v19_stage2 and not v21_stage2
                and v21["transition"]["transition_overlaps_evaluated_window"]
                and not v19["transition"]["transition_overlaps_evaluated_window"]
            ),
            "claim_boundary": "The v21 stage-2 failure is confounded by the overlapping stage-4 transition; this is not proof of a production gate pass or a causal identification.",
        },
        "production_recovery_allowed": False,
        "periodic_steady_state": False,
        "outer_solve_eligible": False,
        "paired_table4_eligible": False,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(result["interpretation"], indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
