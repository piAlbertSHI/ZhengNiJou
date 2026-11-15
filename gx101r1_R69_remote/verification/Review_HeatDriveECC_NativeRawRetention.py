#!/usr/bin/env python3
"""Read-only review of four native diagnostic raw observation packages."""

from __future__ import annotations

import csv
import glob
import hashlib
import json
import os
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List

import h5py
import numpy as np


PROJECT = Path(r"C:\Users\86182\Desktop\正逆耦合")
OUT = PROJECT / r"gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_native_raw_review_20261115"
TARGETS = {
    "qian_warmup20_logmean_kp50": Path(
        r"C:\Users\86182\.codex\worktrees\fixed-stage4-kp237-endpoint\正逆耦合\gx101r1_R69_remote\outputs\qian_coupled_stage4_warmup20_logmean_kp50_20260927_wt"
    ),
    "qian_default_kp160_20cycle": Path(
        r"C:\Users\86182\.codex\worktrees\stage4-default-cold-diagnostic\正逆耦合\gx101r1_R69_remote\outputs\qian_coupled_stage4_default_kp160_20260927_20cycle"
    ),
    "qian_phase_local_blend_20cycle": Path(
        r"C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs\qian_coupled_stage4_phase_local_blend_20260928_20cycle_warmup"
    ),
    "qian_single_target_contract_20cycle": Path(
        r"C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs\qian_coupled_stage4_single_target_contract_20260929_20cycle_progress_contract"
    ),
}

REQUIRED_COMPACT_EVIDENCE = [
    "cycle_physical_summary.csv",
    "mechanism.json",
    "packet_gate.json",
    "physical_validation_report.txt",
    "stage_temperature_probes_50samples.csv",
    "final_operating_point.mat",
]


def now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        while block := fh.read(1024 * 1024):
            h.update(block)
    return h.hexdigest().upper()


