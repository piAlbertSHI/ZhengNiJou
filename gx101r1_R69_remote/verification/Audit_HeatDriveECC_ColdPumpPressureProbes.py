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
    # Pressure probes are unchanged in this exact bounded bias experiment.
    "2c9cbe8f887cd5012440e2c1c451f4b09408bf8c",
    "15e444ac60014a763837a67c46f17ede933d49b9",
    "0bd94ce91f1e6a595eb887ffa0a29c413e19045a",
    "d85609098cb210962a4bd2ee8966db76d0c614da",
    "a436f2aff6440c71b21973a45a01ed5e1750d69f",
    "58049fdec3ad43222c716d508ee01c43cc77f10a",
    "f5329019943455f59c15d8d9d19c873800417383",
    "213fa7772733f725861747c04e6d62b9ac6993f3",
    "2839de0436094ae49da25336fb3b36ae6cbb6b3a",
    "384978570931127d909ddb7e9ca09545e97ffb02",
    "87668932da81d81a20611380bae2e9f14229383d",
    "7390794f4a36650d0f568931a197d0d8d7a92c2e",
    "1e2c9b1b4c9effd772af63f1546e2bacfb8df933",
    # 724376b changes only audit/provenance/report files; the physical
    # runner and pressure-probe contract remain byte-identical to 1e2c9b1.
    "724376b0368acaef63e3d353542c31eefc2c63c1",
    # a9535e2 adds observational Stage-4 controller taps only; pressure
    # probe provenance and the physical runner contract are unchanged.
    "a9535e2582fa6c6d0841dfd3898624690cb50127",
    "393be6f000d9421c159b8c191f6f2c65ac24c185",
    # 737373f adds only read-only Stage-4 boundary diagnostics; the physical
    # runner and pressure-probe contract are unchanged.
    "737373fe920d9a7964fcd698aa0be2de19b1698d",
    # 1d08a59 only updates this audit's exact producer allowlist.
    "1d08a59fd91876e7440b7beab27398ef7888d8ce",
    # Independent cold diagnostics with bounded Stage-4 overrides and
    # observed thermal-boundary extraction; no recovery state is imported.
    "3cda3aab3a6bcee45f67e69403a5bf57e0aef882",
    # 3b27188 only aligns the Stage-4 precharge diagnostic to the settled
    # gate-time grid; pressure probes and their contracts are unchanged.
    "3b2718852ba02e6b37fbb4d6fc83a7cbfa16b617",
    "c7f46db863a1a59b5c79ad1647f226b7d73bfd86",
    # e791744 only makes the bounded pressure-filter override explicit in the
    # post-load runtime workspace; pump-probe and recovery contracts remain
    # unchanged.
    "e79174429c8624097752c05f54d4a0fcc24073d4",
    # 2583785 only restores zero-order-hold alignment between sparse pressure
    # commands and fixed gate grids; pressure probes and recovery contracts
    # remain unchanged.
    "25837852427a831fcc3f1e7c0f33e31f2536cd4a",
    # 3a202dd changes only audit provenance allowlists and regression tests;
    # the physical runner is byte-identical to 2583785.
    "3a202dd",
    # c281c77 exposes only the periodic Stage-4 endpoint-viscosity blend
    # start/duration override; pressure probes and recovery contracts remain
    # unchanged.
    "c281c77575e174a4fe19a6c60b923234f142dc37",
    "baaeab479344e7534159c8a5dbf1c70bb86762c3",
    # fc10ad6 adds finite storage on isolated SE valve legs only; pressure
    # probes remain observational and recovery is still prohibited.
    "fc10ad6ee343dfc000a7b5e7b7fd80b3221936e2",
    "fe9a347e555e486bc991dc890570f09aeb418a0e",
    "237e2766d0022adff5686a9550e89620f4246162",
    # 54364e1 is the JSON-contract runtime observation; pressure probes are
    # observationally identical and the run remains evidence-only.
    "54364e1bdc32f4db06b10f04dfa1f28541acfd67",
    # 85a5339/1baf2be add only the isolated continuous Stage-4 P-activity
    # diagnostic and launcher plumbing; pressure probes and recovery
    # prohibitions remain unchanged.
    "85a5339",
    "1baf2beec18532f2861bd9e30e0235451fabb6b3",
    "4c9036c",
    "36a1dcc",
    "36a1dccf485d2bcb909a5cea0e31dd2d11ab6461",
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
        and len(flow_audit.get("arms", [])) == 2
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
