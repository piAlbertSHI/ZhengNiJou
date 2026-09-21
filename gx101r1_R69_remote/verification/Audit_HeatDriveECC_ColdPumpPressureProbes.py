"""Audit the independent cold-start pump A/B pressure probes.

This audit verifies observation coverage, pressure-domain bounds, and the
non-injected hydraulic-power diagnostic.  It never grants recovery, periodic
steady state, or a Table 4 claim.  The companion cold-buffer ledger is
required for the flow and local inventory results.
"""

import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field


ROOT = "heatdrive_ecc_coupled_se21/"
# Pressure-probe instrumentation is observational; later report-only commits
# preserve the exact runner and probe contract.
PRODUCERS = {
    "15e444ac60014a763837a67c46f17ede933d49b9",
    "0bd94ce91f1e6a595eb887ffa0a29c413e19045a",
    "d85609098cb210962a4bd2ee8966db76d0c614da",
    "a436f2aff6440c71b21973a45a01ed5e1750d69f",
}
PRESSURE_MIN_MPA = 0.45
PRESSURE_MAX_MPA = 5.0
EXPECTED = {
    "heatdrive_ecc_coupled_se21/SMA Pressure Source (TL)": (
        "pump_pressure_sma_port_a_MPa", "pump_pressure_sma_port_b_MPa"),
    "heatdrive_ecc_coupled_se21/SE_Stage2_PistonPressureSource": (
        "pump_pressure_se_stage2_port_a_MPa", "pump_pressure_se_stage2_port_b_MPa"),
    "heatdrive_ecc_coupled_se21/SE_Stage4_PistonPressureSource": (
        "pump_pressure_se_stage4_port_a_MPa", "pump_pressure_se_stage4_port_b_MPa"),
}


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def series(row, name):
    unit = text_field(row["unit"])
    values = np.asarray(row["values"][:], dtype=float).reshape(-1)
    return values, unit


def normalized_signal(signal, start, stop, allow_leading_warmup):
    time = np.asarray(signal["time_s"][:], dtype=float).reshape(-1)
    values = np.asarray(signal["values"][:], dtype=float).reshape(-1)
    expected = round((stop-start)/.001)+1
    trimmed = False
    if (allow_leading_warmup and time.size == round(stop/.001)+1
            and abs(time[0]) <= 1e-9 and abs(time[-1]-stop) <= 1e-9):
        first = round(start/.001)
        time = time[first:first+expected]
        values = values[first:first+expected]
        trimmed = True
    elif (allow_leading_warmup and time.size == expected+1
            and abs(time[0]-(start-.001)) <= 1e-9
            and abs(time[-1]-stop) <= 1e-9):
        time = time[1:]
        values = values[1:]
        trimmed = True
    expected_time = start + np.arange(expected)*.001
    if (time.size != expected or values.size != expected
            or not np.allclose(time, expected_time, rtol=0, atol=1e-9)
            or not np.isfinite(values).all()):
        raise ValueError("Invalid pressure/source trace time grid")
    return time, values, trimmed


def normalized_rows(handle, dataset, start, stop, allow_leading_warmup):
    rows = named_rows(handle, handle[dataset])
    normalized = {}
    for key, row in rows.items():
        time = np.asarray(row["time_s"][:], dtype=float).reshape(-1)
        values = np.asarray(row["values"][:], dtype=float)
        expected = round((stop-start)/.001)+1
        if (allow_leading_warmup and time.size == round(stop/.001)+1
                and abs(time[0]) <= 1e-9 and abs(time[-1]-stop) <= 1e-9):
            first = round(start/.001)
            time = time[first:first+expected]
            values = values[..., first:first+expected]
        elif (allow_leading_warmup and time.size == expected+1
                and abs(time[0]-(start-.001)) <= 1e-9
                and abs(time[-1]-stop) <= 1e-9):
            time = time[1:]
            values = values[..., 1:]
        expected_time = start + np.arange(expected)*.001
        if (time.size != expected or values.shape != (1, expected)
                or not np.allclose(time, expected_time, rtol=0, atol=1e-9)
                or not np.isfinite(values).all()):
            raise ValueError("Invalid pressure/source trace time grid")
        copy_row = dict(row)
        copy_row["time_s"] = time.reshape(1, -1)
        copy_row["values"] = values
        normalized[key] = copy_row
    return normalized


