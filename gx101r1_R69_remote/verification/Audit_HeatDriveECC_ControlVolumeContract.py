"""Audit the declared SMA-SE control-volume and Eq.9/Eq.10 contract."""

from __future__ import annotations

import argparse
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

REQUIRED_AUTHORITY_FIELDS = {
    "freeze_contract_relative_path",
    "frozen_result_relative_path",
    "frozen_result_sha256",
    "frozen_checkpoint_relative_path",
    "frozen_checkpoint_sha256",
    "current_model_restore_allowed",
    "rejected_results_may_resume",
    "rejected_results_may_interpolate",
}
REQUIRED_SAMPLING_FIELDS = {
    "cycle_period_s",
    "window_cycles",
    "window_start_rule",
    "window_stop_rule",
    "complete_cycles_only",
    "endpoint_inclusion",
    "endpoint_extrapolation_allowed",
    "quadrature",
    "native_log_required",
}


def find_freeze_contract(contract_path: Path) -> Path | None:
    for parent in (contract_path.parent, *contract_path.parents):
        candidate = parent / "verification" / "c200_mainline_freeze_contract.json"
        if candidate.is_file():
            return candidate
    return None


def validate_authority(contract: dict, contract_path: Path) -> dict:
    authority = contract.get("authority") or {}
    freeze_path = find_freeze_contract(contract_path)
    freeze = None
    if freeze_path:
        freeze = json.loads(freeze_path.read_text(encoding="utf-8"))
    fields_pass = REQUIRED_AUTHORITY_FIELDS <= set(authority)
    hash_pass = all(
        isinstance(authority.get(key), str) and len(authority[key]) == 64
        and all(char in "0123456789ABCDEFabcdef" for char in authority[key])
        for key in ("frozen_result_sha256", "frozen_checkpoint_sha256")
    )
    freeze_match = bool(
        freeze
        and authority.get("frozen_result_sha256") == freeze.get("result_sha256")
        and authority.get("frozen_checkpoint_sha256") == freeze.get("checkpoint_sha256")
        and authority.get("current_model_restore_allowed") is False
        and authority.get("rejected_results_may_resume") is False
        and authority.get("rejected_results_may_interpolate") is False
    )
    return {
        "authority_fields_pass": fields_pass,
        "authority_hash_format_pass": hash_pass,
        "freeze_contract_found": freeze_path is not None,
        "freeze_binding_pass": freeze_match,
        "freeze_contract_path": None if freeze_path is None else str(freeze_path),
    }


def validate_sampling(contract: dict) -> dict:
    sampling = contract.get("sampling_contract") or {}
    equations = contract.get("equations") or []
    equation_fields = all(
        {"window_start_rule", "window_stop_rule", "endpoint_inclusion", "quadrature", "required_signals"}
        <= set(row) for row in equations
    )
    values_pass = (
        REQUIRED_SAMPLING_FIELDS <= set(sampling)
        and float(sampling.get("cycle_period_s", 0)) > 0
        and int(sampling.get("window_cycles", 0)) == 10
        and sampling.get("complete_cycles_only") is True
        and sampling.get("endpoint_extrapolation_allowed") is False
        and sampling.get("native_log_required") is True
        and "trapz" in str(sampling.get("quadrature", "")).lower()
    )
    return {
        "sampling_fields_pass": REQUIRED_SAMPLING_FIELDS <= set(sampling),
        "sampling_values_pass": values_pass,
        "equation_sampling_fields_pass": equation_fields,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("contract", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--shex-smoke", type=Path)
    args = parser.parse_args()
    contract = json.loads(args.contract.read_text(encoding="utf-8"))
    rows = {row["control_volume"] for row in contract.get("rows", [])}
    metrics = {row["metric"] for row in contract.get("equations", [])}
    missing_rows = sorted(REQUIRED_VOLUMES - rows)
    missing_metrics = sorted(REQUIRED_METRICS - metrics)
    smoke = None
    if args.shex_smoke:
        smoke = json.loads(args.shex_smoke.read_text(encoding="utf-8"))
    authority = validate_authority(contract, args.contract)
    sampling = validate_sampling(contract)
    structure_pass = (
        contract.get("schema") == "heatdrive_ecc_control_volume_contract_v2"
        and not missing_rows
        and not missing_metrics
        and contract.get("qian_window_cycles") == 10
        and contract.get("SE_active_mass_kg") == 0.041816836466254441
    )
    result = {
        "schema": "heatdrive_ecc_control_volume_contract_audit_v1",
        "source": str(args.contract),
        "contract_schema": contract.get("schema"),
        "control_volume_count": len(rows),
        "metric_count": len(metrics),
        "required_control_volume_count": len(REQUIRED_VOLUMES),
        "required_metric_count": len(REQUIRED_METRICS),
        "missing_control_volumes": missing_rows,
        "missing_metrics": missing_metrics,
        "se_active_mass_kg": contract.get("SE_active_mass_kg"),
        "contract_role": contract.get("contract_role"),
        "contract_structure_pass": structure_pass,
        "authority": authority,
        "sampling": sampling,
        "qian_window_cycles": contract.get("qian_window_cycles"),
        "shex_topology_update_pass": (
            None if smoke is None else bool(smoke.get("topology_update_pass"))
        ),
        "audit_pass": (
            structure_pass
            and contract.get("contract_role") == "structure_only_not_recovery_source"
            and authority["authority_fields_pass"]
            and authority["authority_hash_format_pass"]
            and authority["freeze_binding_pass"]
            and sampling["sampling_fields_pass"]
            and sampling["sampling_values_pass"]
            and sampling["equation_sampling_fields_pass"]
            and (smoke is None or bool(smoke.get("topology_update_pass")))
        ),
        "claim_boundary": "Contract structure only; no physical periodic or experimental validation claim.",
    }
    payload = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload, encoding="utf-8")
    print(payload, end="")
    return 0 if result["audit_pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
