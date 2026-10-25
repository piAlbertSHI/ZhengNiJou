"""Guided pixel metrology of the Q01 Fig3/Fig4 actuator traces.

Guides select the curve, never supply measured ordinates. Ambiguous ridges,
legend/annotations and shared chart-frame plateaus are explicitly left missing.
These published simulated component paths use Table2, not the Table4 prototype.
"""
import argparse
from collections import Counter
import json
from pathlib import Path

import fitz
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Run_HeatDriveECC_ConservativeTransport import write_json


Q01_SHA = "2D0EB5F84AA515BA651638974414D426A3806FD417A1EAD96EFA36EDA08034CC"
GUIDES = {
    "phase": np.array([[.45, 1.], [.5, .96], [.6, .87], [.7, .76], [.8, .63], [.9, .49],
        [1., .32], [1.1, .16], [1.2, .076], [1.3, .023], [1.4, 0.], [6.1, 0.],
        [6.2, .05], [6.5, .19], [6.8, .366], [7., .459], [7.2, .567], [7.4, .668],
        [7.6, .759], [7.8, .857], [8., .93], [8.2, .98], [8.4, 1.]]),
    "temperature": np.array([[0., 32.], [.2, 36.], [.5, 50.], [.8, 63.], [1., 69.], [1.3, 83.],
        [1.8, 96.], [2.5, 109.], [3.5, 117.], [4.5, 120.], [5., 120.], [5.25, 107.],
        [5.5, 90.], [6., 70.], [6.5, 57.], [7., 50.], [8., 43.], [8.5, 39.],
        [9., 35.], [9.5, 33.], [10., 32.]])}


def pixel_group(values, max_vertical_pixels=14):
    """Only an unambiguous contiguous dark ridge is returned."""
    if len(values) == 0:
        return None, "no_dark_pixels"
    groups = np.split(values, np.flatnonzero(np.diff(values) > 1)+1)
    if len(groups) != 1:
        return None, "multiple_dark_ridges"
    if len(groups[0]) > max_vertical_pixels:
        return None, "vertical_stroke_or_unresolved_crossing"
    return groups[0], None


def extract_trace(image, kind):
    height, width, _ = image.shape
    if kind == "phase":
        if (width, height) != (1541, 805):
            raise ValueError("Unregistered phase image")
        x0, x20, yzero, ytop, ordinate_top, strip = 137., 1522., 690., 76., 1., .065
    elif kind == "temperature":
        if (width, height) != (1541, 735):
            raise ValueError("Unregistered temperature image")
        x0, x20, yzero, ytop, ordinate_top, strip = 131., 1515., 617., 77., 150., 5.
    else:
        raise ValueError("Unknown source trace")
    dark = (image.max(axis=2) < 135) & (np.ptp(image.astype(int), axis=2) < 30)
    ordinate = (yzero-np.arange(height))*ordinate_top/(yzero-ytop)
    measured, missing = [], []
    guide = GUIDES[kind]
    guide_derivative = np.gradient(guide[:, 1], guide[:, 0])
    for requested in np.arange(.1, 20., .1):
        clock = float(round(requested, 10))
        cycle = 1 if clock < 10. else 2
        local = clock-(cycle-1)*10
        reason = None
        annotation_times = (0., 3.5, 5., 8.5, 10.) if kind == "temperature" else (0., .5, 1.4, 3.5, 5., 6.1, 8., 8.5, 10.)
        if min(abs(local-v) for v in annotation_times) < .075:
            reason = "stage_annotation_column"
        if kind == "phase":
            if not (.5 <= local <= 1.35 or 6.2 <= local <= 8.15):
                reason = "plateau_or_chart_frame_not_independent_measurement"
            if .75 <= local <= 1.05 or 6.75 <= local <= 7.05 or 7.25 <= local <= 7.6:
                reason = "SE_trace_crossing_or_unresolved_curve_identity"
        expected = float(np.interp(local, guide[:, 0], guide[:, 1]))
        if kind == "phase" and cycle == 2 and 11.35 <= clock <= 19.75 and expected > .70:
            reason = "legend_overlay"
        if reason:
            missing.append({"requested_time_s": clock, "reason": reason})
            continue
        column = int(round(x0+clock*(x20-x0)/20))
        candidates = np.flatnonzero(dark[:, column] & (abs(ordinate-expected) < strip))
        dy_dx = abs(float(np.interp(local, guide[:, 0], guide_derivative)))*(yzero-ytop)/ordinate_top*20/(x20-x0)
        max_stroke = int(np.ceil(7*np.sqrt(1+dy_dx*dy_dx)))+2
        selected, reason = pixel_group(candidates, max_stroke)
        if reason:
            missing.append({"requested_time_s": clock, "reason": reason})
            continue
        row = float(np.median(selected))
        actual = (yzero-row)*ordinate_top/(yzero-ytop)
        low = (yzero-float(selected[-1])-1)*ordinate_top/(yzero-ytop)
        high = (yzero-float(selected[0])+1)*ordinate_top/(yzero-ytop)
        measured.append({"requested_time_s": clock, "image_time_s": float((column-x0)*20/(x20-x0)),
            "value": float(actual), "pixel_ordinate_extent_plus_one": [float(low), float(high)],
            "pixel_x": column, "pixel_y_median": row, "dark_pixel_count": len(selected),
            "slope_aware_vertical_stroke_limit_pixels": max_stroke,
            "cycle": cycle})
    if len(measured) < (10 if kind == "phase" else 100):
        raise ValueError("Insufficient separable source pixels for "+kind+": "+str(len(measured))+
                         "; missing="+str(dict(Counter(r["reason"] for r in missing))))
    return {"quantity": "SMA_xM" if kind == "phase" else "SMA_temperature_C",
        "source_figure": 3 if kind == "phase" else 4,
        "axes_pixels_x0_x20_y0_ytop": [x0, x20, yzero, ytop], "axis_ordinate_top": ordinate_top,
        "one_pixel_time_s": 20/(x20-x0), "one_pixel_ordinate": ordinate_top/(yzero-ytop),
        "guide_half_width": strip, "guide_points_are_not_measurements": True,
        "stroke_selection": "7-pixel normal width rotated by guide slope, plus 2-pixel allowance; not data smoothing",
        "guide_for_curve_identity": guide.tolist(), "measured": measured, "missing": missing,
        "uncertainty_scope": "pixel stroke extent plus 1 pixel only; axis registration/curve identity/systematic figure errors remain",
        "missing_points_interpolated": False}


