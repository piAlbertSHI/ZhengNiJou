"""Read-only decomposition of the strict cold-buffer mass ledger.

This audit distinguishes sampled-flux quadrature error from the measured
state increment. It never changes a model, creates an operating point, or
authorizes recovery.
"""
import argparse
import json
import math
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_ColdChamberCycle import checked_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_ColdChamberRejection import read
from Audit_HeatDriveECC_SegmentedEvidence import sha256


ROOT = "heatdrive_ecc_coupled_se21/"
BUFFERS = tuple(ROOT + name for name in (
    "ColdFluidBuffer", "HotFluidBuffer", "SHEXFluidBuffer", "SMAHotFluidBuffer"
))
MASS_LIMIT_KG = 1e-15


def _kahan_sum(values):
    total = 0.0
    correction = 0.0
    for value in values:
        y = float(value) - correction
        updated = total + y
        correction = (updated - total) - y
        total = updated
    return total


def _cumulative_kahan(values):
    result = np.empty(len(values) + 1, dtype=float)
    total = 0.0
    correction = 0.0
    result[0] = 0.0
    for index, value in enumerate(values, start=1):
        y = float(value) - correction
        updated = total + y
        correction = (updated - total) - y
        total = updated
        result[index] = total
    return result


def _ledger(time_s, mass_kg, mdot_kg_s):
    time_s = np.asarray(time_s, dtype=float)
    mass_kg = np.asarray(mass_kg, dtype=float)
    mdot_kg_s = np.asarray(mdot_kg_s, dtype=float)
    if (time_s.ndim != 1 or len(time_s) < 2 or
            mass_kg.shape != time_s.shape or mdot_kg_s.shape != time_s.shape or
            not np.isfinite([time_s, mass_kg, mdot_kg_s]).all() or
            np.any(np.diff(time_s) <= 0) or np.any(mass_kg <= 0)):
        raise ValueError("Invalid time, mass, or mass-flow trace")
    h = np.diff(time_s)
    right_increment = h * mdot_kg_s[1:]
    left_increment = h * mdot_kg_s[:-1]
    trapezoid_increment = h * 0.5 * (mdot_kg_s[1:] + mdot_kg_s[:-1])
    measured_increment = np.diff(mass_kg)
    methods = {
        "backward_euler_right": right_increment,
        "forward_euler_left": left_increment,
        "trapezoid": trapezoid_increment,
        "measured_state_increment": measured_increment,
    }
    cumulative = {
        name: np.r_[0.0, np.cumsum(increments)]
        for name, increments in methods.items()
    }
    cumulative["backward_euler_right_kahan"] = _cumulative_kahan(right_increment)
    cumulative["backward_euler_right_longdouble"] = np.asarray(
        np.r_[np.longdouble(0), np.cumsum(right_increment.astype(np.longdouble))],
        dtype=float,
    )
    residuals = {
        name: cumulative[name] - (mass_kg - mass_kg[0])
        for name in cumulative
    }
    derivative_residual = np.diff(mass_kg) / h - mdot_kg_s[1:]
    absolute_increment_sum = _kahan_sum(np.abs(right_increment))
    return {
        "sample_count": int(len(time_s)),
        "time_step_s": float(np.min(h)),
        "time_step_max_s": float(np.max(h)),
        "mass_start_kg": float(mass_kg[0]),
        "mass_end_kg": float(mass_kg[-1]),
        "endpoint_mass_change_kg": float(mass_kg[-1] - mass_kg[0]),
        "right_flux_absolute_increment_sum_kg": absolute_increment_sum,
        "right_flux_machine_scale_kg": float(np.finfo(float).eps * max(
            1.0, absolute_increment_sum, abs(float(mass_kg[-1] - mass_kg[0]))
        )),
        "derivative_vs_right_flux_max_abs_kg_s": float(np.max(abs(derivative_residual))),
        "derivative_vs_right_flux_rms_kg_s": float(np.sqrt(np.mean(derivative_residual ** 2))),
        "methods": {
            name: {
                "max_abs_residual_kg": float(np.max(abs(residual))),
                "end_residual_kg": float(residual[-1]),
                "pass_at_1e-15_kg": bool(np.all(abs(residual) <= MASS_LIMIT_KG)),
            }
            for name, residual in residuals.items()
        },
        "interpretation": (
            "The measured state increment is the reference identity; sampled flux methods "
            "are diagnostic only. A passing alternate quadrature does not authorize recovery."
        ),
    }


def analyze_arm(folder):
    observations = folder / "observations.mat"
    if not observations.is_file():
        raise FileNotFoundError(observations)
    rows_by_buffer = {}
    with h5py.File(observations, "r") as handle:
        expected_rows = 1240 if folder.name == "native" else 1258
        rows = checked_rows(handle, "native", expected_rows)
        for block_path in BUFFERS:
            mass_name = "stored_mass" if (block_path, "stored_mass") in rows else "mass"
            if (block_path, mass_name) not in rows or (block_path, "mdot_A") not in rows:
                continue
            get = lambda name, unit: scalar_series(rows[(block_path, name)], unit)
            time_s = rows[(block_path, mass_name)]["time_s"][:].reshape(-1)
            result = _ledger(time_s, get(mass_name, "kg"), get("mdot_A", "kg/s"))
            result["mass_state_name"] = mass_name
            rows_by_buffer[block_path] = result
    return rows_by_buffer


def analyze(repo, output_root):
    output_root = Path(output_root).resolve()
    if output_root.exists():
        raise FileExistsError(f"Refusing to overwrite evidence: {output_root}")
    source = repo / "outputs/cold_chamber_flux_compensated_fullcycle_kp126_225_0p85_20260914_v9"
    if not source.is_dir():
        raise FileNotFoundError(source)
    arms = {
        arm: analyze_arm(source / arm)
        for arm in ("native", "conservative")
    }
    return {
        "schema": "heatdrive_ecc_cold_buffer_mass_consistency_v1",
        "read_only": True,
        "source_root": str(source),
        "input_sha256": {
            str((source / arm / "observations.mat").relative_to(repo)): sha256(
                source / arm / "observations.mat"
            )
            for arm in arms
        },
        "mass_limit_kg": MASS_LIMIT_KG,
        "arms": arms,
        "production_recovery_allowed": False,
        "interpolation_eligible": False,
        "operating_point_created": False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", type=Path, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    result = analyze(repo, args.output_root)
    args.output_root.mkdir(parents=True)
    (args.output_root / "cold_buffer_mass_consistency.json").write_text(
        json.dumps(result, indent=2, allow_nan=False) + "\n", encoding="utf-8"
    )
    print(json.dumps({"schema": result["schema"], "output_root": str(args.output_root)}, indent=2))


if __name__ == "__main__":
    main()