def audit_arm(root, arm, start, stop):
    folder = root / arm
    contract = read(folder / "pump_pressure_probe_contract.json")
    names = tuple(contract.get("observation_signal_names", ()))
    expected_names = tuple(name for pair in EXPECTED.values() for name in pair)
    contract_gate = bool(
        contract.get("schema") == "heatdrive_ecc_pump_pressure_probe_contract_v1"
        and contract.get("source_count") == 3
        and contract.get("simulation_run") is True
        and contract.get("state_imported") is False
        and contract.get("production_recovery_allowed") is False
        and set(names) == set(expected_names)
    )
    pressure_records = []
    source_records = []
    allow_leading_warmup = start > 0
    with h5py.File(folder / "observations.mat", "r") as handle:
        signals = handle["signals"]
        probes = handle["pressure_probe_signals"]
        source_rows = normalized_rows(handle, "source_traces", start, stop, allow_leading_warmup)
        signal_gate = True
        for name in expected_names:
            if name not in signals or name not in probes:
                raise ValueError(f"Missing pressure probe signal: {arm}/{name}")
            time, values, _ = normalized_signal(signals[name], start, stop, allow_leading_warmup)
            if not np.isfinite(values).all():
                signal_gate = False
            pressure_mpa = values
            pressure_records.append({
                "signal": name,
                "min_MPa": float(pressure_mpa.min()),
                "max_MPa": float(pressure_mpa.max()),
                "start_MPa": float(pressure_mpa[0]),
                "end_MPa": float(pressure_mpa[-1]),
                "finite": bool(np.isfinite(pressure_mpa).all()),
                "valid_range_MPa": [PRESSURE_MIN_MPA, PRESSURE_MAX_MPA],
                "gate_pass": bool(np.isfinite(pressure_mpa).all()
                                  and pressure_mpa.min() >= PRESSURE_MIN_MPA
                                  and pressure_mpa.max() <= PRESSURE_MAX_MPA),
            })

        source_gate = True
        hydraulic_records = []
        for source_path, (name_a, name_b) in EXPECTED.items():
            required = {"mdot_A", "rho_A", "rho_B", "Phi_A", "Phi_B", "power"}
            if not required.issubset({key[1] for key in source_rows if key[0] == source_path}):
                raise ValueError(f"Incomplete source trace coverage: {arm}/{source_path}")
            mdot, mdot_unit = series(source_rows[source_path, "mdot_A"], "mdot_A")
            rho_a, rho_a_unit = series(source_rows[source_path, "rho_A"], "rho_A")
            rho_b, rho_b_unit = series(source_rows[source_path, "rho_B"], "rho_B")
            phi_a, phi_a_unit = series(source_rows[source_path, "Phi_A"], "Phi_A")
            phi_b, phi_b_unit = series(source_rows[source_path, "Phi_B"], "Phi_B")
            power, power_unit = series(source_rows[source_path, "power"], "power")
            _, pressure_a, _ = normalized_signal(signals[name_a], start, stop, allow_leading_warmup)
            _, pressure_b, _ = normalized_signal(signals[name_b], start, stop, allow_leading_warmup)
            pressure_a = pressure_a * 1.0e6
            pressure_b = pressure_b * 1.0e6
            rho_mean = 0.5 * (rho_a + rho_b)
            hydraulic = mdot * (pressure_b - pressure_a) / rho_mean
            port_residual = phi_a + phi_b + power
            finite = bool(np.isfinite(hydraulic).all() and np.isfinite(port_residual).all())
            zero_native_power = bool(np.max(np.abs(power)) == 0.0)
            port_balance = float(np.max(np.abs(port_residual)))
            source_pass = bool(finite and zero_native_power and port_balance <= 1.0e-10)
            source_gate = source_gate and source_pass
            hydraulic_records.append({
                "source_path": source_path,
                "mdot_unit": mdot_unit,
                "rho_a_unit": rho_a_unit,
                "rho_b_unit": rho_b_unit,
                "pressure_unit": "MPa probe converted to Pa",
                "power_unit": power_unit,
                "hydraulic_formula": "mdot_A*(p_B-p_A)/mean(rho_A,rho_B)",
                "hydraulic_mean_W": float(np.mean(hydraulic)),
                "hydraulic_positive_mean_W": float(np.mean(np.maximum(hydraulic, 0.0))),
                "hydraulic_max_W": float(np.max(hydraulic)),
                "hydraulic_integral_J": float(np.trapezoid(hydraulic, dx=0.001)),
                "native_power_max_abs_W": float(np.max(np.abs(power))),
                "source_port_energy_residual_max_abs_W": port_balance,
                "source_port_energy_residual_limit_W": 1.0e-10,
                "finite": finite,
                "zero_native_power": zero_native_power,
                "hydraulic_diagnostic_gate": source_pass,
            })
    pressure_gate = bool(contract_gate and signal_gate
                         and all(row["gate_pass"] for row in pressure_records))
    return {
        "arm": arm,
        "probe_contract_gate": contract_gate,
        "probe_signal_gate": signal_gate,
        "pressure_range_gate": pressure_gate,
        "pressure_records": pressure_records,
        "hydraulic_diagnostic_gate": source_gate,
        "hydraulic_diagnostics": hydraulic_records,
    }


