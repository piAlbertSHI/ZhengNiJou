"""Decide whether a failed one-cycle cold run may continue as warm-up only.

This is intentionally weaker than the production 10 s seed gate and is a
separate contract. It can authorize only a fresh diagnostic continuation that
must be re-audited after warm-up. It never authorizes recovery, interpolation,
outer solves, sensitivity, paired endpoints, or Table 4 claims.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from Audit_HeatDriveECC_SegmentedEvidence import sha256


def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def execution_contract_passes(execution: dict) -> bool:
    return bool(
        execution.get("schema") == "heatdrive_ecc_independent_cold_chamber_v2"
        and execution.get("collection_pass") is True
        and execution.get("start_time_s") == 0
        and execution.get("stop_time_s") == 10
        and execution.get("cycle_count") == 1
        and execution.get("c200_state_imported") is False
        and execution.get("checkpoint_saved") is False
        and execution.get("production_recovery_allowed") is False
        and [case.get("arm") for case in execution.get("cases", [])]
        == ["native", "conservative"]
    )


def safe_flow_failures(flow: dict, causal: dict) -> tuple[bool, list[dict]]:
    failures = []
    for arm in flow.get("arms", []):
        for gate in arm.get("selected_flow_gates", []):
            if not gate.get("selected_flow_gate"):
                failures.append({"arm": arm.get("arm"), **gate})
    if not failures:
        return False, failures
    if any(
        row.get("component") != "SE"
        or int(row.get("stage", -1)) != 4
        or float(row.get("mean_signed_kg_s", 0.0)) <= 0.0
        or float(row.get("max_abs_relative_error", 1.0)) > 0.15
        for row in failures
    ):
        return False, failures
    causal_rows = [
        arm
        for experiment in causal.get("experiments", [])
        for arm in experiment.get("arms", [])
    ]
    if not causal_rows or any(
        row.get("flow_shape", {}).get("reverse_flow_fraction") != 0.0
        for row in causal_rows
    ):
        return False, failures
    return True, failures


def pressure_and_probe_pass(pressure: dict, probes: dict) -> bool:
    pressure_arms = pressure.get("arms", [])
    probe_arms = probes.get("arms", [])
    return bool(
        pressure.get("schema") == "heatdrive_ecc_cold_pump_pressure_probe_audit_v1"
        and pressure.get("pressure_range_gate") is True
        and pressure.get("hydraulic_diagnostic_gate") is True
        and pressure.get("production_recovery_allowed") is False
        and len(pressure_arms) == 2
        and all(
            arm.get("probe_contract_gate") is True
            and arm.get("probe_signal_gate") is True
            and arm.get("pressure_range_gate") is True
            and arm.get("hydraulic_diagnostic_gate") is True
            for arm in pressure_arms
        )
        and probes.get("schema") == "heatdrive_ecc_stage4_controller_probe_audit_v1"
        and probes.get("provenance_gate") is True
        and probes.get("case_probe_gate") is True
        and len(probe_arms) == 2
        and all(
            arm.get("contract_gate") is True
            and arm.get("signal_gate") is True
            and arm.get("probe_count") == probes.get("expected_probe_count") == 17
            for arm in probe_arms
        )
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flow-audit", type=Path, required=True)
    parser.add_argument("--pressure-audit", type=Path, required=True)
    parser.add_argument("--probe-audit", type=Path, required=True)
    parser.add_argument("--causal-audit", type=Path, required=True)
    parser.add_argument("--execution", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Never overwrite a cold warm-up decision")
    flow, pressure, probes, causal, execution = map(
        read,
        (args.flow_audit, args.pressure_audit, args.probe_audit,
         args.causal_audit, args.execution),
    )
    execution_ok = execution_contract_passes(execution)
    flow_base_ok = bool(
        flow.get("schema") == "heatdrive_ecc_cold_buffer_coupled_audit_v2"
        and flow.get("evidence_audit_pass") is True
        and flow.get("trajectory_compiled_inventory_gate") is True
        and flow.get("local_inventory_conservation_pass") is True
        and flow.get("strict_initial_coordinate_match") is True
        and flow.get("production_recovery_allowed") is False
        and len(flow.get("arms", [])) == 2
        and all(check.get("passed") for check in flow.get("source_storage_port_checks", []))
    )
    allowed_flow_failure, failures = safe_flow_failures(flow, causal)
    pressure_ok = pressure_and_probe_pass(pressure, probes)
    eligible = bool(execution_ok and flow_base_ok and allowed_flow_failure and pressure_ok)
    reasons = []
    if not execution_ok:
        reasons.append("execution is outside the independent one-cycle cold contract")
    if not flow_base_ok:
        reasons.append("inventory, endpoint, coordinate, or source-port base gate failed")
    if not allowed_flow_failure:
        reasons.append("flow failures are not limited to bounded positive SE Stage4 warm-up bias")
    if not pressure_ok:
        reasons.append("pressure, hydraulic, or probe contract failed")
    result = {
        "schema": "heatdrive_ecc_cold_warmup_eligibility_v1",
        "diagnostic_only": True,
        "execution_contract_pass": execution_ok,
        "flow_base_contract_pass": flow_base_ok,
        "allowed_warmup_flow_failure": allowed_flow_failure,
        "pressure_and_probe_contract_pass": pressure_ok,
        "failed_flow_gates": failures,
        "warmup_only_20cycle_eligible": eligible,
        "requires_post_warmup_reaudit": True,
        "production_recovery_allowed": False,
        "checkpoint_saved": False,
        "seed_eligible": False,
        "outer_solve_eligible": False,
        "paired_table4_eligible": False,
        "table4_reproduction_claim": False,
        "rejection_reasons": reasons,
        "input_sha256": {
            "flow_audit": sha256(args.flow_audit),
            "pressure_audit": sha256(args.pressure_audit),
            "probe_audit": sha256(args.probe_audit),
            "causal_audit": sha256(args.causal_audit),
            "execution": sha256(args.execution),
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "warmup_only_20cycle_eligible": eligible,
        "requires_post_warmup_reaudit": True,
        "production_recovery_allowed": False,
        "seed_eligible": False,
    }, indent=2))
    return 0 if eligible else 1


if __name__ == "__main__":
    raise SystemExit(main())
