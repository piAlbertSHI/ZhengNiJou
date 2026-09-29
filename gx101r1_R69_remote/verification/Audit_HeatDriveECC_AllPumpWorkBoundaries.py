"""Audit all three pressure-source pump work boundaries on raw observations.

Diagnostic only.  The output is a control-volume evidence package and never
authorizes recovery, seed use, outer solve, sensitivity, paired endpoints,
or Table 4 reproduction.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import h5py
import numpy as np


ROUTES = {
    "se_stage2": {
        "block": "heatdrive_ecc_coupled_se21/SE_Stage2_PistonPressureSource",
        "pressure_a": "pump_pressure_se_stage2_port_a_MPa",
        "pressure_b": "pump_pressure_se_stage2_port_b_MPa",
        "window": (193.801, 194.850),
    },
    "se_stage4": {
        "block": "heatdrive_ecc_coupled_se21/SE_Stage4_PistonPressureSource",
        "pressure_a": "pump_pressure_se_stage4_port_a_MPa",
        "pressure_b": "pump_pressure_se_stage4_port_b_MPa",
        "window": (198.801, 199.850),
    },
    "sma_stage1": {
        "block": "heatdrive_ecc_coupled_se21/SMA Pressure Source (TL)",
        "pressure_a": "pump_pressure_sma_port_a_MPa",
        "pressure_b": "pump_pressure_sma_port_b_MPa",
        "window": (190.301, 191.350),
    },
    "sma_stage3": {
        "block": "heatdrive_ecc_coupled_se21/SMA Pressure Source (TL)",
        "pressure_a": "pump_pressure_sma_port_a_MPa",
        "pressure_b": "pump_pressure_sma_port_b_MPa",
        "window": (195.301, 196.350),
    },
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def decode_char(handle: h5py.File, dataset: h5py.Dataset) -> str:
    return "".join(chr(value) for value in
                    np.asarray(handle[dataset.ref]).astype(int).ravel())


def read_series(group: h5py.Group, name: str) -> tuple[np.ndarray, np.ndarray]:
    row = group[name]
    return np.asarray(row["time_s"][0], dtype=float), np.asarray(
        row["values"][0], dtype=float)


def load_sources(handle: h5py.File) -> dict[tuple[str, str], tuple[np.ndarray, np.ndarray, str]]:
    result = {}
    for ref in np.asarray(handle["source_traces"]).ravel():
        trace = handle[ref]
        key = (decode_char(handle, trace["block_path"]),
               decode_char(handle, trace["state_name"]))
        result[key] = (np.asarray(trace["time_s"], dtype=float).ravel(),
                       np.asarray(trace["values"], dtype=float).ravel(),
                       decode_char(handle, trace["unit"]))
    return result


def interval(time_s: np.ndarray, values: np.ndarray,
             start_s: float, stop_s: float) -> dict:
    mask = (time_s >= start_s) & (time_s <= stop_s)
    if int(mask.sum()) < 2:
        raise ValueError("Pump route interval is undersampled")
    t, v = time_s[mask], values[mask]
    return {
        "start_s": float(t[0]), "stop_s": float(t[-1]),
        "samples": int(mask.sum()), "mean": float(v.mean()),
        "rms": float(np.sqrt(np.mean(v ** 2))), "min": float(v.min()),
        "max": float(v.max()), "integral": float(np.trapezoid(v, t)),
    }


def audit_route(handle: h5py.File, sources: dict, route_name: str) -> dict:
    cfg = ROUTES[route_name]
    signals = handle["signals"]
    ta, pressure_a = read_series(signals, cfg["pressure_a"])
    tb, pressure_b = read_series(signals, cfg["pressure_b"])
    if not np.array_equal(ta, tb):
        raise ValueError(f"Pressure probe grids differ for {route_name}")
    keys = [(cfg["block"], name) for name in
            ("P", "mdot_A", "mdot_B", "q_A", "q_B", "power")]
    if any(key not in sources for key in keys):
        raise ValueError(f"Missing source trace for {route_name}")

    def on_signal_grid(name: str) -> np.ndarray:
        t, values, _ = sources[(cfg["block"], name)]
        return values if np.array_equal(t, ta) else np.interp(ta, t, values)

    source_p = on_signal_grid("P")
    mdot_a, mdot_b = on_signal_grid("mdot_A"), on_signal_grid("mdot_B")
    q_a, q_b = on_signal_grid("q_A"), on_signal_grid("q_B")
    power_kw = on_signal_grid("power")
    pressure_residual = source_p / 1.0e6 + pressure_a - pressure_b
    mass_balance = mdot_a + mdot_b
    hydraulic_power = source_p * q_a
    start_s, stop_s = cfg["window"]
    mask = (ta >= start_s) & (ta <= stop_s)
    consistency = bool(
        np.max(np.abs(pressure_residual[mask])) < 1.0e-6 and
        np.max(np.abs(mass_balance[mask])) < 1.0e-9)
    return {
        "route": route_name,
        "source_block": cfg["block"],
        "window": {"start_s": start_s, "stop_s": stop_s,
                   "samples": int(mask.sum())},
        "pressure_source_MPa": interval(ta, source_p / 1.0e6, start_s, stop_s),
        "pressure_probe_delta_MPa": interval(ta, pressure_a - pressure_b, start_s, stop_s),
        "pressure_residual_MPa": interval(ta, pressure_residual, start_s, stop_s),
        "mass_balance_kgps": interval(ta, mass_balance, start_s, stop_s),
        "volume_balance_m3ps": interval(ta, q_a + q_b, start_s, stop_s),
        "reconstructed_hydraulic_power_W": interval(ta, hydraulic_power, start_s, stop_s),
        "declared_source_power_kW": interval(ta, power_kw, start_s, stop_s),
        "source_boundary_consistency_pass": consistency,
        "declared_power_observable": bool(np.max(np.abs(power_kw[mask])) > 1.0e-9),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--observations", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    with h5py.File(args.observations, "r") as handle:
        sources = load_sources(handle)
        routes = [audit_route(handle, sources, name) for name in ROUTES]
    result = {
        "schema": "heatdrive_ecc_all_pump_work_boundary_audit_v1",
        "diagnostic_only": True,
        "observations_sha256": sha256(args.observations),
        "routes": routes,
        "all_source_boundaries_pass": all(
            route["source_boundary_consistency_pass"] for route in routes),
        "all_declared_power_observable": all(
            route["declared_power_observable"] for route in routes),
        "derived_hydraulic_power_not_direct_pump_power": True,
        "production_recovery_allowed": False,
        "seed_eligible": False,
        "outer_solve_eligible": False,
        "paired_table4_eligible": False,
        "table4_reproduction_claim": False,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "all_source_boundaries_pass": result["all_source_boundaries_pass"],
        "all_declared_power_observable": result["all_declared_power_observable"],
        "seed_eligible": False,
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
