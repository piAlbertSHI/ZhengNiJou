"""Guided raster readback of Q01 Fig5, not material identification.

Axes are manually registered against the original embedded image. Wide strips
separate the three visible black lines; slopes/intercepts are fitted to pixels,
not assigned from Table2. This cannot recover kinetics or a full polycrystal law.
"""
import argparse
import json
from pathlib import Path

import fitz
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Run_HeatDriveECC_ConservativeTransport import write_json


Q01_SHA = "2D0EB5F84AA515BA651638974414D426A3806FD417A1EAD96EFA36EDA08034CC"


def fit_diagram(pdf):
    if sha256(pdf) != Q01_SHA:
        raise ValueError("Unexpected Q01 source")
    document = fitz.open(pdf)
    images = document[7].get_images(full=True)
    if len(images) != 1:
        raise ValueError("Ambiguous Fig5 image")
    pixmap = fitz.Pixmap(document, images[0][0])
    if (pixmap.width, pixmap.height, pixmap.n) != (1422, 698, 3):
        raise ValueError("Unregistered source image")
    pixels = np.frombuffer(pixmap.samples, dtype=np.uint8).reshape(698, 1422, 3)
    # Source-image pixels, not page-render pixels. One-pixel axis uncertainty
    # is included below as a registration perturbation, not a confidence band.
    axes = (133., 1387., 580., 18.)
    runs = []
    for delta in (0., -1., 1.):
        x0, x120, y0, y800 = np.asarray(axes)+delta
        xx = np.arange(1422)
        temperature = (xx-x0)*120/(x120-x0)
        stress = (y0-np.arange(698))*800/(y0-y800)
        dark = (pixels.max(axis=2) < 120) & (np.ptp(pixels.astype(int), axis=2) < 30)
        lines = []
        for label, guide_slope, guide_intercept in (("left_100pct_M", 7.5, 40.),
                ("middle_50pct_M", 7.5, 45.), ("right_0pct_M", 7.5, 50.)):
            tx, sy = [], []
            for column in np.flatnonzero((temperature >= 82.) & (temperature <= 99.)):
                guide = guide_slope*(temperature[column]-guide_intercept)
                ys = np.flatnonzero(dark[:, column] & (abs(stress-guide) < 15.))
                if len(ys):
                    tx.append(temperature[column])
                    sy.append(float(np.median(stress[ys])))
            if len(tx) < 40:
                raise ValueError("Insufficient independent dark-line pixels")
            slope, intercept = np.polyfit(tx, sy, 1)
            lines.append({"line": label, "slope_MPa_per_K": float(slope),
                "zero_stress_intercept_C": float(-intercept/slope),
                "columns": len(tx), "RMS_pixel_fit_MPa": float(np.sqrt(np.mean((np.asarray(sy)-np.polyval([slope, intercept], tx))**2)))})
        runs.append({"axis_pixel_shift": delta, "lines": lines})
    return {"schema": "heatdrive_ecc_Q01_Fig5_guided_raster_readback_v1",
        "source": str(pdf), "source_sha256": Q01_SHA, "PDF_page": 8,
        "phase_line_labels_from_PDF_page": 7,
        "source_image_size": [1422, 698], "axes_x0_x120_y0_y800": list(axes),
        "fit_temperature_interval_C": [82., 99.], "pixel_color_filter_max": 120,
        "guided_strip_half_width_MPa": 15., "runs": runs,
        "axis_shift_is_sensitivity_not_statistical_confidence": True,
        "interpretation": "Check plot consistency only; finite-resolution fit is not exact constitutive input",
        "not_identified": ["activation volume", "relaxation time", "phase-dependent barrier distribution",
                           "low-temperature well branch", "path dependence"],
        "system_parameters_changed": False, "physical_validation_claim": False}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pdf", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError(args.output)
    result = fit_diagram(args.pdf.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    write_json(args.output, result)
    print(json.dumps({"output": str(args.output), "source_sha256": result["source_sha256"],
                      "central_fit": result["runs"][0]["lines"]}))
