"""Read compact native packets and independently verify lossless real-data packing."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_NativeWindowLedger import validate_grid
from Audit_HeatDriveECC_SegmentedEvidence import audit as audit_split, load_traces, sha256, text_field


def unpack_columns(time, matrix, columns):
    if (matrix.dtype != np.dtype("float64") or matrix.ndim != 2 or matrix.shape[0] != len(time)
            or not np.isfinite(matrix).all()):
        raise ValueError("Invalid compact value matrix")
    result, next_column = {}, 1
    for column in columns:
        start, count = column["first_column_1based"], column["channel_count"]
        if (not isinstance(start, int) or not isinstance(count, int) or start != next_column
                or count < 1 or start - 1 + count > matrix.shape[1]):
            raise ValueError("Noncontiguous, overlapping or invalid column descriptor")
        if any(not isinstance(column[k], str) for k in ("block_path", "state_name", "unit")):
            raise ValueError("Invalid trace descriptor text")
        key = column["block_path"] + "::" + column["state_name"]
        if key in result:
            raise ValueError("Duplicate compact trace")
        result[key] = dict(time=time, values=matrix[:, start - 1:start - 1 + count],
                           block_path=column["block_path"], unit=column["unit"])
        next_column += count
    if next_column != matrix.shape[1] + 1:
        raise ValueError("Unassigned compact value columns")
    return result


def load_packet(path):
    with h5py.File(path, "r") as file:
        if set(file.keys()) != {"header_json", "time_s", "native_values", "observed_values"}:
            raise ValueError("Unexpected packet fields; OP/model/legacy data are forbidden")
        header = json.loads(text_field(file["header_json"]))
        if (header["schema"] != "heatdrive_ecc_native_window_samples_v1"
                or not header["storage_only_no_operating_point"] or header["production_recovery_allowed"]
                or header["strict_restore_verified_by_writer"] or header["full_internal_periodicity_verified"]
                or header["equation_matched_cycle_closure_verified"]):
            raise ValueError("Invalid packet version or overstated authority")
        time = file["time_s"][:].reshape(-1)
        validate_grid(time, header["start_s"], header["stop_s"], header["fixed_step_s"])
        if time.dtype != np.dtype("float64") or len(time) != header["sample_count"]:
            raise ValueError("Invalid compact time representation")
        streams = {stream: unpack_columns(time, file[stream + "_values"][:].T, header[stream + "_columns"])
                   for stream in ("native", "observed")}
    for stream, groups, coordinates in (("native", 1240, 1240), ("observed", 73, 1376)):
        rows = streams[stream]
        if (len(rows) != groups or sum(r["values"].shape[1] for r in rows.values()) != coordinates
                or header[stream + "_coordinate_count"] != coordinates):
            raise ValueError("Unexpected compact state inventory")
    if len({r["block_path"] for r in streams["native"].values()}) != 119 or header["native_component_count"] != 119:
        raise ValueError("Unexpected compact component inventory")
    return header, streams


def exact_match(original, packed):
    if original.keys() != packed.keys():
        raise ValueError("Packed and original inventories differ")
    count = 0
    for key, row in original.items():
        other = packed[key]
        if row["unit"] != other["unit"] or row["block_path"] != other["block_path"]:
            raise ValueError("Packed descriptor changed")
        for field in ("time", "values"):
            a, b = row[field], other[field]
            if (a.dtype != np.dtype("float64") or b.dtype != np.dtype("float64")
                    or a.shape != b.shape or not np.isfinite(a).all()
                    or not np.array_equal(a.view(np.uint64), b.view(np.uint64))):
                raise ValueError("Lossless bit-pattern comparison failed")
        count += row["values"].size
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packet-root", type=Path, required=True)
    parser.add_argument("--split-root", type=Path, required=True)
    parser.add_argument("--execution-commit", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Do not overwrite packing evidence")
    source = audit_split(args.split_root, args.execution_commit)
    if not source["independent_mat_recalculation_pass"]:
        raise ValueError("Original split experiment failed")
    summary = json.loads((args.split_root / "segmented_inventory_restore.json").read_text(encoding="utf-8-sig"))
    rows = []
    for index, case in enumerate(summary["cases"], 1):
        with h5py.File(args.split_root / f"case_{index}_traces.mat", "r") as original:
            for part in ("reference", "prefix", "suffix"):
                path = args.packet_root / f"case_{index}_{part}.mat"
                header, streams = load_packet(path)
                for key in ("source_result_sha256", "source_checkpoint_sha256"):
                    if header[key] != summary[key]:
                        raise ValueError("Compact packet source mismatch")
                start = case["split_s"] if part == "suffix" else case["start_s"]
                stop = case["split_s"] if part == "prefix" else case["end_s"]
                if (header["start_s"] != start or header["stop_s"] != stop
                        or header["fixed_step_s"] != summary["fixed_step_s"]
                        or header["cycle_period_s"] != summary["cycle_period_s"]):
                    raise ValueError("Compact window differs from the experiment")
                count = sum(exact_match(load_traces(original, part, stream), streams[stream])
                            for stream in ("native", "observed"))
                rows.append(dict(path=str(path.resolve()), sha256=sha256(path), bytes=path.stat().st_size,
                                 scalar_value_comparisons=count, float64_bits_identical=True))
    result = dict(schema="heatdrive_ecc_native_packet_lossless_audit_v1", lossless_packing_pass=True,
                  packet_count=len(rows), packets=rows, packet_total_bytes=sum(r["bytes"] for r in rows),
                  scalar_value_comparisons=sum(r["scalar_value_comparisons"] for r in rows),
                  source_input_sha256=source["input_sha256"], source_execution_commit=args.execution_commit,
                  comparison_includes_time_bits=True, simulation_run=False, production_recovery_allowed=False,
                  full_internal_periodicity_verified=False, equation_matched_cycle_closure_verified=False)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k not in ("packets", "source_input_sha256")}, indent=2))


if __name__ == "__main__":
    main()
