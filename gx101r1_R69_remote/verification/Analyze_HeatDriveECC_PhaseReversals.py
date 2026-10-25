"""Sampled material reversals in sealed same-contract C1 operator controls.

No continuous event times, memory law, material identification or causal system
error attribution are inferred from selected observations.
"""
import argparse
import json
from pathlib import Path

import numpy as np

from Analyze_HeatDriveECC_CaloricCycle import read_packet
from Analyze_HeatDriveECC_PhaseOperator import check_ablation_contract, verify_shared_operator_source
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Run_HeatDriveECC_ConservativeTransport import write_json


def sampled_turns(clock, phase, tolerance):
    if (clock.ndim != 1 or phase.shape != clock.shape or np.any(np.diff(clock) <= 0)
            or not np.isfinite(np.r_[clock, phase]).all() or not tolerance > 0):
        raise ValueError("Require ordered finite selected samples and positive diagnostic tolerance")
    difference = np.diff(phase)
    indices = np.flatnonzero(abs(difference) > tolerance)
    events = []
    for previous, current in zip(indices[:-1], indices[1:]):
        if np.sign(difference[previous]) != np.sign(difference[current]):
            events.append({"time_bracket_s": [float(clock[previous+1]), float(clock[current])],
                "selected_turn_phase": float(phase[current]),
                "direction_before": int(np.sign(difference[previous])),
                "direction_after": int(np.sign(difference[current]))})
    return events


def review(first, second):
    a, ma, ta, ya, _ = read_packet(first)
    b, mb, tb, yb, _ = read_packet(second)
    check_ablation_contract(a["network_contract"], b["network_contract"])
    scope = verify_shared_operator_source(b)
    if a["cycles"] != 1 or b["cycles"] != 1 or not np.array_equal(ta, tb):
        raise ValueError("Require same-clock C1 controls, not differently sampled long chains")
    packets = []
    for root, record, model, states in ((first, a, ma, ya), (second, b, mb, yb)):
        scans = []
        for tolerance in (1e-9, 1e-8, 1e-7, 1e-6, 1e-5):
            fields = {}
            for name in ("phase_a", "phase_r"):
                x = states[:, model.slices[name]]
                events = [sampled_turns(ta, x[:, j], tolerance) for j in range(model.n)]
                counts = [len(v) for v in events]
                fields[name] = {"count_range": [min(counts), max(counts)],
                    "nodes_with_more_than_one_turn_1_based": [j+1 for j, n in enumerate(counts) if n > 1]}
                if tolerance == 1e-5:
                    fields[name]["events_by_node"] = events
            scans.append({"phase_increment_tolerance": tolerance, "fields": fields})
        packets.append({"root": str(root), "execution_sha256": sha256(root/"caloric_cycle_execution.json"),
            "raw_sha256": record["raw"]["sha256"], "observations": len(ta), "scans": scans})
    return {"schema": "heatdrive_ecc_sampled_phase_reversal_control_v1", "reader_sha256": sha256(Path(__file__)),
        "source_scope": scope, "controls": packets,
        "tolerance_scan_is_not_a_scientific_gate": True,
        "continuous_event_times_or_rates_identified": False,
        "memory_law_implemented_or_calibrated": False,
        "source_2019_PC_memory_approach_is_not_claimed_Q01_code": True,
        "mechanism_or_periodicity_promoted": False,
        "interpretation": "retained observations support prioritizing path-dependent material closure; no claim that missing memory alone explains Table4 error"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--first", type=Path, required=True)
    parser.add_argument("--second", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError(args.output)
    result = review(args.first.resolve(), args.second.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    write_json(args.output, result)
    print(json.dumps({"output": str(args.output), "sha256": sha256(args.output),
        "ranges": [p["scans"][-1]["fields"]["phase_r"]["count_range"] for p in result["controls"]]}))
