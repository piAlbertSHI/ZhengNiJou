"""Audit the observable Stage-4 pump pressure/work boundary.

This is diagnostic evidence only.  It does not grant a seed, recovery,
periodic steady state, outer solve, sensitivity, paired endpoint, or Table 4
status.  The audit checks source A/B pressure, A/B mass flow, source volume
flow, the corresponding pressure-source channel, and a reconstructed
hydraulic-power estimate on the same raw time grid.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import h5py
import numpy as np


TARGET_KGPS = 0.0032
TAU_S = 10.0
WINDOW_START_S = 8.801
WINDOW_STOP_S = 9.850


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def decode_char(handle: h5py.File, dataset: h5py.Dataset) -> str:
    ref = dataset.ref
    values = np.asarray(handle[ref]).astype(int).ravel()
    return "".join(chr(value) for value in values)


def read_series(group: h5py.Group, name: str) -> tuple[np.ndarray, np.ndarray]:
    row = group[name]
    return (np.asarray(row["time_s"][0], dtype=float),
            np.asarray(row["values"][0], dtype=float))


def source_traces(handle: h5py.File) -> dict[tuple[str, str], tuple[np.ndarray, np.ndarray, str]]:
    result = {}
    for ref in np.asarray(handle["source_traces"]).ravel():
        trace = handle[ref]
        block_path = decode_char(handle, trace["block_path"])
        state_name = decode_char(handle, trace["state_name"])
        unit = decode_char(handle, trace["unit"])
        time_s = np.asarray(trace["time_s"], dtype=float).ravel()
        values = np.asarray(trace["values"], dtype=float).ravel()
        result[(block_path, state_name)] = (time_s, values, unit)
    return result


def interval_metrics(time_s: np.ndarray, values: np.ndarray,
                     start_s: float, stop_s: float) -> dict:
    mask = (time_s >= start_s) & (time_s <= stop_s)
    if int(mask.sum()) < 2:
        raise ValueError("Pump-work audit interval is undersampled")
    t = time_s[mask]
    v = values[mask]
    return {
        "start_s": float(t[0]),
        "stop_s": float(t[-1]),
        "samples": int(mask.sum()),
        "mean": float(np.mean(v)),
        "rms": float(np.sqrt(np.mean(v ** 2))),
        "min": float(np.min(v)),
        "max": float(np.max(v)),
        "integral": float(np.trapezoid(v, t)),
    }


def audit(observations: Path, target_kgps: float) -> dict:
    with h5py.File(observations, "r") as handle:
        signals = handle["signals"]
        signal_time, inlet_flow = read_series(
            signals, "mass_flow_v4_hot_inlet_kgps")
        _, pressure_a = read_series(
            signals, "pump_pressure_se_stage4_port_a_MPa")
        _, pressure_b = read_series(
            signals, "pump_pressure_se_stage4_port_b_MPa")
        traces = source_traces(handle)
        prefix = "heatdrive_ecc_coupled_se21/SE_Stage4_PistonPressureSource"
        required = [(prefix, name) for name in
                    ("P", "mdot_A", "mdot_B", "q_A", "q_B", "power")]
        missing = [key for key in required if key not in traces]
        if missing:
            raise ValueError(f"Missing Stage-4 pressure-source traces: {missing}")
        source_time = traces[(prefix, "P")][0]
        source_grid_equal = bool(np.array_equal(signal_time, source_time))

        def on_signal_grid(name: str) -> np.ndarray:
            trace_time, trace_values, _ = traces[(prefix, name)]
            if np.array_equal(signal_time, trace_time):
                return trace_values
            return np.interp(signal_time, trace_time, trace_values)

        source_p = on_signal_grid("P")
        mdot_a = on_signal_grid("mdot_A")
        mdot_b = on_signal_grid("mdot_B")
        q_a = on_signal_grid("q_A")
        q_b = on_signal_grid("q_B")
        declared_power_kw = on_signal_grid("power")

    pressure_delta_mpa = pressure_a - pressure_b
    pressure_residual_mpa = source_p / 1.0e6 + pressure_delta_mpa
    flow_residual_kgps = mdot_a + inlet_flow
    flow_balance_kgps = mdot_a + mdot_b
    volume_balance_m3ps = q_a + q_b
    hydraulic_power_w = source_p * q_a
    cycle_index = max(0, int(np.floor(signal_time[-1] / TAU_S)) - 1)
    offset_s = cycle_index * TAU_S
    start_s = WINDOW_START_S + offset_s
    stop_s = WINDOW_STOP_S + offset_s
    strict_mask = (signal_time >= start_s) & (signal_time <= stop_s)
    strict = {
        "cycle_index": cycle_index,
        "pressure_source_MPa": interval_metrics(
            signal_time, source_p / 1.0e6, start_s, stop_s),
        "pressure_probe_delta_MPa": interval_metrics(
            signal_time, pressure_delta_mpa, start_s, stop_s),
        "pressure_consistency_residual_MPa": interval_metrics(
            signal_time, pressure_residual_mpa, start_s, stop_s),
        "source_mdot_A_kgps": interval_metrics(
            signal_time, mdot_a, start_s, stop_s),
        "source_mdot_B_kgps": interval_metrics(
            signal_time, mdot_b, start_s, stop_s),
        "inlet_flow_kgps": interval_metrics(
            signal_time, inlet_flow, start_s, stop_s),
        "source_flow_residual_kgps": interval_metrics(
            signal_time, flow_residual_kgps, start_s, stop_s),
        "source_mass_balance_kgps": interval_metrics(
            signal_time, flow_balance_kgps, start_s, stop_s),
        "source_volume_balance_m3ps": interval_metrics(
            signal_time, volume_balance_m3ps, start_s, stop_s),
        "reconstructed_hydraulic_power_W": interval_metrics(
            signal_time, hydraulic_power_w, start_s, stop_s),
        "declared_source_power_kW": interval_metrics(
            signal_time, declared_power_kw, start_s, stop_s),
    }
    declared_power_w = declared_power_kw * 1000.0
    pump_power_observable = bool(
        np.max(np.abs(declared_power_w)) > 1.0e-9)
    source_consistency_pass = bool(
        np.max(np.abs(pressure_residual_mpa[strict_mask])) < 1.0e-6 and
        np.max(np.abs(flow_residual_kgps[strict_mask])) < 1.0e-9 and
        np.max(np.abs(flow_balance_kgps[strict_mask])) < 1.0e-9)
    return {
        "schema": "heatdrive_ecc_stage4_pump_work_boundary_audit_v1",
        "diagnostic_only": True,
        "observations_sha256": sha256(observations),
        "target_flow_kgps": target_kgps,
        "source_block": prefix,
        "source_and_signal_grid_equal": source_grid_equal,
        "strict_window": strict,
        "source_boundary_consistency_pass": source_consistency_pass,
        "declared_pump_power_observable": pump_power_observable,
        "reconstructed_hydraulic_power_is_not_declared_pump_power": True,
        "production_recovery_allowed": False,
        "seed_eligible": False,
        "outer_solve_eligible": False,
        "paired_table4_eligible": False,
        "table4_reproduction_claim": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--observations", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--target-kgps", type=float, default=TARGET_KGPS)
    args = parser.parse_args()
    result = audit(args.observations, args.target_kgps)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "source_boundary_consistency_pass": result["source_boundary_consistency_pass"],
        "declared_pump_power_observable": result["declared_pump_power_observable"],
        "seed_eligible": False,
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
