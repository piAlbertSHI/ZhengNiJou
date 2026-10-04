"""Classify evidence, physical-seed, and paper-claim gates without conflation.

This audit is deliberately non-authorizing.  It reads existing JSON evidence,
reports the highest-level blocker, and never promotes a result to a recovery
source, 20-cycle seed, outer solve, or Table 4 claim.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _arm(audit: dict, name: str) -> dict:
    matches = [row for row in audit.get("arms", []) if row.get("arm") == name]
    if len(matches) != 1:
        raise ValueError(f"expected exactly one {name} arm")
    return matches[0]


def build(c200: dict, flow: dict, pressure: dict, state: dict) -> dict:
    flow_native = _arm(flow, "native")
    pressure_native = _arm(pressure, "native")
    flow_gates = {
        f"{row['component']}_stage{row['stage']}": bool(row["selected_flow_gate"])
        for row in flow_native.get("selected_flow_gates", [])
    }
    evidence_complete = bool(c200.get("all_required_control_volume_observations_complete", False))
    endpoint_applicable = bool(
        evidence_complete and flow_native.get("full_device_first_law_verified", False)
    )
    mechanism_pass = all(flow_gates.values()) and bool(
        pressure.get("pressure_range_gate") and pressure.get("hydraulic_diagnostic_gate")
    )
    blockers: list[str] = []
    if not evidence_complete:
        blockers.append("runtime control-volume evidence incomplete")
    if not all(flow_gates.values()):
        blockers.append("finite diagnostic SE flow gate failed")
    if not pressure.get("pressure_range_gate") or not pressure.get("hydraulic_diagnostic_gate"):
        blockers.append("pressure or hydraulic diagnostic gate failed")
    if not bool(state.get("contract_completeness_pass")):
        blockers.append("shared-state contract evidence incomplete")
    if not blockers:
        blockers.append("no diagnostic blocker recorded; paper claim still requires separate endpoint gates")
    periodic_conflict = bool(
        (c200.get("periodic_steady_state_evidence") or {}).get(
            "conflict_detected", c200.get("conflict_detected", False)
        )
    )
    return {
        "schema": "heatdrive_ecc_gate_semantics_audit_v1",
        "source_sha256": {
            "c200_control_volume_evidence": c200["_source_sha256"],
            "finite_flow": flow["_source_sha256"],
            "finite_pressure": pressure["_source_sha256"],
            "finite_state_contract": state["_source_sha256"],
        },
        "policy": {
            "evidence_completeness_is_hard_for_outer_solve": True,
            "local_inventory_and_flow_are_hard_for_seed": True,
            "whole_device_endpoint_residual_is_diagnostic_until_boundary_complete": True,
            "periodic_or_near_steady_is_required_before_paper_claim": True,
            "this_audit_grants_no_authority": True,
        },
        "evidence_layer": {
            "contract_structure_complete": bool(c200.get("contract_structure_complete", True)),
            "runtime_observations_complete": evidence_complete,
            "periodic_flag_conflict": periodic_conflict,
            "outer_solve_eligible": False,
        },
        "physical_seed_layer": {
            "flow_gates": flow_gates,
            "pressure_range_gate": bool(pressure.get("pressure_range_gate")),
            "hydraulic_diagnostic_gate": bool(pressure.get("hydraulic_diagnostic_gate")),
            "mechanism_pass_for_finite_diagnostic": mechanism_pass,
            "seed_eligible": False,
            "production_recovery_allowed": False,
        },
        "endpoint_residual_layer": {
            "native_residual_J": flow_native.get("source_minus_actual_endpoint_storage_J"),
            "hard_gate_applicable": endpoint_applicable,
            "classification": "hard_gate" if endpoint_applicable else "diagnostic_only_missing_boundary_terms",
        },
        "claim_layer": {
            "periodic_steady_state": bool(flow.get("periodic_steady_state", False)),
            "strict_table4_reproduction": bool(flow.get("table4_reproduction_claim", False)),
            "table4_claim_allowed": False,
        },
        "highest_level_blockers": blockers,
        "decision": "diagnose_architecture_or_runtime_contract_before_new_20cycle",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--c200", type=Path, required=True)
    parser.add_argument("--flow", type=Path, required=True)
    parser.add_argument("--pressure", type=Path, required=True)
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    paths = [args.c200, args.flow, args.pressure, args.state]
    docs = [load(path) for path in paths]
    for doc, path in zip(docs, paths):
        doc["_source_sha256"] = sha256(path)
    result = build(*docs)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.output.exists():
        raise FileExistsError(f"refusing to overwrite {args.output}")
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
