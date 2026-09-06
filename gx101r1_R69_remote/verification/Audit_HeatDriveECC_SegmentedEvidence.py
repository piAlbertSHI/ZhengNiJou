"""Independently recompute strict split-trace equality from saved MATLAB data."""
import argparse
import hashlib
import json
from pathlib import Path

import h5py
import numpy as np


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def text_field(dataset):
    if bool(dataset.attrs.get("MATLAB_empty", 0)):
        return ""
    if dataset.dtype != np.dtype("uint16"):
        raise ValueError("Expected a MATLAB UTF-16 char field")
    return dataset[:].reshape(-1).astype("<u2").tobytes().decode("utf-16le")


def load_traces(file, part, stream):
    result = {}
    for reference in file[f"{part}/{stream}"][:].reshape(-1):
        row = file[reference]
        path, name = text_field(row["block_path"]), text_field(row["state_name"])
        key = path + "::" + name
        if key in result:
            raise ValueError("Duplicate named trace")
        t = row["time_s"][:].reshape(-1)
        values = row["values"][:].T
        channels = int(row["channel_count"][0, 0])
        if values.shape != (t.size, channels) or values.dtype != np.dtype("float64"):
            raise ValueError("Invalid native trace shape or numeric representation")
        result[key] = dict(time=t, values=values, unit=text_field(row["unit"]), block_path=path)
    return result


def compare(reference, candidate, start, stop, dt):
    if not reference or reference.keys() != candidate.keys():
        raise ValueError("Trace inventories differ")
    expected = int(round((stop - start) / dt)) + 1
    tolerance = 16 * np.spacing(stop)
    max_abs, bitwise, channels, points = 0.0, True, 0, 0
    for key, other in candidate.items():
        base = reference[key]
        t = other["time"]
        if (t.size != expected or not np.isfinite(t).all() or abs(t[0] - start) > tolerance
                or abs(t[-1] - stop) > tolerance or np.any(abs(np.diff(t) - dt) > tolerance)):
            raise ValueError("Candidate grid or endpoint mismatch")
        selected = (base["time"] >= start - tolerance) & (base["time"] <= stop + tolerance)
        base_time = base["time"][selected]
        if base_time.shape != t.shape or np.any(abs(base_time - t) > tolerance):
            raise ValueError("Reference grid mismatch; interpolation is forbidden")
        a, b = base["values"][selected], other["values"]
        if base["unit"] != other["unit"] or a.shape != b.shape or not np.isfinite([a, b]).all():
            raise ValueError("Trace units, shape, or finite-value check failed")
        max_abs = max(max_abs, float(np.max(abs(a - b))))
        bitwise = bitwise and np.array_equal(a.view(np.uint64), b.view(np.uint64))
        channels += a.shape[1]
        points += a.size
    return dict(trace_count=len(candidate), coordinate_count=channels, scalar_comparisons=points,
                sample_count=expected, max_abs_difference=max_abs, float64_bits_identical=bool(bitwise))


def audit(root, execution_commit):
    summary_path = root / "segmented_inventory_restore.json"
    summary = json.loads(summary_path.read_text(encoding="utf-8-sig"))
    if (summary["schema"] != "heatdrive_ecc_segmented_inventory_restore_v1"
            or not summary["segmentation_equivalence_pass"] or not summary["collection_pass"]
            or summary["production_recovery_allowed"] or len(summary["cases"]) != 2):
        raise ValueError("Require completed non-production split experiment")
    hashes = {summary_path.name: sha256(summary_path)}
    comparisons = []
    for index, case in enumerate(summary["cases"], 1):
        path = root / f"case_{index}_traces.mat"
        hashes[path.name] = sha256(path)
        with h5py.File(path, "r") as file:
            for stream, expected_traces, expected_coordinates in (("observed", 73, 1376), ("native", 1240, 1240)):
                reference = load_traces(file, "reference", stream)
                if stream == "native" and len({r["block_path"] for r in reference.values()}) != 119:
                    raise ValueError("Incomplete native component coverage")
                for part, start, stop in (("prefix", case["start_s"], case["split_s"]),
                                          ("suffix", case["split_s"], case["end_s"])):
                    result = compare(reference, load_traces(file, part, stream), start, stop, summary["fixed_step_s"])
                    if result["trace_count"] != expected_traces or result["coordinate_count"] != expected_coordinates:
                        raise ValueError("Unexpected observed or native coordinate inventory")
                    result.update(case=case["kind"], part=part, stream=stream, start_s=start, stop_s=stop)
                    comparisons.append(result)
        path = root / f"case_{index}_DO_NOT_RESUME_FOR_PRODUCTION.mat"
        hashes[path.name] = sha256(path)
        with h5py.File(path, "r") as file:
            if "diagnostic_op" not in file or bool(file["production_recovery_allowed"][0, 0]):
                raise ValueError("Diagnostic OP has unauthorized scope")
    passed = all(r["float64_bits_identical"] and r["max_abs_difference"] == 0 for r in comparisons)
    return dict(schema="heatdrive_ecc_independent_split_evidence_v1", source_commit=execution_commit,
                execution_commit_supplied_from_run_record=True,
                independent_mat_recalculation_pass=passed, comparisons=comparisons, input_sha256=hashes,
                scalar_comparisons=sum(r["scalar_comparisons"] for r in comparisons),
                original_matlab_equality_used_isequal=True,
                independent_check_compares_float64_bit_patterns=True,
                scope="Two six-millisecond windows including their split samples, not whole-cycle trajectory or periodicity proof",
                production_recovery_allowed=False, multi_cycle_energy_closure_verified=False,
                full_internal_state_periodicity_verified=False, table4_reproduction_claim=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--execution-commit", required=True,
                        help="Recorded execution commit; this offline audit does not infer execution provenance")
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Do not overwrite independent evidence")
    result = audit(args.root, args.execution_commit)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k not in ("comparisons", "input_sha256")}, indent=2))
    if not result["independent_mat_recalculation_pass"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
