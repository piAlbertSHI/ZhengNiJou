"""Inventory observed thermal boundaries without granting a physics gate.

This audit answers a narrow question: which time-resolved thermal and flow
signals are actually present in an observations MAT file, on which time grid,
and what do they measure over the final complete cycle?  It deliberately does
not infer missing HHEX/CHEX boundaries from configured targets and never
declares a first-law, periodicity, recovery, or Table 4 pass.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import h5py
import numpy as np


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_signal(group: h5py.Group, name: str) -> tuple[np.ndarray, np.ndarray] | None:
    if name not in group:
        return None
    signal = group[name]
    if "time_s" not in signal or "values" not in signal:
        return None
    time = np.asarray(signal["time_s"][:], dtype=float).reshape(-1)
    raw_values = np.asarray(signal["values"][:], dtype=float)
    if raw_values.ndim == 1:
        values = raw_values
    elif raw_values.ndim == 2 and raw_values.shape[-1] == time.size:
        # Constitutive channels retain one row per SMA/SE node.  The thermal
        # boundary metric is their signed node sum, not a flattened matrix.
        values = np.sum(raw_values, axis=0)
    elif raw_values.ndim == 2 and raw_values.shape[0] == time.size:
        values = np.sum(raw_values, axis=1)
    else:
        return None
    if time.shape != values.shape or time.size < 2:
        return None
    return time, values


def status(present: dict[str, bool]) -> str:
    if all(present.values()):
        return "complete"
    if any(present.values()):
        return "partial"
    return "missing"


def finite_grid(signal: tuple[np.ndarray, np.ndarray] | None) -> dict[str, object]:
    if signal is None:
        return {"present": False, "finite": False, "uniform": False}
    time, values = signal
    delta = np.diff(time)
    uniform = bool(np.isfinite(time).all() and time.size > 1 and np.all(delta > 0)
                   and np.allclose(delta, delta[0], rtol=0, atol=1e-12))
    return {
        "present": True,
        "finite": bool(np.isfinite(time).all() and np.isfinite(values).all()),
        "uniform": uniform,
        "sample_count": int(time.size),
        "start_s": float(time[0]),
        "stop_s": float(time[-1]),
        "dt_s": float(delta[0]) if delta.size else None,
    }


def window_metrics(signal: tuple[np.ndarray, np.ndarray] | None, start: float, stop: float) -> dict[str, object]:
    if signal is None:
        return {"present": False}
    time, values = signal
    mask = (time >= start - 1e-12) & (time <= stop + 1e-12)
    if np.count_nonzero(mask) < 2:
        return {"present": True, "window_samples": int(np.count_nonzero(mask)), "window_complete": False}
    t, y = time[mask], values[mask]
    return {
        "present": True,
        "window_samples": int(t.size),
        "window_start_s": float(t[0]),
        "window_stop_s": float(t[-1]),
        "window_complete": bool(abs(t[0] - start) <= 1e-12 and abs(t[-1] - stop) <= 1e-12),
        "finite": bool(np.isfinite(y).all()),
        "mean": float(np.mean(y)),
        "rms": float(np.sqrt(np.mean(y * y))),
        "min": float(np.min(y)),
        "max": float(np.max(y)),
        "integral": float(np.trapezoid(y, t)),
    }


def audit(result_path: Path, cycle_start: float, cycle_stop: float, output: Path) -> dict[str, object]:
    with h5py.File(result_path, "r") as handle:
        if "signals" not in handle:
            raise ValueError("observations MAT file has no signals group")
        signals = handle["signals"]
        names = {
            "SHEX": {
                "thermal": ["shex_source_heat_flow_W", "shex_fluid_heat_flow_W"],
                "temperature": ["shex_buffer_temp_out", "SHEX_hot_hx_inlet_fluid_temp_out",
                                 "SHEX_hot_hx_outlet_fluid_temp_out"],
                "mass_flow": ["mass_flow_sma_stage1_route_kgps"],
            },
            "HHEX": {
                "thermal": ["hhex_fluid_heat_flow_W"],
                "temperature": ["hot_hx_inlet_fluid_temp_out", "hot_hx_outlet_fluid_temp_out",
                                 "hhex_sma_branch_inlet_fluid_temp_out", "hhex_sma_branch_outlet_fluid_temp_out"],
                "mass_flow": ["mass_flow_sma_stage3_route_kgps", "mass_flow_v3_sma_to_hot_kgps"],
            },
            "CHEX": {
                "thermal": ["chex_fluid_heat_flow_W", "Qdot_cold_sink_mass_to_hx_pipe_W",
                             "Qdot_cold_sink_mass_to_pipe_W"],
                "temperature": ["cold_hx_inlet_fluid_temp_out", "cold_hx_outlet_fluid_temp_out",
                                 "cold_sink_temp_out", "cold_buffer_temp_out"],
                "mass_flow": ["mass_flow_v6_sma_to_chip_cold_kgps"],
            },
            "SMA_SE_constitutive": {
                "thermal": ["ECC_Q_SMA_constitutive_W", "ECC_Q_SE_constitutive_W"],
                "temperature": ["hot_buffer_temp_out", "cold_buffer_temp_out"],
                "mass_flow": [],
            },
            "boundary_and_pump": {
                "thermal": ["Qdot_cold_sink_mass_to_hx_pipe_W", "Qdot_cold_sink_mass_to_pipe_W"],
                "temperature": ["hot_buffer_temp_out", "cold_buffer_temp_out"],
                "mass_flow": ["mass_flow_v4_hot_inlet_kgps", "mass_flow_v1_cold_inlet_kgps"],
            },
        }

        all_signals = {}
        for group_name, categories in names.items():
            all_signals[group_name] = {}
            for category, requested in categories.items():
                present = {name: name in signals for name in requested}
                entries = {}
                for name in requested:
                    signal = read_signal(signals, name)
                    all_signals[group_name][category] = all_signals[group_name].get(category, {})
                    entries[name] = {
                        "grid": finite_grid(signal),
                        "final_cycle": window_metrics(signal, cycle_start, cycle_stop),
                    }
                all_signals[group_name][category] = {
                    "status": status(present),
                    "requested": requested,
                    "signals": entries,
                }

        grid_signals = []
        for group in all_signals.values():
            for category in group.values():
                for entry in category["signals"].values():
                    if entry["grid"].get("present"):
                        grid_signals.append(entry["grid"])
        time_axes = {(item["sample_count"], item["start_s"], item["stop_s"], item["dt_s"])
                     for item in grid_signals if item.get("finite") and item.get("uniform")}
        thermal_required = {
            "SHEX_fluid_heat": "shex_fluid_heat_flow_W",
            "HHEX_fluid_heat": "hhex_fluid_heat_flow_W",
            "CHEX_fluid_heat": "chex_fluid_heat_flow_W",
            "SHEX_mass_flow": "mass_flow_sma_stage1_route_kgps",
            "HHEX_mass_flow_SE_or_SMA": "mass_flow_sma_stage3_route_kgps",
            "CHEX_mass_flow": "mass_flow_v6_sma_to_chip_cold_kgps",
        }
        required_presence = {label: signal in signals for label, signal in thermal_required.items()}
        result = {
            "schema": "heatdrive_ecc_observed_thermal_boundary_audit_v1",
            "diagnostic_only": True,
            "source": str(result_path),
            "observations_sha256": sha256(result_path),
            "cycle_window": {"start_s": cycle_start, "stop_s": cycle_stop},
            "groups": all_signals,
            "time_grid": {
                "finite_uniform_grid_count": len(grid_signals),
                "distinct_finite_uniform_axes": len(time_axes),
                "single_common_axis": len(time_axes) == 1,
            },
            "required_time_resolved_boundary_presence": required_presence,
            "full_device_first_law_observable": bool(all(required_presence.values()) and len(time_axes) == 1),
            "full_device_first_law_verified": False,
            "periodic_steady_state_verified": False,
            "production_recovery_allowed": False,
            "seed_eligible": False,
            "outer_solve_eligible": False,
            "paired_table4_eligible": False,
            "table4_reproduction_claim": False,
            "interpretation": "Signal inventory and window statistics only; configured targets are excluded from physical evidence.",
        }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--observations", type=Path, required=True)
    parser.add_argument("--cycle-start", type=float, required=True)
    parser.add_argument("--cycle-stop", type=float, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Do not overwrite thermal boundary evidence")
    print(json.dumps(audit(args.observations, args.cycle_start, args.cycle_stop, args.output), indent=2))


if __name__ == "__main__":
    main()
