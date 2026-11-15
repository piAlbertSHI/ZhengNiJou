#!/usr/bin/env python3
"""Create compact native failure dossiers and optionally retire native raw traces.

This script never starts MATLAB or Simulink.  Without ``--retire`` it is
read-only.  With ``--retire`` it deletes only the four exact native
``observations.mat`` files after the dossier coverage and hash checks pass.
"""

from __future__ import annotations

import csv
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List

import h5py
import numpy as np


PROJECT = Path(r"C:\Users\86182\Desktop\正逆耦合")
OUT = PROJECT / r"gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_native_dossier_20261115"
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

REQUIRED_REPLACEMENT_FILES = [
    "cold_chamber_execution.json",
    "launcher_contract.json",
    "native/configuration.mat",
    "native/cold_public_targets.mat",
    "native/buffer_replacement_contract.json",
    "native/pump_pressure_probe_contract.json",
    "native/stage4_controller_probe_contract.json",
]


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        while block := fh.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest().upper()


def dump(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, ensure_ascii=True, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def matlab_processes() -> List[str]:
    proc = subprocess.run(
        ["tasklist", "/FO", "CSV", "/NH"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    return [line for line in (proc.stdout or "").splitlines() if re.search(r"MATLAB|Simulink", line, re.I)]


def direct_references(name: str) -> Dict[str, Any]:
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
        if not re.search(r"Retire_|Workspace_DeepCleanup|Audit_|Review_HeatDriveECC|Build_HeatDriveECC", path)
    ]
    return {"all_matches": matches, "production_script_references": production}


def scalar(dataset: Any) -> Any:
    values = np.asarray(dataset).reshape(-1)
    if values.size != 1:
        return None
    value = values[0]
    return value.item() if isinstance(value, np.generic) else value


def signal_summary(group: Any, signal_name: str) -> Dict[str, Any]:
    signal = group[signal_name]
    time = np.asarray(signal["time_s"][()]).reshape(-1)
    values = np.asarray(signal["values"][()]).reshape(-1)
    if time.size != values.size:
        raise ValueError(f"time/value size mismatch for {signal_name}")
    if not np.all(np.isfinite(time)) or not np.all(np.isfinite(values)):
        raise ValueError(f"non-finite values for {signal_name}")
    indices = np.linspace(0, values.size - 1, 101).round().astype(int)
    return {
        "name": signal_name,
        "samples": int(values.size),
        "time_min_s": float(time.min()),
        "time_max_s": float(time.max()),
        "time_monotonic_non_decreasing": bool(np.all(np.diff(time) >= 0)),
        "value_min": float(values.min()),
        "value_max": float(values.max()),
        "first_value": float(values[0]),
        "last_value": float(values[-1]),
        "fixed_downsample_count": int(indices.size),
        "fixed_downsample": [
            {"time_s": float(time[index]), "value": float(values[index])} for index in indices
        ],
    }


def raw_dossier(raw: Path) -> Dict[str, Any]:
    result: Dict[str, Any] = {
        "path": str(raw),
        "bytes": raw.stat().st_size,
        "sha256": sha256(raw),
        "root_keys": [],
        "boundary_metadata": {},
        "signal_counts": {},
        "signal_summaries": {"pressure_probe_signals": [], "stage4_controller_probe_signals": []},
        "dataset_count_excluding_refs": 0,
        "dataset_logical_bytes_excluding_refs": 0,
    }
    with h5py.File(raw, "r") as root:
        result["root_keys"] = list(root.keys())
        boundary = root["boundary_metadata"]
        for key in (
            "complete_cycle_verified",
            "full_device_first_law_verified",
            "physical_model_modified",
            "production_recovery_allowed",
            "source_count",
            "trace_count",
        ):
            if key in boundary:
                result["boundary_metadata"][key] = scalar(boundary[key][()])
        for group_name in ("signals", "pressure_probe_signals", "stage4_controller_probe_signals"):
            if group_name in root:
                group = root[group_name]
                result["signal_counts"][group_name] = len(group.keys())
                if group_name in result["signal_summaries"]:
                    result["signal_summaries"][group_name] = [
                        signal_summary(group, name) for name in sorted(group.keys())
                    ]

        def count_datasets(group: Any, prefix: str = "") -> None:
            for name, obj in group.items():
                if not prefix and name.startswith("#"):
                    continue
                if hasattr(obj, "items"):
                    count_datasets(obj, f"{prefix}/{name}" if prefix else name)
                else:
                    result["dataset_count_excluding_refs"] += 1
                    result["dataset_logical_bytes_excluding_refs"] += int(obj.size * obj.dtype.itemsize)

        count_datasets(root)
    return result


def execution_summary(root: Path) -> Dict[str, Any]:
    path = next(root.rglob("cold_chamber_execution.json"))
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
    selected["cases"] = obj.get("cases", [])
    selected["path"] = str(path)
    selected["bytes"] = path.stat().st_size
    selected["sha256"] = sha256(path)
    return selected


def build_dossier(name: str, root: Path) -> Dict[str, Any]:
    raw = root / "native" / "observations.mat"
    execution = execution_summary(root)
    refs = direct_references(root.name)
    processes = matlab_processes()
    replacement_files = []
    for path in sorted(root.rglob("*")):
        if path.is_file() and path != raw:
            replacement_files.append(
                {"path": str(path), "bytes": path.stat().st_size, "sha256": sha256(path)}
            )
    required = []
    for relative in REQUIRED_REPLACEMENT_FILES:
        path = root / relative
        required.append(
            {"path": str(path), "present": path.exists(), "sha256": sha256(path) if path.exists() else None}
        )
    raw_summary = raw_dossier(raw)
    pressure = raw_summary["signal_summaries"]["pressure_probe_signals"]
    stage4 = raw_summary["signal_summaries"]["stage4_controller_probe_signals"]
    coverage_pass = bool(
        len(pressure) == 6
        and len(stage4) == 17
        and all(item["samples"] == 200001 for item in pressure + stage4)
        and all(item["time_monotonic_non_decreasing"] for item in pressure + stage4)
        and all(item["value_min"] == item["value_min"] for item in pressure + stage4)
        and all(item["present"] for item in required)
        and not refs["production_script_references"]
        and not processes
    )
    failure_reason = (
        "Diagnostic package is not a production or recovery result: "
        f"complete_cycle_verified={raw_summary['boundary_metadata'].get('complete_cycle_verified')}, "
        f"full_device_first_law_verified={raw_summary['boundary_metadata'].get('full_device_first_law_verified')}, "
        f"production_recovery_allowed={raw_summary['boundary_metadata'].get('production_recovery_allowed')}, "
        f"checkpoint_saved={execution.get('checkpoint_saved')}, "
        f"periodic_steady_state={execution.get('periodic_steady_state')}, "
        f"table4_reproduction_claim={execution.get('table4_reproduction_claim')}."
    )
    return {
        "schema": "heatdrive_ecc_native_failure_dossier_v1",
        "generated_utc": utc_now(),
        "target": name,
        "root": str(root),
        "raw_observation": raw_summary,
        "execution_contract": execution,
        "required_replacement_files": required,
        "replacement_files": replacement_files,
        "direct_script_references": refs,
        "matlab_simulink_processes_before_delete": processes,
        "failure_reason": failure_reason,
        "coverage": {
            "pressure_probe_count": len(pressure),
            "stage4_probe_count": len(stage4),
            "pressure_and_stage4_fixed_downsample_complete": coverage_pass,
            "required_replacement_hashes_complete": all(item["present"] for item in required),
            "production_script_direct_reference_absent": not refs["production_script_references"],
            "coverage_pass": coverage_pass,
        },
        "deletion_allowed": coverage_pass,
    }


def write_dossiers() -> List[Dict[str, Any]]:
    OUT.mkdir(parents=True, exist_ok=True)
    dossiers = [build_dossier(name, root) for name, root in TARGETS.items()]
    for dossier in dossiers:
        dump(OUT / f"{dossier['target']}_failure_dossier.json", dossier)
    with (OUT / "failure_dossier.csv").open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(
            fh,
            fieldnames=[
                "target",
                "raw_path",
                "raw_bytes",
                "raw_sha256",
                "time_min_s",
                "time_max_s",
                "sample_count",
                "pressure_probe_count",
                "stage4_probe_count",
                "complete_cycle_verified",
                "full_device_first_law_verified",
                "production_recovery_allowed",
                "checkpoint_saved",
                "periodic_steady_state",
                "table4_reproduction_claim",
                "coverage_pass",
                "deletion_allowed",
            ],
        )
        writer.writeheader()
        for dossier in dossiers:
            raw = dossier["raw_observation"]
            axis = dossier["raw_observation"]["signal_summaries"]["pressure_probe_signals"][0]
            boundary = raw["boundary_metadata"]
            execution = dossier["execution_contract"]
            writer.writerow(
                {
                    "target": dossier["target"],
                    "raw_path": raw["path"],
                    "raw_bytes": raw["bytes"],
                    "raw_sha256": raw["sha256"],
                    "time_min_s": axis["time_min_s"],
                    "time_max_s": axis["time_max_s"],
                    "sample_count": axis["samples"],
                    "pressure_probe_count": dossier["coverage"]["pressure_probe_count"],
                    "stage4_probe_count": dossier["coverage"]["stage4_probe_count"],
                    "complete_cycle_verified": boundary.get("complete_cycle_verified"),
                    "full_device_first_law_verified": boundary.get("full_device_first_law_verified"),
                    "production_recovery_allowed": boundary.get("production_recovery_allowed"),
                    "checkpoint_saved": execution.get("checkpoint_saved"),
                    "periodic_steady_state": execution.get("periodic_steady_state"),
                    "table4_reproduction_claim": execution.get("table4_reproduction_claim"),
                    "coverage_pass": dossier["coverage"]["coverage_pass"],
                    "deletion_allowed": dossier["deletion_allowed"],
                }
            )
    manifest = {
        "schema": "heatdrive_ecc_native_failure_dossier_manifest_v1",
        "generated_utc": utc_now(),
        "dossier_count": len(dossiers),
        "dossier_files": [str(OUT / f"{d['target']}_failure_dossier.json") for d in dossiers],
        "csv": str(OUT / "failure_dossier.csv"),
        "deletion_performed": False,
        "deletion_allowed_only_after_all_dossiers_pass": True,
        "protected_paths": ["C200", "v43", "C020", "models", "configs", "existing audit chain"],
    }
    dump(OUT / "failure_dossier_manifest.json", manifest)
    sums = []
    for path in sorted(OUT.glob("*")):
        if path.is_file() and path.name != "sha256sums.txt":
            sums.append(f"{sha256(path)}  {path.name}")
    (OUT / "sha256sums.txt").write_text("\n".join(sums) + "\n", encoding="utf-8")
    return dossiers


def retire(dossiers: List[Dict[str, Any]]) -> Dict[str, Any]:
    if not all(dossier["deletion_allowed"] for dossier in dossiers):
        raise RuntimeError("Dossier coverage did not pass for every target")
    if matlab_processes():
        raise RuntimeError("MATLAB/Simulink process is active")
    deleted = []
    for dossier in dossiers:
        raw = Path(dossier["raw_observation"]["path"])
        if not raw.exists() or sha256(raw) != dossier["raw_observation"]["sha256"]:
            raise RuntimeError(f"Raw changed or missing: {raw}")
        size = raw.stat().st_size
        os.remove(raw)
        if raw.exists():
            raise RuntimeError(f"Deletion postcheck failed: {raw}")
        deleted.append({"path": str(raw), "bytes": size, "sha256": dossier["raw_observation"]["sha256"], "replacement": str(OUT / f"{dossier['target']}_failure_dossier.json")})
    receipt = {
        "schema": "heatdrive_ecc_native_failure_dossier_retirement_receipt_v1",
        "status": "completed",
        "generated_utc": utc_now(),
        "deleted_file_count": len(deleted),
        "reclaimed_bytes": sum(item["bytes"] for item in deleted),
        "reclaimed_gib": round(sum(item["bytes"] for item in deleted) / (1024**3), 6),
        "deleted_files": deleted,
        "scientific_gates_changed": False,
        "C200_touched": False,
        "v43_touched": False,
        "C020_touched": False,
        "models_or_configs_deleted": False,
        "matlab_simulink_started_or_interrupted": False,
    }
    dump(OUT / "retirement_receipt.json", receipt)
    postcheck = {
        "schema": "heatdrive_ecc_native_failure_dossier_postcheck_v1",
        "generated_utc": utc_now(),
        "deleted_paths_still_present": [item["path"] for item in deleted if Path(item["path"]).exists()],
        "replacement_missing": [item["replacement"] for item in deleted if not Path(item["replacement"]).exists()],
        "matlab_simulink_processes": matlab_processes(),
    }
    postcheck["postcheck_pass"] = bool(
        not postcheck["deleted_paths_still_present"]
        and not postcheck["replacement_missing"]
        and not postcheck["matlab_simulink_processes"]
    )
    dump(OUT / "postcheck.json", postcheck)
    sums = []
    for path in sorted(OUT.glob("*")):
        if path.is_file() and path.name != "sha256sums.txt":
            sums.append(f"{sha256(path)}  {path.name}")
    (OUT / "sha256sums.txt").write_text("\n".join(sums) + "\n", encoding="utf-8")
    return receipt


def postcheck_only() -> Dict[str, Any]:
    receipt_path = OUT / "retirement_receipt.json"
    if not receipt_path.exists():
        raise RuntimeError(f"Missing retirement receipt: {receipt_path}")
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    deleted = receipt.get("deleted_files", [])
    postcheck = {
        "schema": "heatdrive_ecc_native_failure_dossier_postcheck_v1",
        "generated_utc": utc_now(),
        "deleted_paths_still_present": [item["path"] for item in deleted if Path(item["path"]).exists()],
        "replacement_missing": [item["replacement"] for item in deleted if not Path(item["replacement"]).exists()],
        "matlab_simulink_processes": matlab_processes(),
    }
    postcheck["postcheck_pass"] = bool(
        not postcheck["deleted_paths_still_present"]
        and not postcheck["replacement_missing"]
        and not postcheck["matlab_simulink_processes"]
    )
    dump(OUT / "postcheck.json", postcheck)
    sums = []
    for path in sorted(OUT.glob("*")):
        if path.is_file() and path.name != "sha256sums.txt":
            sums.append(f"{sha256(path)}  {path.name}")
    (OUT / "sha256sums.txt").write_text("\n".join(sums) + "\n", encoding="utf-8")
    return postcheck


def main() -> int:
    if "--postcheck" in sys.argv[1:]:
        print(json.dumps(postcheck_only(), ensure_ascii=True, indent=2))
        return 0
    retire_requested = "--retire" in sys.argv[1:]
    dossiers = write_dossiers()
    if retire_requested:
        receipt = retire(dossiers)
        print(json.dumps(receipt, ensure_ascii=True, indent=2))
    else:
        print(json.dumps({"schema": "heatdrive_ecc_native_failure_dossier_audit_v1", "delete_performed": False, "targets": [{"target": d["target"], "coverage_pass": d["coverage"]["coverage_pass"], "deletion_allowed": d["deletion_allowed"], "raw_bytes": d["raw_observation"]["bytes"]} for d in dossiers]}, ensure_ascii=True, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
