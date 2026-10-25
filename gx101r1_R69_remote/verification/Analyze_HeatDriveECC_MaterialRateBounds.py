"""Integral bounds from Q01 Eq3 and registered component-figure pixel boxes.

For falling x: integral(pMA) >= log(x1/x2). For rising x:
integral(pAM) >= log((1-x1)/(1-x2)). Opposing microscopic fluxes are
nonnegative; no one-way-stage or instantaneous finite-difference assumption.
Bounds are conditional on the retained metrology boxes, not full uncertainty.
"""
import argparse
import json
from pathlib import Path

import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Run_HeatDriveECC_ConservativeTransport import write_json


def interval_bound(first, second, time_uncertainty, direction):
    low1, high1 = first["pixel_ordinate_extent_plus_one"]
    low2, high2 = second["pixel_ordinate_extent_plus_one"]
    dt = second["image_time_s"]-first["image_time_s"]+2*time_uncertainty
    if not (0 < low1 <= high1 < 1 and 0 < low2 <= high2 < 1 and dt > 0):
        raise ValueError("Require interior phase boxes and increasing times")
    if direction == "M_to_A":
        ratio = low1/high2
    elif direction == "A_to_M":
        ratio = (1-high1)/(1-low2)
    else:
        raise ValueError("Unknown phase direction")
    lower = max(0., float(np.log(ratio)))
    return {"selected_times_s": [first["image_time_s"], second["image_time_s"]],
        "conservative_duration_upper_s": dt, "integrated_coefficient_lower_bound": lower,
        "interval_average_coefficient_lower_bound_per_s": lower/dt,
        "direction": direction}


def review(source):
    record = json.loads(source.read_text(encoding="utf-8"))
    phase = next(row for row in record["traces"] if row["quantity"] == "SMA_xM")
    intervals = []
    for cycle in (1, 2):
        for direction, start, end in (("M_to_A", .5, 1.4), ("A_to_M", 6.1, 8.4)):
            points = [r for r in phase["measured"] if r["cycle"] == cycle
                      and start <= r["image_time_s"]-(cycle-1)*10 <= end]
            for i, first in enumerate(points):
                for second in points[i+1:]:
                    row = interval_bound(first, second, phase["one_pixel_time_s"], direction)
                    if row["integrated_coefficient_lower_bound"]:
                        intervals.append(dict(row, cycle=cycle))
    if not intervals:
        raise ValueError("No positive conditional integral constraints")
    strongest = {name: max((row for row in intervals if row["direction"] == name),
                          key=lambda r: r["interval_average_coefficient_lower_bound_per_s"])
                 for name in ("M_to_A", "A_to_M")}
    return {"schema": "heatdrive_ecc_component_integral_rate_bounds_v1", "reader_sha256": sha256(Path(__file__)),
        "source_pixel_record": str(source), "source_pixel_record_sha256": sha256(source),
        "equation": "Q01 Eq3 two nonnegative fluxes; integrated logarithmic inequality",
        "intervals": intervals, "strongest_interval_average_bounds": strongest,
        "scope": "conditional on source-pixel boxes and curve identity; Table2 simulated SMA, not Table4 or experiments",
        "instantaneous_rates_identified": False, "activation_volume_or_tau_identified": False,
        "opposing_flux_set_to_zero": False, "new_scientific_gate": False,
        "material_or_Table4_reproduction_claim": False}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pixels", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError(args.output)
    result = review(args.pixels.resolve())
    write_json(args.output, result)
    print(json.dumps({"sha256": sha256(args.output), "intervals": len(result["intervals"]),
                      "strongest": result["strongest_interval_average_bounds"]}))