def audit(root, flow_audit_path):
    execution = read(root / "cold_chamber_execution.json")
    flow_audit = read(flow_audit_path)
    start = float(execution.get("simscape_log_window_start_s", 0.0))
    stop = float(execution.get("stop_time_s", 0.0))
    cycle_count = int(execution.get("cycle_count", 0))
    provenance_gate = bool(
        execution.get("schema") == "heatdrive_ecc_independent_cold_chamber_v2"
        and execution.get("execution_commit") in PRODUCERS
        and execution.get("collection_pass") is True
        and execution.get("start_time_s") == 0
        and stop > 0
        and cycle_count > 0
        and abs(stop-cycle_count*10.0) <= 1e-9
        and 0 <= start < stop
        and execution.get("c200_state_imported") is False
        and execution.get("checkpoint_saved") is False
        and execution.get("production_recovery_allowed") is False
        and [case.get("arm") for case in execution.get("cases", [])] == ["native", "conservative"]
    )
    arms = [audit_arm(root, arm, start, stop) for arm in ("native", "conservative")]
    flow_gate = bool(
        flow_audit.get("evidence_audit_pass") is True
        and flow_audit.get("declared_window_numerical_gates_pass") is True
        and flow_audit.get("local_inventory_conservation_pass") is True
        and flow_audit.get("strict_initial_coordinate_match") is True
        and flow_audit.get("production_recovery_allowed") is False
        and all(check.get("passed") for check in flow_audit.get("source_storage_port_checks", []))
        and all(flow.get("selected_flow_gate")
                for arm in flow_audit.get("arms", [])
                for flow in arm.get("selected_flow_gates", []))
    )
    mechanism_complete = bool(execution.get("periodic_steady_state")
                              and all(case.get("mechanism_pass") for case in execution.get("cases", [])))
    return {
        "schema": "heatdrive_ecc_cold_pump_pressure_probe_audit_v1",
        "diagnostic_only": True,
        "execution_commit": execution.get("execution_commit"),
        "logged_window_start_s": start,
        "logged_window_stop_s": stop,
        "cycle_count": cycle_count,
        "leading_warmup_sample_trimmed": bool(start > 0),
        "provenance_gate": provenance_gate,
        "flow_and_inventory_audit_path": str(flow_audit_path),
        "flow_and_inventory_gate": flow_gate,
        "arms": arms,
        "pressure_range_gate": all(arm["pressure_range_gate"] for arm in arms),
        "hydraulic_diagnostic_gate": all(arm["hydraulic_diagnostic_gate"] for arm in arms),
        "mechanism_gates_complete": mechanism_complete,
        "periodic_steady_state": bool(execution.get("periodic_steady_state")),
        "full_device_first_law_verified": bool(execution.get("full_device_first_law_verified")),
        "production_recovery_allowed": False,
        "table4_reproduction_claim": False,
        "seed_eligible": bool(provenance_gate and flow_gate
                               and all(arm["pressure_range_gate"] for arm in arms)
                               and all(arm["hydraulic_diagnostic_gate"] for arm in arms)
                               and mechanism_complete),
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
        "cold_chamber_execution.json": sha256(args.experiment_root / "cold_chamber_execution.json"),
        "flow_audit": sha256(args.flow_audit),
        "native_observations.mat": sha256(args.experiment_root / "native/observations.mat"),
        "conservative_observations.mat": sha256(args.experiment_root / "conservative/observations.mat"),
        "native_probe_contract": sha256(args.experiment_root / "native/pump_pressure_probe_contract.json"),
        "conservative_probe_contract": sha256(args.experiment_root / "conservative/pump_pressure_probe_contract.json"),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({k: result[k] for k in (
        "provenance_gate", "flow_and_inventory_gate", "pressure_range_gate",
        "hydraulic_diagnostic_gate", "mechanism_gates_complete", "seed_eligible",
        "production_recovery_allowed", "table4_reproduction_claim")}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
