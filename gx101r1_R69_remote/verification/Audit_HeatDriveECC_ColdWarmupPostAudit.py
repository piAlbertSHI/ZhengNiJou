"""Evaluate a completed diagnostic warm-up without granting production status.

This is intentionally separate from the one-cycle warm-up eligibility audit.
It consumes the final-cycle audits of a multi-cycle run and reports exactly
which strict contracts remain incomplete.  It never grants recovery,
checkpointing, outer solves, sensitivity, paired endpoints, or Table 4 status.
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


def all_arm_checks(document: dict, keys: tuple[str, ...]) -> bool:
    arms = document.get("arms", [])
    return bool(len(arms) == 2 and all(all(arm.get(key) is True for key in keys)
                                       for arm in arms))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--execution", type=Path, required=True)
    parser.add_argument("--flow-audit", type=Path, required=True)
    parser.add_argument("--pressure-audit", type=Path, required=True)
    parser.add_argument("--probe-audit", type=Path, required=True)
    parser.add_argument("--causal-audit", type=Path, required=True)
    parser.add_argument("--dynamics-audit", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Never overwrite warm-up post-audit evidence")

    execution = read(args.execution)
    flow = read(args.flow_audit)
    pressure = read(args.pressure_audit)
    probes = read(args.probe_audit)
    causal = read(args.causal_audit)
    dynamics = read(args.dynamics_audit)
    cycle_count = int(execution.get("cycle_count", 0))
    execution_contract_pass = bool(
        execution.get("schema") == "heatdrive_ecc_independent_cold_chamber_v2"
        and execution.get("collection_pass") is True
        and execution.get("start_time_s") == 0
        and execution.get("stop_time_s") == cycle_count * 10
        and cycle_count >= 2
        and execution.get("c200_state_imported") is False
        and execution.get("checkpoint_saved") is False
        and execution.get("production_recovery_allowed") is False
        and [case.get("arm") for case in execution.get("cases", [])]
        == ["native", "conservative"]
    )
    flow_gate_pass = bool(
        flow.get("schema") == "heatdrive_ecc_cold_buffer_coupled_audit_v2"
        and flow.get("evidence_audit_pass") is True
        and flow.get("full_cycle_completed") is True
        and flow.get("cycle_count") == cycle_count
        and all(all(gate.get("selected_flow_gate") is True
                    for gate in arm.get("selected_flow_gates", []))
                for arm in flow.get("arms", []))
    )
    pressure_gate_pass = bool(
        pressure.get("schema") == "heatdrive_ecc_cold_pump_pressure_probe_audit_v1"
        and pressure.get("pressure_range_gate") is True
        and pressure.get("hydraulic_diagnostic_gate") is True
        and all_arm_checks(pressure, ("probe_contract_gate", "probe_signal_gate",
                                      "pressure_range_gate", "hydraulic_diagnostic_gate"))
    )
    probe_gate_pass = bool(
        probes.get("schema") == "heatdrive_ecc_stage4_controller_probe_audit_v1"
        and probes.get("provenance_gate") is True
        and probes.get("case_probe_gate") is True
        and probes.get("coverage_gate") is True
        and all(arm.get("contract_gate") is True and arm.get("signal_gate") is True
                and arm.get("probe_count") == probes.get("expected_probe_count") == 17
                for arm in probes.get("arms", []))
    )
    cycle_index = cycle_count - 1
    causal_cycle_pass = bool(
        causal.get("experiments")
        and all(experiment.get("cycle_count") == cycle_count
                and experiment.get("analysis_cycle_index") == cycle_index
                for experiment in causal["experiments"])
    )
    dynamics_cycle_pass = bool(
        dynamics.get("experiments")
        and all(experiment.get("cycle_count") == cycle_count
                and experiment.get("analysis_cycle_index") == cycle_index
                for experiment in dynamics["experiments"])
    )
    periodic = bool(flow.get("periodic_steady_state") is True)
    first_law = bool(flow.get("full_device_first_law_verified") is True)
    failed_flow_gates = [
        {"arm": arm.get("arm"), **gate}
        for arm in flow.get("arms", [])
        for gate in arm.get("selected_flow_gates", [])
        if gate.get("selected_flow_gate") is not True
    ]
    strict_post_warmup_pass = bool(
        execution_contract_pass and flow_gate_pass and pressure_gate_pass
        and probe_gate_pass and causal_cycle_pass and dynamics_cycle_pass
        and periodic and first_law
    )
    result = {
        "schema": "heatdrive_ecc_cold_warmup_post_audit_v1",
        "diagnostic_only": True,
        "cycle_count": cycle_count,
        "analysis_cycle_index": cycle_index,
        "execution_contract_pass": execution_contract_pass,
        "flow_gate_pass": flow_gate_pass,
        "pressure_gate_pass": pressure_gate_pass,
        "stage4_probe_gate_pass": probe_gate_pass,
        "causal_final_cycle_contract_pass": causal_cycle_pass,
        "dynamics_final_cycle_contract_pass": dynamics_cycle_pass,
        "periodic_steady_state": periodic,
        "full_device_first_law_verified": first_law,
        "strict_post_warmup_pass": strict_post_warmup_pass,
        "production_recovery_allowed": False,
        "checkpoint_saved": False,
        "seed_eligible": False,
        "outer_solve_eligible": False,
        "paired_table4_eligible": False,
        "table4_reproduction_claim": False,
        "failed_flow_gates": failed_flow_gates,
        "input_sha256": {name: sha256(path) for name, path in {
            "execution": args.execution,
            "flow_audit": args.flow_audit,
            "pressure_audit": args.pressure_audit,
            "probe_audit": args.probe_audit,
            "causal_audit": args.causal_audit,
            "dynamics_audit": args.dynamics_audit,
        }.items()},
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n",
                           encoding="utf-8")
    print(json.dumps({
        "strict_post_warmup_pass": strict_post_warmup_pass,
        "periodic_steady_state": periodic,
        "production_recovery_allowed": False,
        "failed_flow_gates": len(failed_flow_gates),
    }, indent=2))
    return 0 if strict_post_warmup_pass else 1


if __name__ == "__main__":
    raise SystemExit(main())
