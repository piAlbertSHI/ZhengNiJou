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


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def build(contract_path: Path, cold_audit_path: Path) -> dict:
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    cold = json.loads(cold_audit_path.read_text(encoding="utf-8"))
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
    native = next(arm for arm in cold["arms"] if arm["arm"] == "native")
    conservative = next(arm for arm in cold["arms"] if arm["arm"] == "conservative")
    source_ports_pass = all(item["passed"] for item in cold["source_storage_port_checks"])
    native_endpoint_residual = float(native["source_minus_actual_endpoint_storage_J"])
    conservative_endpoint_residual = float(conservative["source_minus_actual_endpoint_storage_J"])
    native_group_residuals = {
        key: float(value["endpoint_energy_residual_J"])
        for key, value in native["component_groups"].items()
    }
    native_endpoint_pass = abs(native_endpoint_residual) <= 1e-8
    observed_inventory_closure_pass = bool(
        cold.get("local_inventory_conservation_pass")
        and cold.get("strict_initial_coordinate_match")
        and source_ports_pass
        and native_endpoint_pass
    )
    full_device_evidence_pass = bool(
        native.get("full_device_first_law_verified")
        and native.get("periodic_steady_state")
    )
    implementation_ready = bool(
        contract_structure_pass
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
        "declared_control_volume_count": len(declared_volumes),
        "declared_metric_count": len(declared_metrics),
        "qian_window_cycles": contract.get("qian_window_cycles"),
        "SE_active_mass_kg": contract.get("SE_active_mass_kg"),
        "contract_role": contract.get("contract_role"),
        "authority_binding_pass": bool(contract_structure_pass),
        "sampling_contract_pass": bool(contract_structure_pass),
        "observed_inventory_closure_pass": observed_inventory_closure_pass,
        "full_device_evidence_pass": full_device_evidence_pass,
        "cold_window": {
            "start_s": cold.get("logged_window_start_s"),
            "stop_s": cold.get("logged_window_stop_s"),
            "samples": cold.get("samples"),
            "full_cycle_completed": cold.get("full_cycle_completed"),
            "strict_initial_coordinate_match": cold.get("strict_initial_coordinate_match"),
            "local_inventory_conservation_pass": cold.get("local_inventory_conservation_pass"),
            "source_storage_port_checks_pass": source_ports_pass,
        },
        "native": {
            "endpoint_residual_J": native_endpoint_residual,
            "endpoint_inventory_gate_pass": native_endpoint_pass,
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
            "claim_boundary": "Contract structure is complete, but the current native cold implementation is not physically closed.",
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--cold-audit", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError(f"Refusing to overwrite evidence: {args.output}")
    result = build(args.contract, args.cold_audit)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
