"""Diagnose Stage-4 transport-window sensitivity without changing gates.

The production Stage-4 flow gate is intentionally left untouched.  This
read-only audit separates the current instantaneous window from boundary
transients and late-phase overshoot so an audit failure is not misdiagnosed as
an arbitrary PI-tuning problem.  It never grants a seed, recovery, outer
solve, sensitivity, paired endpoint, or Table 4 status.
"""

import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256


STAGE4_START_S = 8.5
STAGE4_STOP_S = 10.0
STRICT_START_S = 8.801
STRICT_STOP_S = 9.85
WINDOW_DURATION_S = STRICT_STOP_S - STRICT_START_S
SHIFT_OFFSETS_S = (0.301, 0.4, 0.5, 0.6, 0.7, 0.8)


def _read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def _signal(experiment_root, arm):
    path = experiment_root / arm / "observations.mat"
    with h5py.File(path, "r") as handle:
        time = np.asarray(
            handle["signals"]["mass_flow_v4_hot_inlet_kgps"]["time_s"][:],
            dtype=float,
        ).reshape(-1)
        flow = np.asarray(
            handle["signals"]["mass_flow_v4_hot_inlet_kgps"]["values"][:],
            dtype=float,
        ).reshape(-1)
    return path, time, flow


def _window_metrics(time, flow, start, stop, target):
    mask = (time >= start) & (time < stop)
    if not np.any(mask):
        raise ValueError(f"Empty Stage-4 transport window: {start}--{stop} s")
    values = flow[mask]
    error = values / target - 1.0
    interval_time = time[mask]
    signed_mass = float(np.trapezoid(values, interval_time) * 1000.0)
    expected_mass = float(target * (interval_time[-1] - interval_time[0]) * 1000.0)
    return {
        "start_s": float(start),
        "stop_s": float(stop),
        "duration_s": float(stop - start),
        "samples": int(values.size),
        "mean_flow_kgps": float(values.mean()),
        "rms_relative_error": float(np.sqrt(np.mean(error**2))),
        "max_abs_relative_error": float(np.max(np.abs(error))),
        "signed_transport_mass_g": signed_mass,
        "expected_transport_mass_g": expected_mass,
        "integrated_signed_mass_relative_error": float(
            (signed_mass - expected_mass) / expected_mass
        ),
        "reverse_flow_fraction": float(np.mean(values < 0.0)),
    }


def audit(experiment_root, flow_audit_path):
    execution = _read(experiment_root / "cold_chamber_execution.json")
    if not execution.get("collection_pass"):
        raise ValueError("Cold collection did not pass")
    if execution.get("c200_state_imported") or execution.get("checkpoint_saved"):
        raise ValueError("Transport diagnostic cannot consume a recovery package")
    cycles = int(execution.get("cycle_count", 0))
    if cycles < 1 or abs(float(execution["stop_time_s"]) - cycles * 10.0) > 1e-9:
        raise ValueError("Transport diagnostic requires complete 10 s cycles")
    with h5py.File(experiment_root / "native" / "observations.mat", "r") as handle:
        time = np.asarray(
            handle["signals"]["mass_flow_v4_hot_inlet_kgps"]["time_s"][:],
            dtype=float,
        ).reshape(-1)
    if time.size < 2 or not np.allclose(np.diff(time), 0.001, atol=1e-9, rtol=0):
        raise ValueError("Stage-4 flow trace is not on the 1 ms grid")
    flow_audit = _read(flow_audit_path)
    native_stage4 = next(
        row
        for row in flow_audit["arms"][0]["selected_flow_gates"]
        if row["component"] == "SE" and row["stage"] == 4
    )
    target = float(native_stage4["target_kg_s"])
    cycle_start = (cycles - 1) * 10.0
    phase_start = cycle_start + STAGE4_START_S
    phase_stop = cycle_start + STAGE4_STOP_S
    strict_start = cycle_start + STRICT_START_S
    strict_stop = cycle_start + STRICT_STOP_S
    arms = []
    for arm in ("native", "conservative"):
        observations_path, arm_time, flow = _signal(experiment_root, arm)
        if not np.array_equal(arm_time, time):
            raise ValueError("Native and conservative time grids differ")
        windows = {
            "full_stage4": _window_metrics(
                time, flow, phase_start, phase_stop, target
            ),
            "strict_current": _window_metrics(
                time, flow, strict_start, strict_stop, target
            ),
        }
        shifted = []
        for offset in SHIFT_OFFSETS_S:
            start = cycle_start + STAGE4_START_S + offset
            stop = min(start + WINDOW_DURATION_S, phase_stop)
            shifted.append(
                dict(
                    offset_from_stage4_start_s=offset,
                    **_window_metrics(time, flow, start, stop, target),
                )
            )
        arms.append(
            {
                "arm": arm,
                "observations_sha256": sha256(observations_path),
                "analysis_cycle_index": cycles - 1,
                "target_kgps": target,
                "windows": windows,
                "shifted_windows": shifted,
            }
        )
    return {
        "schema": "heatdrive_ecc_stage4_transport_window_audit_v1",
        "diagnostic_only": True,
        "execution_commit": execution["execution_commit"],
        "cycle_count": cycles,
        "analysis_cycle_index": cycles - 1,
        "stage4_phase_start_s": STAGE4_START_S,
        "stage4_phase_stop_s": STAGE4_STOP_S,
        "strict_window_start_s": STRICT_START_S,
        "strict_window_stop_s": STRICT_STOP_S,
        "interpretation": {
            "production_flow_gate_unchanged": True,
            "steady_transport_gate_defined_here": False,
            "purpose": "Separate boundary transient from late-phase overshoot before structural controller changes.",
        },
        "arms": arms,
        "production_recovery_allowed": False,
        "seed_eligible": False,
        "outer_solve_eligible": False,
        "paired_table4_eligible": False,
        "table4_reproduction_claim": False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--experiment-root", type=Path, required=True)
    parser.add_argument("--flow-audit", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Do not overwrite diagnostic evidence")
    result = audit(args.experiment_root.resolve(), args.flow_audit.resolve())
    result["input_sha256"] = {
        "cold_chamber_execution.json": sha256(
            args.experiment_root / "cold_chamber_execution.json"
        ),
        "flow_audit": sha256(args.flow_audit),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n",
        encoding="utf-8",
    )
    print(
        json.dumps(
            {
                "analysis_cycle_index": result["analysis_cycle_index"],
                "production_recovery_allowed": False,
                "seed_eligible": False,
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
