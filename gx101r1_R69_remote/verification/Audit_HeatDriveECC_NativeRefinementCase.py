"""Gate a restricted 0.3 s solver-step diagnostic, never a production restart."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_NativeWindowLedger import NativeWindowLedger
from Audit_HeatDriveECC_NativeWindowPackets import load_packet
from Audit_HeatDriveECC_SegmentedEvidence import compare, load_traces, sha256, text_field


def initial_states_equal(reference, observed, start, stop):
    if reference.keys() != observed.keys():
        raise ValueError("Observed state inventory changed")
    count = 0
    grids = {}
    for key, other in observed.items():
        base = reference[key]
        time, values = other["time"], other["values"]
        if (base["unit"] != other["unit"] or values.ndim != 2 or values.shape[1] != base["values"].shape[1]
                or len(time) < 2 or not np.isfinite(time).all() or not np.isfinite(values).all()
                or abs(time[0] - start) > 16 * np.spacing(stop) or abs(time[-1] - stop) > 16 * np.spacing(stop)
                or np.any(np.diff(time) <= 0)):
            raise ValueError("Incomplete state history; do not interpolate it")
        if not np.array_equal(base["values"][0].view(np.uint64), values[0].view(np.uint64)):
            raise ValueError("The refined run changed a saved initial state")
        count += values.shape[1]
        grids[str(len(time))] = grids.get(str(len(time)), 0) + 1
    return dict(initial_state_bits_equal=True, coordinate_count=count, state_group_sample_counts=grids,
                original_multirate_time_axes_preserved=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case-file", type=Path, required=True)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Do not overwrite refinement evidence")
    audit = args.repo / "outputs_storage_audit"
    pilot = args.repo / "outputs/qian_native_inventory_pilot_from_c180_20260906/cycle_181"
    paths = {"topology": audit / "tl_domain_energy_tables_20260906/tl_domain_metadata.json",
             "probe": audit / "native_inventory_port_comparison_20260906/native_inventory_probe.json",
             "metadata": audit / "native_inventory_model_metadata_20260906/storage_model_metadata.json"}
    ledger = NativeWindowLedger(*(json.loads(p.read_text(encoding="utf-8-sig")) for p in paths.values()))
    previous = json.loads((pilot / "native_ledger.json").read_text(encoding="utf-8-sig"))
    packet_hash = sha256(pilot / "native_window.mat")
    if packet_hash != previous["packet_sha256"]:
        raise ValueError("Original pilot packet changed")
    for key, path in paths.items():
        if sha256(path) != previous["input_sha256"][key]:
            raise ValueError("Original metadata changed")
    header, original = load_packet(pilot / "native_window.mat")
    with h5py.File(args.case_file, "r") as file:
        meta = json.loads(text_field(file["record_json"]))
        native, observed = (load_traces(file, "traces", stream) for stream in ("native", "observed"))
    if (meta["schema"] != "heatdrive_ecc_native_refinement_case_v1" or not meta["strict_restore_pass"]
            or meta["production_recovery_allowed"] or meta["start_s"] != 1800 or meta["stop_s"] != 1800.3
            or meta["solver_step_s"] not in (.001, .0005, .00025)
            or meta["configured_constitutive_sample_time_s"] != .001
            or any(meta[key] != value or header[key] != value for key, value in ledger.source.items())):
        raise ValueError("Diagnostic protocol or frozen source changed")
    if len(observed) != 73 or sum(r["values"].shape[1] for r in observed.values()) != 1376:
        raise ValueError("Incomplete observed state inventory")
    initial = initial_states_equal(original["observed"], observed, meta["start_s"], meta["stop_s"])
    reference_comparisons = None
    if meta["solver_step_s"] == .001:
        reference_comparisons = {stream: compare(original[stream], rows, meta["start_s"], meta["stop_s"], .001)
                                 for stream, rows in (("native", native), ("observed", observed))}
        if not all(r["float64_bits_identical"] for r in reference_comparisons.values()):
            raise ValueError("Nominal prefix differs from actual C181; do not proceed to refinement")
    result = ledger.evaluate(native, meta["start_s"], meta["stop_s"], meta["solver_step_s"])
    result.update(schema="heatdrive_ecc_native_refinement_case_audit_v1", case=meta,
                  initial_observed=initial, original_prefix_comparisons=reference_comparisons,
                  diagnostic_case_pass=True, case_file_sha256=sha256(args.case_file),
                  original_pilot_packet_sha256=packet_hash,
                  full_cycle_mechanism_gate_evaluated=False, temporal_convergence_verified=False,
                  scope="0.3 s same-state continuous solver refinement, discrete constitutive sample time unchanged")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k not in ("components", "case")}, indent=2))


if __name__ == "__main__":
    main()
