"""Summarize native endpoint-vs-differential residual attribution.

This is an evidence-only audit. It never edits raw observations, changes a
gate, or produces a recovery/seed qualification.
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


def selected(row: dict) -> dict:
    fields = (
        "block_path",
        "mask_type",
        "BE_coefficient_energy_residual_J_end",
        "endpoint_energy_residual_J_end",
        "BE_coefficient_mass_residual_kg_end",
        "endpoint_mass_residual_kg_end",
        "energy_endpoint_change_J",
        "pressure_volume_work_J",
        "energy_flow_integral_J",
        "energy_equation_accumulation_J",
        "energy_enthalpy_endpoint_change_J",
        "mass_flow_integral_kg",
        "mass_equation_accumulation_kg",
        "mass_endpoint_change_kg",
    )
    return {field: row.get(field) for field in fields}


def build(audit_path: Path) -> dict:
    audit = json.loads(audit_path.read_text(encoding="utf-8"))
    arms = {arm["arm"]: arm for arm in audit["arms"]}
    native = arms["native"]
    rows = [
        selected(row)
        for row in native["components"]
        if row["mask_type"] in {"Constant Volume Chamber (TL)", "Tank (TL)"}
    ]
    groups = native["component_groups"]
    chamber_rows = [
        row for row in rows if row["mask_type"] == "Constant Volume Chamber (TL)"
    ]
    coefficient_residual = max(
        abs(float(row["BE_coefficient_energy_residual_J_end"]))
        for row in chamber_rows
    )
    endpoint_residual = sum(float(row["endpoint_energy_residual_J_end"]) for row in chamber_rows)
    tank_residual = sum(
        float(row["endpoint_energy_residual_J_end"])
        for row in rows
        if row["mask_type"] == "Tank (TL)"
    )
    return {
        "schema": "heatdrive_ecc_native_endpoint_residual_attribution_v1",
        "source_audit": str(audit_path),
        "source_audit_sha256": sha256(audit_path),
        "scope": "v8 one-cycle native/conservative cold diagnostic; evidence only",
        "native_component_groups": groups,
        "native_selected_components": rows,
        "native_chamber_max_abs_coefficient_energy_residual_J": coefficient_residual,
        "native_chamber_endpoint_energy_residual_J": endpoint_residual,
        "native_tank_endpoint_energy_residual_J": tank_residual,
        "interpretation": {
            "differential_coefficient_ledger_closes": coefficient_residual <= 1e-8,
            "endpoint_inventory_gate_passes": abs(endpoint_residual + tank_residual) <= 1e-8,
            "endpoint_gate_must_not_be_relaxed": True,
            "seed_eligible": False,
            "production_recovery_allowed": False,
            "next_action": "reconcile native property/state endpoint semantics before any 20-cycle run",
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audit", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError(f"Refusing to overwrite evidence: {args.output}")
    result = build(args.audit)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({
        "source_audit_sha256": result["source_audit_sha256"],
        "native_chamber_max_abs_coefficient_energy_residual_J": result[
            "native_chamber_max_abs_coefficient_energy_residual_J"
        ],
        "native_chamber_endpoint_energy_residual_J": result[
            "native_chamber_endpoint_energy_residual_J"
        ],
        "native_tank_endpoint_energy_residual_J": result[
            "native_tank_endpoint_energy_residual_J"
        ],
        "seed_eligible": False,
        "output": str(args.output),
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
