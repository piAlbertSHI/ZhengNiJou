"""Measure observed same-phase drift in an independent cold diagnostic.

This is not a periodic-steady-state gate: hidden Simscape states and full
device energy accounting are not covered by the exported observations.
"""

import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256


SCALAR_TEMPERATURES = (
    "cold_buffer_temp_out",
    "hot_buffer_temp_out",
    "shex_buffer_temp_out",
    "sma_hot_buffer_temp_out",
    "se_cooldown_inlet_fluid_temp_out",
    "se_cooldown_outlet_fluid_temp_out",
)
FIELDS = {
    "SMA_temperature_K": ("SMA_Tx21_internal", None),
    "SE_temperature_K": ("SE_Tx21_internal", None),
    "SMA_martensite_fraction": ("ECC_constitutive21_output", slice(42, 63)),
    "SE_martensite_fraction": ("ECC_constitutive21_output", slice(63, 84)),
    "SE_stage4_flow_kgps": ("mass_flow_v4_hot_inlet_kgps", None),
    "SE_stage4_route_PI_MPa": ("stage4_route_integral", None),
    **{name: (name, None) for name in SCALAR_TEMPERATURES},
}


def compare_cycles(values, prior_start, last_start, samples):
    a = values[:, prior_start:prior_start + samples]
    b = values[:, last_start:last_start + samples]
    if a.shape != b.shape or a.shape[-1] != samples or not np.isfinite(a).all() or not np.isfinite(b).all():
        raise ValueError("Incomplete or nonfinite same-phase observation")
    delta = b - a
    return {
        "same_phase_rms": float(np.sqrt(np.mean(delta**2))),
        "same_phase_max_abs": float(np.max(np.abs(delta))),
        "endpoint_max_abs": float(np.max(np.abs(delta[:, -1]))),
        "endpoint_mean_signed": float(np.mean(delta[:, -1])),
        "prior_endpoint_mean": float(np.mean(a[:, -1])),
        "last_endpoint_mean": float(np.mean(b[:, -1])),
    }


def audit(root):
    execution_path = root / "cold_chamber_execution.json"
    execution = json.loads(execution_path.read_text(encoding="utf-8-sig"))
    cycles = int(execution.get("cycle_count", 0))
    if cycles < 2 or not execution.get("collection_pass") or execution.get("c200_state_imported"):
        raise ValueError("Need at least two complete independent cold cycles")
    if abs(float(execution["stop_time_s"]) - cycles * 10.0) > 1e-9:
        raise ValueError("Incomplete declared cycle horizon")
    prior_start = (cycles - 2) * 10000
    last_start = (cycles - 1) * 10000
    samples = 10001
    arms = []
    for arm in ("native", "conservative"):
        path = root / arm / "observations.mat"
        with h5py.File(path, "r") as handle:
            signals = handle["signals"]
            time = np.asarray(signals["SE_Tx21_internal"]["time_s"][:]).reshape(-1)
            if time.size != cycles * 10000 + 1 or not np.allclose(
                np.diff(time), 0.001, atol=1e-9, rtol=0
            ):
                raise ValueError("Observation grid differs from declared 1 ms cycles")
            fields = {}
            for name, (signal_name, row_slice) in FIELDS.items():
                values = np.asarray(signals[signal_name]["values"][:], dtype=float)
                if row_slice is not None:
                    values = values[row_slice, :]
                fields[name] = compare_cycles(values, prior_start, last_start, samples)
        arms.append({"arm": arm, "observations_sha256": sha256(path), "fields": fields})
    return {
        "schema": "heatdrive_ecc_cold_cycle_drift_diagnostic_v1",
        "diagnostic_only": True,
        "execution_commit": execution["execution_commit"],
        "cycle_count": cycles,
        "prior_cycle_index": cycles - 2,
        "last_cycle_index": cycles - 1,
        "phase_grid_samples": samples,
        "phase_grid_closed_endpoint": True,
        "observable_periodicity_assessed": True,
        "periodic_steady_state_verified": False,
        "periodic_status": "not_verifiable_from_partial_observations",
        "full_device_first_law_verified": False,
        "production_recovery_allowed": False,
        "outer_solve_eligible": False,
        "paired_table4_eligible": False,
        "table4_reproduction_claim": False,
        "arms": arms,
        "input_sha256": {"execution": sha256(execution_path)},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--experiment-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Do not overwrite drift evidence")
    result = audit(args.experiment_root.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n",
        encoding="utf-8",
    )
    print(json.dumps({
        "cycles": result["cycle_count"],
        "last_cycle_index": result["last_cycle_index"],
        "periodic_status": result["periodic_status"],
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