def dump(path: Path, obj: Any) -> None:
    path.write_text(json.dumps(obj, ensure_ascii=True, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def scalar(value: Any) -> Any:
    value = np.asarray(value).reshape(-1)
    if value.size == 1:
        item = value[0]
        if isinstance(item, np.generic):
            item = item.item()
        return item
    return None


def h5_summary(path: Path) -> Dict[str, Any]:
    result: Dict[str, Any] = {"path": str(path), "bytes": path.stat().st_size, "sha256": sha256(path)}
    with h5py.File(path, "r") as root:
        result["root_keys"] = list(root.keys())
        datasets = 0
        logical_bytes = 0
        time_axes: List[Dict[str, Any]] = []
        boundary: Dict[str, Any] = {}

        if "boundary_metadata" in root:
            b = root["boundary_metadata"]
            for key in (
                "complete_cycle_verified",
                "full_device_first_law_verified",
                "physical_model_modified",
                "production_recovery_allowed",
                "source_count",
                "trace_count",
            ):
                if key in b:
                    boundary[key] = scalar(b[key][()])

        def visit(group: Any, prefix: str = "") -> None:
            nonlocal datasets, logical_bytes
            for name, obj in group.items():
                if not prefix and name.startswith("#"):
                    continue
                current = f"{prefix}/{name}" if prefix else name
                if hasattr(obj, "items"):
                    visit(obj, current)
                    continue
                datasets += 1
                logical_bytes += int(obj.size * obj.dtype.itemsize)
                if name.lower() in {"time", "time_s", "tout", "t"} and obj.size <= 2_000_000:
                    values = np.asarray(obj[()]).reshape(-1)
                    values = values[np.isfinite(values)]
                    if values.size:
                        time_axes.append(
                            {
                                "path": current,
                                "samples": int(values.size),
                                "min": float(values.min()),
                                "max": float(values.max()),
                                "monotonic_non_decreasing": bool(np.all(np.diff(values) >= 0)),
                            }
                        )

        visit(root)
        result["dataset_count_excluding_refs"] = datasets
        result["dataset_logical_bytes_excluding_refs"] = logical_bytes
        result["boundary_metadata"] = boundary
        result["time_axes"] = time_axes[:20]
        result["signal_group_counts"] = {
            name: len(root[name].keys()) if hasattr(root[name], "keys") else None
            for name in (
                "signals",
                "pressure_probe_signals",
                "stage4_controller_probe_signals",
            )
            if name in root
        }
    return result


def selected_execution(path: Path) -> Dict[str, Any]:
    obj = json.loads(path.read_text(encoding="utf-8-sig"))
    selected = {}
    for key in (
        "execution_commit",
        "c200_state_imported",
        "production_recovery_allowed",
        "diagnostic_simulation_mode",
        "table4_reproduction_claim",
        "periodic_steady_state",
        "full_device_first_law_verified",
        "checkpoint_saved",
        "start_time_s",
        "stop_time_s",
        "cycle_count",
        "collection_pass",
        "error_message",
        "initialization_source_root",
        "c200_result_sha256",
        "c200_checkpoint_sha256",
    ):
        if key in obj:
            selected[key] = obj[key]
    selected["sha256"] = sha256(path)
    selected["bytes"] = path.stat().st_size
    selected["cases"] = obj.get("cases", [])
    return selected


def direct_refs(name: str) -> Dict[str, Any]:
    args = [
        "rg",
        "--files-with-matches",
        "--hidden",
        "--glob",
        "!outputs/**",
        "--glob",
        "!outputs_storage_audit/**",
        "--glob",
        "!*.mat",
        "--glob",
        "!*.h5",
        "--glob",
        "!*.slx",
        "--glob",
        "!*.slxc",
        "--glob",
        "!*.json",
        "--glob",
        "!*.csv",
        "--glob",
        "!*.md",
        "--glob",
        "!*.txt",
        name,
        str(PROJECT / "gx101r1_R69_remote"),
    ]
    proc = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace", check=False)
    matches = [line for line in (proc.stdout or "").splitlines() if line.strip()]
    production = [
        path
        for path in matches
        if not re.search(r"Retire_|Workspace_DeepCleanup|Audit_|Review_HeatDriveECC", path)
    ]
    return {"all_matches": matches, "retirement_or_audit_matches": [p for p in matches if p not in production], "production_matches": production}


def summarize(name: str, root: Path) -> Dict[str, Any]:
    raw = root / "native" / "observations.mat"
    execution_path = next(root.rglob("cold_chamber_execution.json"))
    execution = selected_execution(execution_path)
    files = []
    for path in sorted(root.rglob("*")):
        if path.is_file():
            files.append({"path": str(path), "bytes": path.stat().st_size, "sha256": sha256(path)})
    missing = [item for item in REQUIRED_COMPACT_EVIDENCE if not (root / "native" / item).exists() and not (root / item).exists()]
    raw_meta = h5_summary(raw)
    refs = direct_refs(root.name)
    coverage_pass = False
    return {
        "target": name,
        "root": str(root),
        "generated_utc": now(),
        "raw_observation": raw_meta,
        "execution_contract": execution,
        "file_inventory": files,
        "missing_compact_conclusion_evidence": missing,
        "direct_script_references": refs,
        "coverage": {
            "raw_hash_recorded": True,
            "dimensions_and_time_axes_recorded": bool(raw_meta.get("time_axes")),
            "pressure_and_stage4_probe_metadata_recorded": True,
            "cycle_energy_flow_gate_summary_present": False,
            "temperature_probe_summary_present": False,
            "production_script_direct_reference_absent": not refs["production_matches"],
            "coverage_pass": coverage_pass,
        },
        "decision": "manual_confirmation_required",
        "deletion_allowed": False,
        "potential_reclaimable_bytes_if_replaced": raw.stat().st_size,
        "reason": (
            "Native raw contains full 0-200 s traces and probe metadata, but no compact cycle-level "
            "flow/energy/pressure gate summary, temperature-probe summary, mechanism report, or final OP. "
            "Deleting it would remove unique native-arm diagnostic evidence."
        ),
    }


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    results = [summarize(name, root) for name, root in TARGETS.items()]
    review = {
        "schema": "heatdrive_ecc_native_raw_retention_review_v1",
        "generated_utc": now(),
        "read_only": True,
        "deletion_performed": False,
        "matlab_simulink_started_or_interrupted": False,
        "targets": results,
        "total_potential_reclaimable_bytes": sum(item["potential_reclaimable_bytes_if_replaced"] for item in results),
        "total_potential_reclaimable_gib": round(sum(item["potential_reclaimable_bytes_if_replaced"] for item in results) / (1024**3), 6),
        "protected_paths": ["C200", "v43", "C020", "v64c1", "v65c1", "v45", "Agent6", "model files", "audit chain"],
        "decision": "retain_all_four_native_raw_manual_confirmation_required",
    }
    dump(OUT / "native_raw_retention_review.json", review)
    with (OUT / "native_raw_retention_review.csv").open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(
            fh,
            fieldnames=["target", "raw_path", "raw_bytes", "raw_sha256", "time_min_s", "time_max_s", "time_samples", "datasets_excluding_refs", "missing_compact_evidence", "decision"],
        )
        writer.writeheader()
        for item in results:
            raw = item["raw_observation"]
            axis = raw["time_axes"][0] if raw["time_axes"] else {}
            writer.writerow(
                {
                    "target": item["target"],
                    "raw_path": raw["path"],
                    "raw_bytes": raw["bytes"],
                    "raw_sha256": raw["sha256"],
                    "time_min_s": axis.get("min", ""),
                    "time_max_s": axis.get("max", ""),
                    "time_samples": axis.get("samples", ""),
                    "datasets_excluding_refs": raw.get("dataset_count_excluding_refs", ""),
                    "missing_compact_evidence": ";".join(item["missing_compact_conclusion_evidence"]),
                    "decision": item["decision"],
                }
            )
    manifest = {
        "schema": "heatdrive_ecc_native_raw_retention_manifest_v1",
        "generated_utc": now(),
        "source_review": str(OUT / "native_raw_retention_review.json"),
        "source_csv": str(OUT / "native_raw_retention_review.csv"),
        "deletion_performed": False,
        "deletion_allowed": False,
        "reason": "No compact native replacement covers all required conclusion fields.",
    }
    dump(OUT / "native_raw_retention_manifest.json", manifest)
    sums = []
    for path in sorted(OUT.glob("*")):
        if path.is_file() and path.name != "sha256sums.txt":
            sums.append(f"{sha256(path)}  {path.name}")
    (OUT / "sha256sums.txt").write_text("\n".join(sums) + "\n", encoding="utf-8")
    print(json.dumps({"schema": review["schema"], "decision": review["decision"], "total_potential_reclaimable_bytes": review["total_potential_reclaimable_bytes"], "target_count": len(results)}, ensure_ascii=True, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
