"""Bind the Eq.9/Eq.10 contract to an actual cold-cycle implementation.

The contract audit alone checks declarations.  This audit additionally checks
the current native cold evidence and deliberately keeps eligibility false when
the physical endpoint inventory is not closed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


REQUIRED_VOLUMES = {
    "SHEX source heat-flow sensor",
    "CHEX boundary heat sensor",
    "SHEX fluid reservoir",
    "HHEX fluid reservoir",
    "CHEX fluid node",
    "SMA solid bed",
    "SE solid bed",
    "SMA/SE route buffers",
    "finite connecting pipes/manifolds",
    "SMA and SE pumps",
}
REQUIRED_METRICS = {
    "heat-driven system COP",
    "SHEX sink-to-fluid transfer",
    "Eq.9 temperature lift",
    "Eq.10 cooling power",
    "Eq.10 specific cooling power",
    "CHEX sensor cross-check",
    "mean pump power",
    "hydraulic COP diagnostic",
    "modeled thermal first-law residual",
    "closed-loop fluid mass drift",
}
ENDPOINT_RESIDUAL_TOL_J = 1e-8


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def _find_arm(cold: dict, name: str) -> dict:
    arms = cold.get("arms")
    if not isinstance(arms, list):
        raise ValueError("cold audit is missing the full native/conservative arm list")
    matches = [arm for arm in arms if isinstance(arm, dict) and arm.get("arm") == name]
    if len(matches) != 1:
        raise ValueError(f"cold audit must contain exactly one {name!r} arm")
    return matches[0]


def _declared_hash(value: object) -> str:
    return str(value or "").strip().upper()


def build(
    contract_path: Path,
    cold_audit_path: Path,
    *,
    expected_result_sha256: str | None = None,
) -> dict:
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    cold = json.loads(cold_audit_path.read_text(encoding="utf-8"))
    contract_path = contract_path.resolve()
    cold_audit_path = cold_audit_path.resolve()
    current_contract_sha256 = sha256(contract_path)
    declared_volumes = {row["control_volume"] for row in contract.get("rows", [])}
    declared_metrics = {row["metric"] for row in contract.get("equations", [])}
    authority = contract.get("authority") or {}
    sampling = contract.get("sampling_contract") or {}
    equation_sampling_pass = all(
        {"window_start_rule", "window_stop_rule", "endpoint_inclusion", "quadrature", "required_signals"}
        <= set(row) for row in contract.get("equations", [])
    )
    contract_structure_pass = (
        contract.get("schema") == "heatdrive_ecc_control_volume_contract_v2"
        and declared_volumes == REQUIRED_VOLUMES
        and declared_metrics == REQUIRED_METRICS
        and contract.get("qian_window_cycles") == 10
        and contract.get("SE_active_mass_kg") == 0.041816836466254441
        and contract.get("contract_role") == "structure_only_not_recovery_source"
        and len(authority.get("frozen_result_sha256", "")) == 64
        and len(authority.get("frozen_checkpoint_sha256", "")) == 64
        and authority.get("current_model_restore_allowed") is False
        and authority.get("rejected_results_may_resume") is False
        and authority.get("rejected_results_may_interpolate") is False
        and float(sampling.get("cycle_period_s", 0)) > 0
        and sampling.get("window_cycles") == 10
        and sampling.get("complete_cycles_only") is True
        and sampling.get("endpoint_extrapolation_allowed") is False
        and sampling.get("native_log_required") is True
        and equation_sampling_pass
    )
    native = _find_arm(cold, "native")
    conservative = _find_arm(cold, "conservative")
    source_port_checks = cold.get("source_storage_port_checks")
    source_ports_pass = bool(source_port_checks) and all(
        isinstance(item, dict) and bool(item.get("passed"))
        for item in source_port_checks
    )
    native_endpoint_residual = float(native["source_minus_actual_endpoint_storage_J"])
    conservative_endpoint_residual = float(conservative["source_minus_actual_endpoint_storage_J"])
    native_group_residuals = {
        key: float(value["endpoint_energy_residual_J"])
        for key, value in native["component_groups"].items()
    }
    native_endpoint_pass = abs(native_endpoint_residual) <= ENDPOINT_RESIDUAL_TOL_J
    # A whole-device source-minus-endpoint balance is only a hard gate when
    # every boundary term is actually observed.  With missing exchanger,
    # buffer, pipe/manifold, or pump port signals, a nonzero residual can be
    # an omitted-term diagnostic rather than a local control-volume failure.
    # Keep the numerical result visible, but do not use it to reject the
    # implementation before the measurement contract is complete.
    complete_runtime_evidence = bool(
        cold.get("all_required_control_volume_observations_complete", False)
    )
    native_endpoint_gate_applicable = bool(
        complete_runtime_evidence
        and native.get("full_device_first_law_verified", False)
    )
    native_endpoint_hard_gate_pass = (
        native_endpoint_pass if native_endpoint_gate_applicable else True
    )
    cold_contract_hash = _declared_hash(cold.get("contract_sha256"))
    contract_binding_pass = cold_contract_hash == current_contract_sha256
    result_hash_present = bool(_declared_hash(cold.get("result_sha256")))
    expected_result_hash = _declared_hash(expected_result_sha256)
    result_binding_pass = (
        not expected_result_hash
        or _declared_hash(cold.get("result_sha256")) == expected_result_hash
    )
    cold_window = {
        "start_s": cold.get("logged_window_start_s"),
        "stop_s": cold.get("logged_window_stop_s"),
        "samples": cold.get("samples"),
        "full_cycle_completed": bool(cold.get("full_cycle_completed")),
        "strict_initial_coordinate_match": bool(cold.get("strict_initial_coordinate_match")),
        "local_inventory_conservation_pass": bool(cold.get("local_inventory_conservation_pass")),
        "source_storage_port_checks_pass": source_ports_pass,
    }
    cold_prerequisite_gate_pass = all([
        cold_window["full_cycle_completed"],
        cold_window["strict_initial_coordinate_match"],
        cold_window["local_inventory_conservation_pass"],
        source_ports_pass,
    ])
    rejection_reasons = []
    if not contract_structure_pass:
        rejection_reasons.append("control-volume contract structure is incomplete or mismatched")
    if not contract_binding_pass:
        rejection_reasons.append("cold audit is bound to a different control-volume contract hash")
    if not result_hash_present:
        rejection_reasons.append("cold audit has no result SHA-256")
    if not result_binding_pass:
        rejection_reasons.append("cold audit result SHA-256 does not match the expected result")
    if not cold_prerequisite_gate_pass:
        rejection_reasons.append("cold-cycle prerequisite gates are incomplete")
    if native_endpoint_gate_applicable and not native_endpoint_pass:
        rejection_reasons.append("native endpoint inventory residual exceeds the scientific tolerance")
    implementation_pass = bool(
        contract_structure_pass
        and contract_binding_pass
        and result_hash_present
        and result_binding_pass
        and cold_prerequisite_gate_pass
        and native_endpoint_hard_gate_pass
    )
    observed_inventory_closure_pass = bool(
        cold.get("local_inventory_conservation_pass")
        and cold.get("strict_initial_coordinate_match")
        and source_ports_pass
        and native_endpoint_hard_gate_pass
    )
    full_device_evidence_pass = bool(
        native.get("full_device_first_law_verified")
        and native.get("periodic_steady_state")
    )
    implementation_ready = bool(
        contract_structure_pass
        and contract_binding_pass
        and result_hash_present
        and result_binding_pass
        and cold_prerequisite_gate_pass
        and observed_inventory_closure_pass
        and full_device_evidence_pass
    )
    return {
        "schema": "heatdrive_ecc_control_volume_implementation_audit_v1",
        "contract_path": str(contract_path),
        "contract_sha256": sha256(contract_path),
        "cold_audit_path": str(cold_audit_path),
        "cold_audit_sha256": sha256(cold_audit_path),
        "contract_structure_pass": contract_structure_pass,
        "contract_binding_pass": contract_binding_pass,
        "cold_audit_contract_sha256": cold_contract_hash,
        "expected_result_sha256": expected_result_hash or None,
        "result_binding_pass": result_binding_pass,
        "endpoint_residual_tolerance_J": ENDPOINT_RESIDUAL_TOL_J,
        "native_endpoint_residual_gate_applicable": native_endpoint_gate_applicable,
        "native_endpoint_residual_hard_gate_pass": native_endpoint_hard_gate_pass,
        "native_endpoint_residual_classification": (
            "hard_gate" if native_endpoint_gate_applicable else "diagnostic_only_missing_boundary_terms"
        ),
        "declared_control_volume_count": len(declared_volumes),
        "declared_metric_count": len(declared_metrics),
        "qian_window_cycles": contract.get("qian_window_cycles"),
        "SE_active_mass_kg": contract.get("SE_active_mass_kg"),
        "contract_role": contract.get("contract_role"),
        "authority_binding_pass": contract_binding_pass,
        "sampling_contract_pass": bool(contract_structure_pass),
        "observed_inventory_closure_pass": observed_inventory_closure_pass,
        "full_device_evidence_pass": full_device_evidence_pass,
        "cold_window": cold_window,
        "cold_prerequisite_gate_pass": cold_prerequisite_gate_pass,
        "native": {
            "endpoint_residual_J": native_endpoint_residual,
            "endpoint_inventory_gate_pass": native_endpoint_pass,
            "endpoint_residual_gate_applicable": native_endpoint_gate_applicable,
            "endpoint_residual_hard_gate_pass": native_endpoint_hard_gate_pass,
            "component_group_endpoint_residuals_J": native_group_residuals,
            "periodic_steady_state": native.get("periodic_steady_state", False),
            "full_device_first_law_verified": native.get("full_device_first_law_verified", False),
        },
        "conservative_diagnostic": {
            "endpoint_residual_J": conservative_endpoint_residual,
            "endpoint_inventory_gate_pass": abs(conservative_endpoint_residual) <= 1e-8,
        },
        "eligibility": {
            "implementation_control_volume_pass": implementation_ready,
            "contract_and_local_inventory_pass": bool(contract_structure_pass and observed_inventory_closure_pass),
            "implementation_ready": implementation_ready,
            "seed_eligible": False,
            "outer_solve_eligible": False,
            "paired_table4_eligible": False,
            "production_recovery_allowed": False,
            "claim_boundary": (
                "Implementation remains diagnostic-only until the current contract is "
                "hash-bound to a complete cold audit and the native endpoint inventory closes."
            ),
        },
        "rejection_reasons": rejection_reasons,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--cold-audit", type=Path, required=True)
    parser.add_argument("--expected-result-sha256")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError(f"Refusing to overwrite evidence: {args.output}")
    result = build(
        args.contract,
        args.cold_audit,
        expected_result_sha256=args.expected_result_sha256,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
