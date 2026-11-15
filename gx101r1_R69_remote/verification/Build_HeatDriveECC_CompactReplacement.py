#!/usr/bin/env python3
"""Build compact, hash-bound replacements for selected historical raw runs.

The default mode is read-only.  ``--delete`` removes only the exact raw
trajectory files whose compact replacement passed all checks in a prior run.
No MATLAB or Simulink API is used.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List


PROJECT = Path(r"C:\Users\86182\Desktop\正逆耦合")
OUTPUT_ROOT = PROJECT / r"gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_compact_20261115"

TARGETS = {
    "v64c1": Path(
        r"C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs\v64c1"
    ),
    "v65c1": Path(
        r"C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs\v65c1"
    ),
    "v45_buffer_cold_factorial_r1": Path(
        r"C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs\v45_buffer_cold_factorial_r1"
    ),
}

TRAJECTORY_NAMES = {"observations.mat", "observed_states.mat"}
V45_RAW_NAME = "observations.mat"
JSON_FIELD_TOKENS = (
    "pass",
    "gate",
    "mechanism",
    "periodic",
    "recovery",
    "production",
    "failure",
    "error",
    "drift",
    "pressure",
    "flow",
    "energy",
    "mass",
    "temperature",
    "phase",
    "cycle",
    "start_time",
    "stop_time",
    "snapshot",
    "operating_point",
    "source",
    "hash",
    "window",
    "target",
    "complete",
    "eligible",
    "claim",
)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        while True:
            block = fh.read(1024 * 1024)
            if not block:
                break
            h.update(block)
    return h.hexdigest().upper()


def json_dump(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, ensure_ascii=True, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def compact_scalar(value: Any) -> Any:
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    return None


def collect_json_fields(value: Any, prefix: str = "", out: Dict[str, Any] | None = None) -> Dict[str, Any]:
    if out is None:
        out = {}
    if len(out) >= 240:
        return out
    if isinstance(value, dict):
        for key, child in value.items():
            key_text = str(key)
            path = f"{prefix}.{key_text}" if prefix else key_text
            scalar = compact_scalar(child)
            lowered = key_text.lower()
            if scalar is not None and (not prefix or any(token in lowered for token in JSON_FIELD_TOKENS)):
                out[path] = scalar
            if isinstance(child, (dict, list)):
                collect_json_fields(child, path, out)
    elif isinstance(value, list):
        if len(value) <= 20:
            for index, child in enumerate(value):
                collect_json_fields(child, f"{prefix}[{index}]", out)
        else:
            out[f"{prefix}.__len__"] = len(value)
    return out


def summarize_json(path: Path) -> Dict[str, Any]:
    raw = path.read_bytes()
    result: Dict[str, Any] = {
        "path": str(path),
        "bytes": len(raw),
        "sha256": sha256_file(path),
    }
    try:
        parsed = json.loads(raw.decode("utf-8-sig"))
        result["keys"] = list(parsed.keys()) if isinstance(parsed, dict) else []
        result["selected_fields"] = collect_json_fields(parsed)
    except Exception as exc:
        result["parse_error"] = repr(exc)
    return result


def summarize_csv(path: Path) -> Dict[str, Any]:
    raw = path.read_bytes()
    result: Dict[str, Any] = {
        "path": str(path),
        "bytes": len(raw),
        "sha256": sha256_file(path),
    }
    try:
        with path.open("r", encoding="utf-8-sig", newline="") as fh:
            reader = csv.DictReader(fh)
            rows = list(reader)
        result["columns"] = reader.fieldnames or []
        result["row_count"] = len(rows)
        result["first_row"] = rows[0] if rows else {}
        result["last_row"] = rows[-1] if rows else {}
        numeric_ranges: Dict[str, Dict[str, float]] = {}
        for column in reader.fieldnames or []:
            values: List[float] = []
            for row in rows:
                try:
                    values.append(float(row[column]))
                except (TypeError, ValueError):
                    pass
            if values:
                numeric_ranges[column] = {"min": min(values), "max": max(values)}
        result["numeric_ranges"] = numeric_ranges
    except Exception as exc:
        result["parse_error"] = repr(exc)
    return result


def summarize_text(path: Path) -> Dict[str, Any]:
    raw = path.read_bytes()
    lines = raw.decode("utf-8", errors="replace").splitlines()
    failure_lines = [
        line[:400]
        for line in lines
        if re.search(r"fail|error|reject|invalid|not pass|exception", line, re.IGNORECASE)
    ][:40]
    return {
        "path": str(path),
        "bytes": len(raw),
        "sha256": sha256_file(path),
        "line_count": len(lines),
        "head": lines[:4],
        "tail": lines[-4:],
        "failure_lines": failure_lines,
    }


def hdf5_metadata(path: Path) -> Dict[str, Any]:
    result: Dict[str, Any] = {
        "path": str(path),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }
    try:
        import h5py  # type: ignore
        import numpy as np  # type: ignore
    except Exception as exc:
        result["format"] = "unparsed"
        result["parse_error"] = f"h5py/numpy unavailable: {exc!r}"
        return result

    try:
        with h5py.File(path, "r") as root:
            result["format"] = "MAT-v7.3/HDF5"
            result["root_keys"] = list(root.keys())
            datasets = 0
            logical_bytes = 0
            time_axes: List[Dict[str, Any]] = []
            shape_samples: List[Dict[str, Any]] = []

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
                    try:
                        logical_bytes += int(obj.size * obj.dtype.itemsize)
                    except Exception:
                        pass
                    if len(shape_samples) < 80:
                        shape_samples.append(
                            {"path": current, "shape": list(obj.shape), "dtype": str(obj.dtype)}
                        )
                    base = name.lower()
                    if base in {"time", "time_s", "tout", "t"} and obj.size <= 2_000_000:
                        try:
                            values = np.asarray(obj[()]).reshape(-1)
                            finite = values[np.isfinite(values)]
                            if finite.size:
                                time_axes.append(
                                    {
                                        "path": current,
                                        "samples": int(values.size),
                                        "min": float(finite.min()),
                                        "max": float(finite.max()),
                                        "monotonic_non_decreasing": bool(
                                            np.all(np.diff(finite) >= 0)
                                        ),
                                    }
                                )
                        except Exception:
                            pass

            visit(root)
            result["dataset_count_excluding_refs"] = datasets
            result["dataset_logical_bytes_excluding_refs"] = logical_bytes
            result["shape_samples"] = shape_samples
            result["time_axes"] = time_axes[:40]
    except Exception as exc:
        result["format"] = "non-HDF5-or-unreadable"
        result["parse_error"] = repr(exc)
    return result


def summarize_binary(path: Path) -> Dict[str, Any]:
    if path.suffix.lower() in {".mat", ".h5"}:
        return hdf5_metadata(path)
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": sha256_file(path)}


def tasklist_matlab() -> List[str]:
    try:
        raw = subprocess.run(
            ["tasklist", "/FO", "CSV", "/NH"], capture_output=True, text=True, check=False
        ).stdout
        return [line for line in raw.splitlines() if re.search(r"MATLAB|Simulink", line, re.IGNORECASE)]
    except Exception as exc:
        return [f"tasklist_error: {exc!r}"]


def reference_scan(name: str) -> Dict[str, Any]:
    roots = [PROJECT / "gx101r1_R69_remote"]
    matches: List[str] = []
    for root in roots:
        try:
            proc = subprocess.run(
                [
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
                    str(root),
                ],
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                check=False,
            )
            matches.extend(line for line in (proc.stdout or "").splitlines() if line.strip())
        except Exception as exc:
            matches.append(f"rg_error: {exc!r}")
    allowed = []
    outside = []
    for match in sorted(set(matches)):
        if re.search(r"Retire_|Workspace_DeepCleanup|Audit_|Build_HeatDriveECC_CompactReplacement", match):
            allowed.append(match)
        else:
            outside.append(match)
    return {
        "matches": sorted(set(matches)),
        "allowed_audit_or_retirement_refs": allowed,
        "direct_script_references_outside_audit": outside,
    }


def relative(path: Path, root: Path) -> str:
    return str(path.relative_to(root)).replace("/", "\\")


def evidence_summary(directory: Path, names: Iterable[str]) -> Dict[str, Any]:
    items: Dict[str, Any] = {}
    for name in names:
        path = directory / name
        if not path.exists():
            items[name] = {"present": False}
        elif path.suffix.lower() == ".json":
            items[name] = {"present": True, "summary": summarize_json(path)}
        elif path.suffix.lower() == ".csv":
            items[name] = {"present": True, "summary": summarize_csv(path)}
        elif path.suffix.lower() in {".mat", ".h5"}:
            items[name] = {"present": True, "summary": summarize_binary(path)}
        else:
            items[name] = {"present": True, "summary": summarize_text(path)}
    return items


def packet_summary(packet: Path, root: Path) -> Dict[str, Any]:
    required = [
        "packet_manifest.json",
        "cycle_physical_summary.csv",
        "mechanism.json",
        "physical_validation_report.txt",
        "stage_temperature_probes_50samples.csv",
        "comparison_only_complete_op.mat",
    ]
    gate_json = packet / "packet_gate.json"
    gate_log = packet / "packet_gate_stdout.log"
    gate_present = gate_json.exists() or gate_log.exists()
    evidence = evidence_summary(packet, required)
    evidence["packet_gate.json_or_stdout.log"] = {
        "present": gate_present,
        "summary": summarize_json(gate_json) if gate_json.exists() else summarize_text(gate_log)
        if gate_log.exists()
        else None,
    }
    raw_files = [
        summarize_binary(path)
        for path in packet.rglob("*")
        if path.is_file() and path.name in TRAJECTORY_NAMES
    ]
    compact_ok = all(item.get("present") for key, item in evidence.items() if key != "packet_gate.json_or_stdout.log") and gate_present
    return {
        "relative_path": relative(packet, root),
        "required_evidence_complete": compact_ok,
        "evidence": evidence,
        "raw_candidates": raw_files,
    }


def v45_arm_summary(arm: Path, root: Path) -> Dict[str, Any]:
    required = [
        "cold_chamber_execution.json",
        "runtime_evidence_contract.mat",
        "native/cold_mechanism_audit.json",
        "native/cold_mechanism_observation.mat",
        "native/cycle_physical_summary.csv",
        "native/physical_validation_report.txt",
        "native/stage_temperature_probes_50samples.csv",
    ]
    evidence = evidence_summary(arm, required)
    raw = arm / "native" / V45_RAW_NAME
    raw_candidates = [summarize_binary(raw)] if raw.exists() else []
    compact_ok = all(item.get("present") for item in evidence.values())
    return {
        "relative_path": relative(arm, root),
        "required_evidence_complete": compact_ok,
        "evidence": evidence,
        "raw_candidates": raw_candidates,
    }


def write_group(name: str, root: Path) -> Dict[str, Any]:
    if name in {"v64c1", "v65c1"}:
        arms = [packet_summary(path, root) for path in sorted(root.glob("packet_*")) if path.is_dir()]
        candidate_files = [
            path
            for path in root.rglob("*")
            if path.is_file() and path.name in TRAJECTORY_NAMES
        ]
    else:
        arms = [v45_arm_summary(path, root) for path in sorted(root.iterdir()) if path.is_dir()]
        candidate_files = [
            path
            for path in root.glob("*/native/observations.mat")
            if path.is_file()
        ]

    scan = reference_scan(name)
    process_snapshot = tasklist_matlab()
    compact_ok = all(arm["required_evidence_complete"] for arm in arms)
    parse_ok = all(
        not item.get("summary", {}).get("parse_error")
        for arm in arms
        for item in arm.get("evidence", {}).values()
        if item.get("present") and item.get("summary")
    )
    coverage_pass = bool(
        arms
        and compact_ok
        and parse_ok
        and not scan["direct_script_references_outside_audit"]
        and not process_snapshot
        and all(path.exists() for path in candidate_files)
    )
    result = {
        "schema": "heatdrive_ecc_compact_replacement_v1",
        "generated_utc": utc_now(),
        "target": name,
        "root": str(root),
        "read_only_before_delete": True,
        "matlab_simulink_processes": process_snapshot,
        "reference_scan": scan,
        "arms": arms,
        "raw_candidates": [summarize_binary(path) for path in candidate_files],
        "coverage": {
            "required_evidence_complete": compact_ok,
            "all_evidence_parseable": parse_ok,
            "raw_hashes_recorded": all("sha256" in item for item in [summarize_binary(path) for path in candidate_files]),
            "coverage_pass": coverage_pass,
        },
        "deletion_performed": False,
        "scientific_gates_changed": False,
        "protected_groups_touched": [],
        "decision": "eligible_for_exact_raw_retirement" if coverage_pass else "manual_confirmation_required",
    }
    out_dir = OUTPUT_ROOT / name
    out_dir.mkdir(parents=True, exist_ok=True)
    json_dump(out_dir / "compact_replacement.json", result)

    rows: List[Dict[str, Any]] = []
    for arm in arms:
        for raw in arm.get("raw_candidates", []):
            rows.append(
                {
                    "arm": arm["relative_path"],
                    "raw_path": raw["path"],
                    "raw_bytes": raw["bytes"],
                    "raw_sha256": raw["sha256"],
                    "required_evidence_complete": arm["required_evidence_complete"],
                    "coverage_pass": coverage_pass,
                }
            )
    with (out_dir / "compact_replacement.csv").open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0].keys()) if rows else ["raw_path"])
        writer.writeheader()
        writer.writerows(rows)

    manifest = {
        "schema": "heatdrive_ecc_compact_replacement_manifest_v1",
        "generated_utc": utc_now(),
        "target": name,
        "source_summary": str(out_dir / "compact_replacement.json"),
        "source_csv": str(out_dir / "compact_replacement.csv"),
        "raw_candidate_count": len(candidate_files),
        "raw_candidate_bytes": sum(path.stat().st_size for path in candidate_files),
        "deletion_allowed_only_if_coverage_pass": True,
        "protected_paths": ["C200", "v43_storage_warmup_from_C42_r1", "C020 representative results", "Agent6"],
    }
    json_dump(out_dir / "compact_replacement_manifest.json", manifest)
    return result


def write_hash_receipt() -> None:
    lines: List[str] = []
    for path in sorted(OUTPUT_ROOT.rglob("*")):
        if path.is_file() and path.name != "sha256sums.txt":
            lines.append(f"{sha256_file(path)}  {path.relative_to(OUTPUT_ROOT)}")
    (OUTPUT_ROOT / "sha256sums.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")


def delete_after_review() -> Dict[str, Any]:
    receipts: List[Dict[str, Any]] = []
    total_bytes = 0
    deleted = 0
    for name in TARGETS:
        summary_path = OUTPUT_ROOT / name / "compact_replacement.json"
        if not summary_path.exists():
            raise RuntimeError(f"Missing read-only compact summary: {summary_path}")
        summary = json.loads(summary_path.read_text(encoding="utf-8"))
        if not summary["coverage"]["coverage_pass"]:
            raise RuntimeError(f"Coverage not passed for {name}; no deletion permitted")
        if summary["matlab_simulink_processes"]:
            raise RuntimeError(f"MATLAB/Simulink active for {name}")
        for candidate in summary["raw_candidates"]:
            path = Path(candidate["path"])
            if not path.exists() or sha256_file(path) != candidate["sha256"]:
                raise RuntimeError(f"Raw file changed or missing: {path}")
            if path.is_symlink():
                raise RuntimeError(f"Refusing symlink target: {path}")
        for candidate in summary["raw_candidates"]:
            path = Path(candidate["path"])
            size = path.stat().st_size
            os.remove(path)
            if path.exists():
                raise RuntimeError(f"Deletion postcheck failed: {path}")
            deleted += 1
            total_bytes += size
            receipts.append(
                {
                    "path": str(path),
                    "bytes": size,
                    "sha256": candidate["sha256"],
                    "replacement": str(summary_path),
                }
            )
    receipt = {
        "schema": "heatdrive_ecc_compact_replacement_execution_receipt_v1",
        "status": "completed",
        "generated_utc": utc_now(),
        "deleted_file_count": deleted,
        "reclaimed_bytes": total_bytes,
        "reclaimed_gib": round(total_bytes / (1024**3), 6),
        "deleted_files": receipts,
        "matlab_simulink_started_or_interrupted": False,
        "scientific_gates_changed": False,
        "C200_touched": False,
        "v43_touched": False,
        "C020_touched": False,
        "Agent6_touched": False,
        "model_or_code_deleted": False,
    }
    json_dump(OUTPUT_ROOT / "compact_replacement_execution_receipt.json", receipt)
    write_hash_receipt()
    return receipt


def write_postcheck() -> Dict[str, Any]:
    receipt_path = OUTPUT_ROOT / "compact_replacement_execution_receipt.json"
    if not receipt_path.exists():
        raise RuntimeError(f"Missing execution receipt: {receipt_path}")
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    deleted = receipt.get("deleted_files", [])
    missing_deleted_paths = [item["path"] for item in deleted if Path(item["path"]).exists()]
    missing_replacements = [
        item["replacement"] for item in deleted if not Path(item["replacement"]).exists()
    ]
    postcheck = {
        "schema": "heatdrive_ecc_compact_replacement_postcheck_v1",
        "generated_utc": utc_now(),
        "deleted_file_count": receipt.get("deleted_file_count", 0),
        "reclaimed_bytes": receipt.get("reclaimed_bytes", 0),
        "deleted_paths_still_present": missing_deleted_paths,
        "replacement_files_missing": missing_replacements,
        "matlab_simulink_processes": tasklist_matlab(),
        "protected_paths_touched": [],
        "scientific_gates_changed": False,
        "postcheck_pass": bool(
            not missing_deleted_paths
            and not missing_replacements
            and not tasklist_matlab()
        ),
    }
    json_dump(OUTPUT_ROOT / "compact_replacement_postcheck.json", postcheck)
    write_hash_receipt()
    return postcheck


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--delete", action="store_true", help="delete only prior-pass raw candidates")
    parser.add_argument("--postcheck", action="store_true", help="verify a completed exact deletion")
    args = parser.parse_args()
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    if args.postcheck:
        postcheck = write_postcheck()
        print(json.dumps(postcheck, ensure_ascii=True, indent=2))
        return 0
    if args.delete:
        receipt = delete_after_review()
        print(json.dumps(receipt, ensure_ascii=True, indent=2))
        return 0
    results = [write_group(name, root) for name, root in TARGETS.items()]
    write_hash_receipt()
    print(
        json.dumps(
            {
                "schema": "heatdrive_ecc_compact_replacement_audit_v1",
                "generated_utc": utc_now(),
                "delete_performed": False,
                "targets": [
                    {
                        "target": result["target"],
                        "coverage_pass": result["coverage"]["coverage_pass"],
                        "raw_candidate_count": len(result["raw_candidates"]),
                        "raw_candidate_bytes": sum(item["bytes"] for item in result["raw_candidates"]),
                        "decision": result["decision"],
                    }
                    for result in results
                ],
            },
            ensure_ascii=True,
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
