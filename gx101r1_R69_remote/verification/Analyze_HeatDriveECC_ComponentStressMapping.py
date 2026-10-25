"""Primary-figure stress hull and conditional reverse-rate necessary bounds.

No full material identification, trajectory interpolation, SE endpoint averaging
or phase reset. Red branches/arrows are enclosed, not falsely resolved in time.
The VL grid is synthetic; tau bounds assume the declared Q04 pMA transfer only.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

import fitz
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Extract_HeatDriveECC_QianMaterialPaths import Q01_SHA, extract_trace
from Reference_HeatDriveECC_TwoWayPhase import SingleCrystalMAS
from Run_HeatDriveECC_ConservativeTransport import write_json


PIXEL_SHA = "B8D00A971D723D1775B1FBB570A6BE134065C27DE7714DA035B3352E7E339862"
FIG5_SHA = "A7E4F4302D2B9DF3A6A925A12B8F791DEE31A10232AE812535A8E792430972CE"
TABLE2 = {"L_SMA_m": .45, "L_SE_m": .2, "area_SMA_m2": 14.14e-6, "area_SE_m2": 4e-6,
          "E_Pa": 30e9, "transformation_strain": .03, "SMA_T_As_K": 323.15, "SMA_T_Ms_K": 313.15,
          "C_A_Pa_K": 7.6e6, "C_M_Pa_K": 7.3e6}


def red_pixels(image):
    a = image.astype(float)
    return (a[:, :, 0] > 120) & (a[:, :, 0]-np.maximum(a[:, :, 1], a[:, :, 2]) > 70)


def stress_hull(image, temperature_box_C, axes):
    """Enclose all red pixels across a temperature strip, including arrowheads.

    Every requested column must contain red evidence; an empty column is NOT
    interpolated. No inference is made about which branch occurs at that time.
    """
    if image.shape != (698, 1422, 3):
        raise ValueError("Unregistered Fig5 pixels")
    low, high = temperature_box_C
    if not np.isfinite([low, high]).all() or not 0 < low <= high < 120:
        raise ValueError("Temperature strip outside registered axes")
    x0, x120, y0, y800 = axes
    left = int(np.floor(x0+low*(x120-x0)/120))-1
    right = int(np.ceil(x0+high*(x120-x0)/120))+1
    if left <= x0 or right >= x120:
        return {"available": False, "reason": "strip_touches_frame"}
    ordinate = (y0-np.arange(image.shape[0]))*800/(y0-y800)
    selected = red_pixels(image) & ((ordinate >= 0) & (ordinate <= 230))[:, None]
    support = []
    for column in range(left, right+1):
        rows = np.flatnonzero(selected[:, column])
        if len(rows) == 0:
            return {"available": False, "reason": "missing_red_column", "column": column}
        support.append([column, int(rows[0]), int(rows[-1])])
    row_low = min(v[1] for v in support)-1
    row_high = max(v[2] for v in support)+1
    return {"available": True,
            "stress_extent_MPa": [(y0-row_high)*800/(y0-y800), (y0-row_low)*800/(y0-y800)],
            "pixel_columns": [left, right], "support_column_min_max_rows": support,
            "scope": "both red branches and arrow strokes; not unique stress or branch identity"}


def implied_SE_mean(phase_box, stress_box_MPa, c=TABLE2):
    """Only IF the SMA observed x is its axial mean and sigma is common stress.

    From Q01 Eqs5-8: no SE end value is substituted for a spatial average.
    Raw bounds remain unclipped. A physical intersection is an interval test,
    never assignment or clipping of a material state.
    """
    xlo, xhi = phase_box
    slo, shi = stress_box_MPa
    if not np.isfinite([xlo, xhi, slo, shi]).all() or not (0 <= xlo <= xhi <= 1 and 0 <= slo <= shi):
        raise ValueError("Physical phase/stress boxes required; no coordinate clipping")
    ratio = c["area_SMA_m2"]/c["area_SE_m2"]
    factor = (c["L_SMA_m"]+c["L_SE_m"]*ratio)/(c["E_Pa"]*c["transformation_strain"])
    low = (c["L_SMA_m"]*(1-xhi)-factor*shi*1e6)/c["L_SE_m"]
    high = (c["L_SMA_m"]*(1-xlo)-factor*slo*1e6)/c["L_SE_m"]
    intersection = [max(0., low), min(1., high)] if low <= 1 and high >= 0 else None
    return {"unclipped_range": [low, high], "physical_intersection": intersection,
            "SMA_curve_is_known_axial_mean": False, "measured_SE_mean": False}


def tensile_intersection(stress_box_MPa):
    """Intersect an UNCERTAINTY BOX with known tensile mechanics, not a state.

    The original observed box must remain in the record. A negative pixel-error
    edge alone is not evidence of an actual compressive material coordinate.
    """
    lo, hi = stress_box_MPa
    if not np.isfinite([lo, hi]).all() or lo > hi:
        raise ValueError("Finite ordered stress uncertainty box required")
    return [max(0., lo), hi] if hi >= 0 else None


def tau_upper_bound(volume, temperature_upper_K, stress_lower_MPa, duration_upper_s, integral_lower):
    """Necessary, not sufficient, conditional tau bound from Q04 pMA.

    For positive CM,Ms,T and tensile stress, z=(CM*(T-Ms)-sigma)/sqrt(T)
    increases with T and decreases with sigma; 1/erfcx(z) increases with z.
    Thus maximum pMA is at Tmax,sigma_min. No assumed zero opposing flux.
    """
    if (not np.isfinite([volume, temperature_upper_K, stress_lower_MPa, duration_upper_s, integral_lower]).all()
            or min(volume, temperature_upper_K, duration_upper_s, integral_lower) <= 0
            or stress_lower_MPa < 0):
        raise ValueError("Positive scales and tensile lower stress required")
    kernel = SingleCrystalMAS(TABLE2["E_Pa"], TABLE2["E_Pa"], volume, 1.)
    critical = TABLE2["C_M_Pa_K"]*(temperature_upper_K-TABLE2["SMA_T_Ms_K"])
    coefficient_at_unit_tau = float(kernel.reverse_coefficient(temperature_upper_K, stress_lower_MPa*1e6, critical))
    return duration_upper_s*coefficient_at_unit_tau/integral_lower


def read_image(document, page_index, dimensions):
    matches = [row for row in document[page_index].get_images(full=True) if tuple(row[2:4]) == dimensions]
    if len(matches) != 1:
        raise ValueError("Ambiguous source image identity")
    p = fitz.Pixmap(document, matches[0][0])
    if p.n != 3:
        raise ValueError("Unregistered source channels")
    return np.frombuffer(p.samples, dtype=np.uint8).reshape(p.height, p.width, 3)


def analyze(pixels, fig5, output):
    if sha256(pixels) != PIXEL_SHA or sha256(fig5) != FIG5_SHA:
        raise ValueError("Changed registered source metrology")
    prior = json.loads(pixels.read_text(encoding="utf-8"))
    source = Path(prior["source"])
    if sha256(source) != Q01_SHA:
        raise ValueError("Changed original Q01 PDF")
    relative = "gx101r1_R69_remote/verification/Extract_HeatDriveECC_QianMaterialPaths.py"
    historical = subprocess.check_output(["git", "show", "cbb2535:"+relative])
    if hashlib.sha256(historical).hexdigest().upper() != prior["reader_sha256"]:
        raise ValueError("Historical pixel reader provenance does not match")
    output.mkdir(parents=True, exist_ok=False)
    registration = json.loads(fig5.read_text(encoding="utf-8"))
    axes = registration["axes_x0_x120_y0_y800"]
    phase = next(r for r in prior["traces"] if r["quantity"] == "SMA_xM")
    document = fitz.open(source)
    temperature_image = read_image(document, 6, (1541, 735))
    stress_image = read_image(document, 7, (1422, 698))
    temp_registration = next(r for r in prior["traces"] if r["quantity"] == "SMA_temperature_C")
    tx0, tx20 = temp_registration["axes_pixels_x0_x20_y0_ytop"][:2]
    column_sets = []
    for p in phase["measured"]:
        low = tx0+(p["image_time_s"]-phase["one_pixel_time_s"])*(tx20-tx0)/20
        high = tx0+(p["image_time_s"]+phase["one_pixel_time_s"])*(tx20-tx0)/20
        column_sets.append(list(range(int(np.floor(low))-1, int(np.ceil(high))+2)))
    requested_columns = sorted({c for cols in column_sets for c in cols})
    temperature = extract_trace(temperature_image, "temperature", [(c-tx0)*20/(tx20-tx0) for c in requested_columns])
    by_column = {r["pixel_x"]: r for r in temperature["measured"]}
    pairs, missing = [], []
    for p, columns in zip(phase["measured"], column_sets):
        if any(c not in by_column for c in columns):
            missing.append({"phase_time_s": p["image_time_s"], "reason": "temperature_trace_missing_or_ambiguous"})
            continue
        support = [by_column[c] for c in columns]
        t = min(support, key=lambda r: abs(r["image_time_s"]-p["image_time_s"]))
        tbox = [min(r["pixel_ordinate_extent_plus_one"][0] for r in support),
                max(r["pixel_ordinate_extent_plus_one"][1] for r in support)]
        uncertainty = phase["one_pixel_time_s"]+temperature["one_pixel_time_s"]
        if abs(t["image_time_s"]-p["image_time_s"]) > uncertainty:
            raise ValueError("Figure clocks do not overlap within registered pixel time widths")
        hull = stress_hull(stress_image, tbox, axes)
        if not hull["available"]:
            missing.append({"phase_time_s": p["image_time_s"], **hull})
            continue
        shifts = []
        for shift in (-1., 0., 1.):
            shifted = stress_hull(stress_image, tbox, [v+shift for v in axes])
            if not shifted["available"]:
                raise ValueError("Axis sensitivity loses supporting red columns")
            shifts.append(shifted["stress_extent_MPa"])
        sbox = [min(s[0] for s in shifts), max(s[1] for s in shifts)]
        tensile = tensile_intersection(sbox)
        if tensile is None:
            missing.append({"phase_time_s": p["image_time_s"], "reason": "stress_uncertainty_has_no_tensile_intersection",
                            "unmodified_stress_extent_MPa": sbox})
            continue
        pairs.append({"phase": p, "temperature_center_pixel": t, "temperature_pixel_support": support,
                      "temperature_extent_C": tbox, "clock_offset_s": t["image_time_s"]-p["image_time_s"],
                      "clock_overlap_half_width_sum_s": uncertainty, "stress_hull": hull,
                      "stress_extent_MPa_including_axis_shift": sbox,
                      "tensile_stress_intersection_MPa": tensile,
                      "conditional_mean_compatibility": implied_SE_mean(p["pixel_ordinate_extent_plus_one"], tensile),
                      "Q04_full_two_way_interval_positive_over_T_box": tbox[0]+273.15 > TABLE2["SMA_T_As_K"]})
    if len(pairs) < 10:
        raise ValueError("Insufficient source-based T/x/stress constraints")
    constraints = []
    for cycle in (1, 2):
        falling = [p for p in pairs if p["phase"]["cycle"] == cycle and p["phase"]["image_time_s"]-(cycle-1)*10 < 1.4]
        for i, a in enumerate(falling):
            for b in falling[i+1:]:
                integral = float(np.log(a["phase"]["pixel_ordinate_extent_plus_one"][0]/b["phase"]["pixel_ordinate_extent_plus_one"][1]))
                if integral <= 0:
                    continue
                tbox = [a["temperature_extent_C"][0], b["temperature_extent_C"][1]]
                # Enclose every red source column in the full temperature strip.
                strip = stress_hull(stress_image, tbox, axes)
                if not strip["available"]:
                    raise ValueError("Kinetic strip has a missing stress column")
                shifted = [stress_hull(stress_image, tbox, [v+s for v in axes]) for s in (-1., 0., 1.)]
                if not all(r["available"] for r in shifted):
                    raise ValueError("Kinetic strip axis sensitivity has missing source pixels")
                strip_raw = [min(r["stress_extent_MPa"][0] for r in shifted), max(r["stress_extent_MPa"][1] for r in shifted)]
                strip_tensile = tensile_intersection(strip_raw)
                if strip_tensile is None:
                    raise ValueError("Strip stress box has no tensile intersection")
                stress_lower = strip_tensile[0]
                duration = b["phase"]["image_time_s"]-a["phase"]["image_time_s"]+2*phase["one_pixel_time_s"]
                constraints.append({"cycle": cycle, "phase_time_pair_s": [a["phase"]["image_time_s"], b["phase"]["image_time_s"]],
                                    "integrated_pMA_lower_bound": integral, "duration_upper_s": duration,
                                    "temperature_strip_C": tbox, "unmodified_stress_extent_MPa": strip_raw,
                                    "stress_lower_MPa": stress_lower})
    if not constraints:
        raise ValueError("No joint source constraints for a necessary reverse-rate bound")
    profile = []
    for volume in np.logspace(-28., -22., 13):
        values = [tau_upper_bound(volume, r["temperature_strip_C"][1]+273.15, r["stress_lower_MPa"],
                                  r["duration_upper_s"], r["integrated_pMA_lower_bound"]) for r in constraints]
        idx = int(np.argmin(values))
        profile.append({"synthetic_activation_volume_m3": float(volume), "necessary_tau_upper_s": values[idx],
                        "active_constraint_index": idx, "sufficient_or_identified": False})
    record = {"schema": "heatdrive_ecc_component_stress_constraints_v1", "collection_complete": True,
              "execution_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], encoding="utf-8").strip(),
              "source_sha256": {n: sha256(Path(__file__).with_name(n)) for n in
                 (Path(__file__).name, "Extract_HeatDriveECC_QianMaterialPaths.py", "Reference_HeatDriveECC_TwoWayPhase.py",
                  "Run_HeatDriveECC_ConservativeTransport.py", "Audit_HeatDriveECC_SegmentedEvidence.py")},
              "input_dependencies": [{"path": str(p), "sha256": sha256(p)} for p in (source, pixels, fig5)],
              "Table2_literal_contract": TABLE2, "Table2_source_PDF_page": 6,
              "figure5_axes": axes, "temperature_resampled_from_actual_pixels": temperature,
              "pairs": pairs, "missing": missing, "integral_constraints": constraints, "reverse_rate_profile": profile,
              "assumptions": ["Fig3/4/5 SMA legends refer to the same component observation convention; spatial statistic unspecified",
                              "pixel clock overlap is a raster approximation, not exact continuous simultaneity",
                              "SMA heating temperature monotone between selected early heating points",
                              "Figure5 hull covers the same component stress trajectory; union includes both branches/arrows",
                              "Q04 pMA formula and CM*(T-Ms) transferred conditionally, not established Q01 law",
                              "VL grid is a numerical probe, not a literature parameter range"],
              "axis_shift_is_sensitivity_not_full_confidence": True, "stress_branch_identified": False,
              "Q01_material_identified": False, "forward_low_temperature_branch_solved": False,
              "Table4_calibration_or_input": False, "production_recovery_allowed": False, "new_scientific_gate": False}
    write_json(output/"component_stress_constraints.json", record)
    overlay(stress_image, record, output/"source_stress_hull_overlay.png")
    return {"pairs": len(pairs), "missing": len(missing), "reverse_constraints": len(constraints),
            "conditional_mean_ranges_disjoint_from_physical": sum(p["conditional_mean_compatibility"]["physical_intersection"] is None for p in pairs),
            "full_Q04_domain_not_positive": sum(not p["Q04_full_two_way_interval_positive_over_T_box"] for p in pairs),
            "profile": profile, "sha256": sha256(output/"component_stress_constraints.json")}


def overlay(image, record, output):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.patches import Rectangle
    fig, ax = plt.subplots(figsize=(11, 5.5), layout="constrained")
    ax.imshow(image)
    for p in record["pairs"]:
        left, right = p["stress_hull"]["pixel_columns"]
        support = p["stress_hull"]["support_column_min_max_rows"]
        top, bottom = min(r[1] for r in support)-1, max(r[2] for r in support)+1
        ax.add_patch(Rectangle((left, top), right-left+1, bottom-top+1,
                              fill=False, edgecolor="#00845a", linewidth=.65))
    ax.set_title("Q01 Fig5: source-pixel stress hulls; branch identity unresolved", fontsize=11)
    ax.set_axis_off()
    fig.savefig(output, dpi=160)
    plt.close(fig)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pixels", type=Path, required=True)
    parser.add_argument("--fig5", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(analyze(args.pixels.resolve(), args.fig5.resolve(), args.output.resolve()), allow_nan=False))
