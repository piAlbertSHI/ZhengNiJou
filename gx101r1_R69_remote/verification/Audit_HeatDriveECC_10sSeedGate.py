"""Combine the independent 10 s cold gates before authorizing a 20-cycle run.

This gate authorizes only a fresh cold 20-cycle diagnostic.  It never grants
Operating-Point recovery, interpolation, outer-solve eligibility, periodic
steady state, or a Table 4 claim.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from Audit_HeatDriveECC_SegmentedEvidence import sha256


def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def phase_gate(flow: dict) -> tuple[bool, list[dict]]:
    rows = []
    for arm in flow.get("arms", []):
        for material, balance in arm.get("selected_solid_balances", {}).items():
            passed = bool(
                0.0 <= balance.get("all_node_phase_min", float("nan")) <= 1.0
                and 0.0 <= balance.get("all_node_phase_max", float("nan")) <= 1.0
                and balance.get("selected_solid_energy_gate") is True
            )
            rows.append({
                "arm": arm.get("arm"),
                "material": material,
                "all_node_phase_min": balance.get("all_node_phase_min"),
                "all_node_phase_max": balance.get("all_node_phase_max"),
                "selected_solid_energy_gate": balance.get("selected_solid_energy_gate"),
                "phase_bounds_and_solid_gate_pass": passed,
            })
    return bool(rows) and all(row["phase_bounds_and_solid_gate_pass"] for row in rows), rows


def flow_gate(flow: dict) -> bool:
    return bool(
        flow.get("schema") == "heatdrive_ecc_cold_buffer_coupled_audit_v2"
        and flow.get("evidence_audit_pass") is True
        and flow.get("declared_window_numerical_gates_pass") is True
        and flow.get("trajectory_compiled_inventory_gate") is True
        and flow.get("local_inventory_conservation_pass") is True
        and flow.get("strict_initial_coordinate_match") is True
        and flow.get("production_recovery_allowed") is False
        and len(flow.get("arms", [])) == 2
        and all(check.get("passed") for check in flow.get("source_storage_port_checks", []))
        and all(
            item.get("selected_flow_gate") is True
            for arm in flow.get("arms", [])
            for item in arm.get("selected_flow_gates", [])
        )
    )


def pressure_gate(pressure: dict) -> bool:
    return bool(
        pressure.get("schema") == "heatdrive_ecc_cold_pump_pressure_probe_audit_v1"
        and pressure.get("provenance_gate") is True
        and pressure.get("pressure_range_gate") is True
        and pressure.get("hydraulic_diagnostic_gate") is True
        and pressure.get("production_recovery_allowed") is False
        and pressure.get("table4_reproduction_claim") is False
        and [arm.get("arm") for arm in pressure.get("arms", [])] == ["native", "conservative"]
        and all(
            arm.get("probe_contract_gate") is True
            and arm.get("probe_signal_gate") is True
            and arm.get("pressure_range_gate") is True
            and arm.get("hydraulic_diagnostic_gate") is True
            for arm in pressure.get("arms", [])
        )
    )


def classify(flow: dict, pressure: dict, execution: dict) -> dict:
    if (
        execution.get("schema") != "heatdrive_ecc_independent_cold_chamber_v2"
        or execution.get("collection_pass") is not True
        or execution.get("start_time_s") != 0
        or execution.get("stop_time_s") != 10
        or execution.get("cycle_count") != 1
        or execution.get("c200_state_imported") is not False
        or execution.get("checkpoint_saved") is not False
        or execution.get("production_recovery_allowed") is not False
        or [case.get("arm") for case in execution.get("cases", [])] != ["native", "conservative"]
    ):
        raise ValueError("Execution is outside the independent 10 s cold seed contract")
    flow_ok = flow_gate(flow)
    pressure_ok = pressure_gate(pressure)
    phase_ok, phase_rows = phase_gate(flow)
    eligible = bool(flow_ok and pressure_ok and phase_ok)
    reasons = []
    if not flow_ok:
        reasons.append("10 s flow/inventory/initial-coordinate gate failed")
    if not phase_ok:
        reasons.append("phase bounds or solid energy gate failed")
    if not pressure_ok:
        reasons.append("independent pressure/probe/hydraulic gate failed")
    return {
        "schema": "heatdrive_ecc_10s_seed_gate_v1",
        "diagnostic_only": True,
        "flow_and_inventory_gate": flow_ok,
        "phase_bounds_and_solid_energy_gate": phase_ok,
        "pressure_and_hydraulic_gate": pressure_ok,
        "phase_rows": phase_rows,
        "full_cycle_completed": True,
        "periodic_steady_state": False,
        "mechanism_gates_complete": False,
        "diagnostic_20cycle_seed_eligible": eligible,
        "production_recovery_allowed": False,
        "outer_solve_eligible": False,
        "paired_table4_eligible": False,
        "table4_reproduction_claim": False,
        "rejection_reasons": reasons,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flow-audit", type=Path, required=True)
    parser.add_argument("--pressure-audit", type=Path, required=True)
    parser.add_argument("--execution", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Never overwrite a seed-gate decision")
    flow, pressure, execution = map(read, (args.flow_audit, args.pressure_audit, args.execution))
    result = classify(flow, pressure, execution)
    result["input_sha256"] = {
        "flow_audit": sha256(args.flow_audit),
        "pressure_audit": sha256(args.pressure_audit),
        "execution": sha256(args.execution),
        "native_observations": execution["cases"][0]["observation_sha256"],
        "conservative_observations": execution["cases"][1]["observation_sha256"],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({key: result[key] for key in (
        "flow_and_inventory_gate", "phase_bounds_and_solid_energy_gate",
        "pressure_and_hydraulic_gate", "diagnostic_20cycle_seed_eligible",
        "production_recovery_allowed", "outer_solve_eligible",
        "paired_table4_eligible")}, indent=2))
    return 0 if result["diagnostic_20cycle_seed_eligible"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
