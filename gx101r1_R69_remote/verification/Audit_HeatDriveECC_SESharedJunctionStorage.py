#!/usr/bin/env python3
"""Read-only source audit for the shared SE junction storage assumption.

This is a diagnostic provenance check.  It does not authorize a seed,
checkpoint restore, cycle run, or production recovery.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path


def _read(path: Path) -> tuple[str, str]:
    data = path.read_bytes()
    return data.decode("utf-8-sig"), hashlib.sha256(data).hexdigest()


def _line(text: str, needle: str) -> int | None:
    for number, value in enumerate(text.splitlines(), 1):
        if needle in value:
            return number
    return None


def _match(text: str, pattern: str) -> str | None:
    found = re.search(pattern, text, flags=re.MULTILINE)
    return found.group(0).strip() if found else None


def audit(repo_root: Path) -> dict:
    defaults_path = repo_root / "Build_HeatDriveECC_EighthRound_Defaults.m"
    integrate_path = repo_root / "Integrate_HeatDriveECC_Constitutive21_Interface.m"
    build_path = repo_root / "Build_HeatDriveECC_EighthRound_Simulink_Model.m"
    paths = {
        "defaults": defaults_path,
        "integration": integrate_path,
        "topology_audit": build_path,
    }
    texts: dict[str, str] = {}
    hashes: dict[str, str] = {}
    for name, path in paths.items():
        if not path.is_file():
            raise FileNotFoundError(path)
        texts[name], hashes[name] = _read(path)

    integration = texts["integration"]
    defaults = texts["defaults"]
    topology = texts["topology_audit"]

    junction_source = "SimscapeFluids_lib/Thermal Liquid/Pipes & Fittings/T-Junction (TL)"
    integration_has_junction = junction_source in integration
    inertia_false_count = len(re.findall(r"'inertia'\s*,\s*'false'", integration))
    direct_manifold_model = "zero_volume_direct_manifold_node" in defaults
    finite_hold_pipe_statement = "connecting-pipe finite volumes preserve the manifold enthalpy" in integration
    topology_requires_junctions = "junction_count == 2" in topology
    topology_rejects_cooldown = "cooldown_pipe_count == 0" in topology

    findings = {
        "shared_junction_uses_t_junction_tl": integration_has_junction,
        "shared_junction_inertia_false_occurrences": inertia_false_count,
        "defaults_declare_zero_volume_direct_manifold": direct_manifold_model,
        "integration_claims_finite_connecting_pipe_enthalpy": finite_hold_pipe_statement,
        "topology_audit_requires_two_junctions": topology_requires_junctions,
        "topology_audit_requires_no_cooldown_pipes": topology_rejects_cooldown,
    }

    # This is intentionally a hypothesis flag, not a physical-failure verdict.
    # A finite HoldPipe inventory can still matter even when the junction itself
    # is algebraic; runtime observations are required to decide causality.
    hypothesis_flag = (
        integration_has_junction
        and inertia_false_count >= 2
        and direct_manifold_model
        and finite_hold_pipe_statement
    )

    line_refs = {
        "defaults_zero_volume_model": _line(defaults, "zero_volume_direct_manifold_node"),
        "integration_junction_source": _line(integration, junction_source),
        "integration_first_inertia_false": _line(integration, "'inertia', 'false'"),
        "integration_enthalpy_comment": _line(
            integration, "connecting-pipe finite volumes preserve the manifold enthalpy"
        ),
        "topology_junction_count_gate": _line(topology, "junction_count == 2"),
    }

    return {
        "schema": "heatdrive_ecc_se_shared_junction_storage_audit_v1",
        "scope": "source_architecture_only",
        "seed_or_recovery_authority": False,
        "decision": (
            "architecture_level_finite_junction_storage_diagnostic_required"
            if hypothesis_flag
            else "no_complete_source_level_storage_hypothesis"
        ),
        "interpretation": (
            "The shared SE junction is algebraic while finite HoldPipe inventory is "
            "claimed elsewhere. This is a hypothesis for the reentry event, not a "
            "mechanism-failure verdict and not a license to change production geometry."
            if hypothesis_flag
            else "Source evidence is insufficient for the targeted hypothesis."
        ),
        "findings": findings,
        "line_references": line_refs,
        "source_sha256": hashes,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = audit(args.repo_root.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