def extract(pdf, output):
    if sha256(pdf) != Q01_SHA:
        raise ValueError("Wrong primary Q01 bytes")
    output.mkdir(parents=True, exist_ok=False)
    document = fitz.open(pdf)
    page = document[6]
    images = page.get_images(full=True)
    results, pixels = [], []
    for kind, expected in (("phase", (1541, 805)), ("temperature", (1541, 735))):
        matches = [r for r in images if tuple(r[2:4]) == expected]
        if len(matches) != 1:
            raise ValueError("Ambiguous material figure")
        pixmap = fitz.Pixmap(document, matches[0][0])
        image = np.frombuffer(pixmap.samples, dtype=np.uint8).reshape(pixmap.height, pixmap.width, pixmap.n)
        if pixmap.n != 3:
            raise ValueError("Unregistered image colors")
        pixels.append(image)
        results.append(extract_trace(image, kind))
    record = {"schema": "heatdrive_ecc_Q01_component_pixel_paths_v1", "source": str(pdf),
        "source_sha256": Q01_SHA, "reader_sha256": sha256(Path(__file__)), "PDF_page": 7,
        "scope": "published simulated Table2 component trajectories, NOT Table4 or material experiments",
        "new_material_parameters_identified": False, "Table4_endpoints_used_for_calibration": False,
        "continuous_phase_rates_inferred": False, "Q01_simulation_code_obtained": False,
        "traces": results}
    write_json(output/"Q01_material_pixel_paths.json", record)
    # Source-pixel overlays are for metrology QA, not new system performance plots.
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(2, 1, figsize=(11, 10), layout="constrained")
    for ax, image, result in zip(axes, pixels, results):
        ax.imshow(image)
        points = result["measured"]
        ax.scatter([r["pixel_x"] for r in points], [r["pixel_y_median"] for r in points],
                   s=9, facecolors="none", edgecolors="#b51937", linewidths=.65)
        ax.set_title(result["quantity"]+": accepted source pixels; gaps retained", fontsize=10)
        ax.set_axis_off()
    fig.savefig(output/"Q01_material_pixel_overlay.png", dpi=160)
    plt.close(fig)
    print(json.dumps({"output": str(output), "accepted_counts": [len(r["measured"]) for r in results],
                      "paths_sha256": sha256(output/"Q01_material_pixel_paths.json"),
                      "new_material_parameters_identified": False}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pdf", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    extract(args.pdf.resolve(), args.output.resolve())
