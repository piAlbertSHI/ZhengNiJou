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
        "qian_window_cycles": contract.get("qian_window_cycles"),
        "shex_topology_update_pass": (
            None if smoke is None else bool(smoke.get("topology_update_pass"))
        ),
        "audit_pass": (
            contract.get("schema") == "heatdrive_ecc_control_volume_contract_v2"
            and not missing_rows
            and not missing_metrics
            and contract.get("qian_window_cycles") == 10
            and contract.get("SE_active_mass_kg") == 0.041816836466254441
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
