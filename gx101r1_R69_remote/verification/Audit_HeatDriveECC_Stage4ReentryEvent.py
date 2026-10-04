"""Read-only event-level audit for Stage-4 re-entry.

This audit does not change production gates and never grants seed, recovery,
outer-solve, or Table 4 status. It joins the commanded route opening with
flow, temperature, pressure, feedforward, and independent PI observations at
the same event window.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import h5py
import numpy as np


REQUIRED = (
    "mass_flow_v4_hot_inlet_kgps",
    "se_hold_outlet_fluid_temp_out",
    "stage4_pressure_command",
    "stage4_dynamic_feedforward",
    "stage4_feedforward_ratio_sum",
    "stage4_integrator_state",
    "stage4_integrator_output_gate",
)
OPTIONAL = (
    "stage4_feedforward_activity",
    "probe_v3_sma_to_hot_hot_hx_side_T_K",
    "probe_v3_sma_to_hot_sma_side_T_K",
    "pump_pressure_se_stage4_port_a_MPa",
    "pump_pressure_se_stage4_port_b_MPa",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def row(group, name: str) -> tuple[np.ndarray, np.ndarray]:
    item = group[name]
    return (np.asarray(item["time_s"][:], dtype=float).reshape(-1),
            np.asarray(item["values"][:], dtype=float))


def align_values(group, name: str, time: np.ndarray) -> np.ndarray:
    item_time, values = row(group, name)
    values = values.reshape(values.shape[0], -1) if values.ndim > 1 else values.reshape(1, -1)
    if item_time.size != time.size or not np.allclose(item_time, time, atol=1e-9, rtol=0.0):
        raise ValueError(f"time grid mismatch for {name}")
    if values.shape[0] != 1:
        raise ValueError(f"expected scalar diagnostic signal: {name}")
    return values[0]


def event_candidates(time: np.ndarray) -> list[float]:
    phase = np.mod(time, 10.0)
    mask = np.abs(phase - 8.5) <= 0.0011
    candidates = []
    for value in time[mask]:
        if not candidates or abs(value - candidates[-1]) > 0.01:
            candidates.append(float(value))
    return candidates


def interval_metrics(time: np.ndarray, values: np.ndarray, start: float, stop: float) -> dict:
    mask = (time >= start) & (time <= stop)
    if int(mask.sum()) < 2:
        return {"samples": int(mask.sum()), "available": False}
    q = values[mask]
    return {
        "samples": int(mask.sum()),
        "available": True,
        "min": float(np.min(q)),
        "max": float(np.max(q)),
        "mean": float(np.mean(q)),
        "first": float(q[0]),
        "last": float(q[-1]),
    }


def event_metrics(signals: h5py.Group, commands: h5py.Group | None,
                  event: float, time: np.ndarray) -> dict:
    before = (event - 0.010, event - 0.001)
    after = (event, event + 0.100)
    result = {"event_time_s": event, "before_window_s": before,
              "after_window_s": after, "signals": {}}
    for name in REQUIRED + OPTIONAL:
        if name not in signals:
            result["signals"][name] = {"available": False}
            continue
        values = align_values(signals, name, time)
        b = interval_metrics(time, values, *before)
        a = interval_metrics(time, values, *after)
        delta = None
        if b.get("available") and a.get("available"):
            delta = a["first"] - b["last"]
        result["signals"][name] = {"before": b, "after": a,
                                    "first_after_minus_last_before": delta}
    if commands is not None and "L_valve_command" in commands:
        ct, cv = row(commands, "L_valve_command")
        cv = cv.reshape(cv.shape[0], -1) if cv.ndim > 1 else cv.reshape(1, -1)
        cmd_mask = (ct >= event - 0.010) & (ct <= event + 0.100)
        pre_indices = np.flatnonzero(ct < event)
        post_indices = np.flatnonzero(ct >= event)
        nonzero_post = post_indices[
            np.any(np.abs(cv[:, post_indices]) > 1.0e-12, axis=0)
        ] if post_indices.size else np.array([], dtype=int)
        result["commanded_se_valves"] = {
            "time_start_s": float(ct[cmd_mask][0]) if cmd_mask.any() else None,
            "time_stop_s": float(ct[cmd_mask][-1]) if cmd_mask.any() else None,
            "columns_before": cv[:, pre_indices[-1]].tolist()
            if pre_indices.size else None,
            "first_nonzero_after_event_time_s": float(ct[nonzero_post[0]])
            if nonzero_post.size else None,
            "first_nonzero_after_event_offset_s": float(ct[nonzero_post[0]] - event)
            if nonzero_post.size else None,
            "columns_at_first_nonzero_after_event": cv[:, nonzero_post[0]].tolist()
            if nonzero_post.size else None,
            "columns_after_event": cv[:, post_indices[-1]].tolist()
            if post_indices.size else None,
            "shape": list(cv.shape),
        }
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--observations", type=Path, required=True)
    parser.add_argument("--configuration", type=Path, required=True)
    parser.add_argument("--execution", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Never overwrite event-level evidence")
    execution = json.loads(args.execution.read_text(encoding="utf-8-sig"))
    with h5py.File(args.observations, "r") as obs, h5py.File(args.configuration, "r") as cfg:
        group = obs["signals"]
        time, _ = row(group, REQUIRED[0])
        missing = [name for name in REQUIRED if name not in group]
        if missing:
            raise ValueError(f"missing required event signals: {missing}")
        candidates = event_candidates(time)
        commands = cfg.get("commands")
        events = [event_metrics(group, commands, event, time) for event in candidates]
    result = {
        "schema": "heatdrive_ecc_stage4_reentry_event_audit_v1",
        "diagnostic_only": True,
        "execution_commit": execution.get("execution_commit"),
        "observations_sha256": sha256(args.observations),
        "configuration_sha256": sha256(args.configuration),
        "execution_sha256": sha256(args.execution),
        "event_count": len(events),
        "events": events,
        "production_recovery_allowed": False,
        "diagnostic_20cycle_seed_eligible": False,
        "outer_solve_eligible": False,
        "paired_table4_eligible": False,
        "table4_reproduction_claim": False,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n",
                           encoding="utf-8")
    print(json.dumps({"event_count": len(events),
                      "production_recovery_allowed": False}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
