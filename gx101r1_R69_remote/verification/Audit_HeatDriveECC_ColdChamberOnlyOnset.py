"""Audit the chamber-only independent cold onset package.

This is a 0.2 s initialization and pressure-domain audit.  It verifies the
two-arm public-coordinate contract and the six pump pressure probes, but it
never evaluates a full-cycle flow/mechanism gate or grants seed eligibility.
"""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdChamberRejection import CHAMBERS
from Audit_HeatDriveECC_ColdCoordinateSmoke import compare_initial, ledger, scalar_series
from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_NativeWindowLedger import validate_grid
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field


PRODUCER = "8e7bbf77add7af389cb5a01881e44e79d87a84c8"
STOP_TIME_S = 0.2
DT_S = 0.001
PRESSURE_MIN_MPA = 0.45
PRESSURE_MAX_MPA = 5.0
EXPECTED_NATIVE_TRACES = {"native": 1240, "conservative": 1242}
ROOT = "heatdrive_ecc_coupled_se21/"
EXPECTED_PROBES = {
    "heatdrive_ecc_coupled_se21/SMA Pressure Source (TL)": (
        "pump_pressure_sma_port_a_MPa", "pump_pressure_sma_port_b_MPa"),
    "heatdrive_ecc_coupled_se21/SE_Stage2_PistonPressureSource": (
        "pump_pressure_se_stage2_port_a_MPa", "pump_pressure_se_stage2_port_b_MPa"),
    "heatdrive_ecc_coupled_se21/SE_Stage4_PistonPressureSource": (
        "pump_pressure_se_stage4_port_a_MPa", "pump_pressure_se_stage4_port_b_MPa"),
}
EXPECTED_PROBE_NAMES = tuple(name for pair in EXPECTED_PROBES.values() for name in pair)


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def materialize_block(template: dict, rows: dict, path: str) -> dict:
    block = copy.deepcopy(template)
    block["leaf_variables"] = []
    for (candidate, name), row in rows.items():
        if candidate == path:
            block["leaf_variables"].append({
                "name": name,
                "unit": text_field(row["unit"]),
                "time_s": row["time_s"][:].reshape(-1),
                "values": row["values"][:].reshape(-1),
            })
    return block


def check_time_grid(time: np.ndarray) -> bool:
    expected = np.arange(round(STOP_TIME_S / DT_S) + 1, dtype=float) * DT_S
    return bool(np.array_equal(time, expected))


def pressure_mpa(row: dict) -> np.ndarray:
    values = np.asarray(row["values"][:], dtype=float).reshape(-1)
    unit = text_field(row["unit"])
    if unit == "MPa":
        result = values
    elif unit == "Pa":
        result = values / 1.0e6
    elif unit == "bar":
        result = values / 10.0
    else:
        raise ValueError(f"Unsupported pressure unit: {unit}")
    if not np.isfinite(result).all():
        raise ValueError("Nonfinite pressure trace")
    return result


def audit_probes(handle: h5py.File, source_rows: dict) -> tuple[dict, list[dict], list[dict]]:
    signals = handle["signals"]
    probes = handle["pressure_probe_signals"]
    pressure_records = []
    signal_gate = True
    for name in EXPECTED_PROBE_NAMES:
        if name not in signals or name not in probes:
            signal_gate = False
            continue
        time = signals[name]["time_s"][:].reshape(-1)
        values = signals[name]["values"][:].reshape(-1)
        valid_grid = check_time_grid(time)
        finite = bool(np.isfinite(values).all())
        lo = float(np.min(values)) if values.size else float("nan")
        hi = float(np.max(values)) if values.size else float("nan")
        in_range = bool(finite and lo >= PRESSURE_MIN_MPA and hi <= PRESSURE_MAX_MPA)
        signal_gate = signal_gate and valid_grid and finite
        pressure_records.append({
            "signal": name,
            "samples": int(values.size),
            "min_MPa": lo,
            "max_MPa": hi,
            "start_MPa": float(values[0]) if values.size else float("nan"),
            "end_MPa": float(values[-1]) if values.size else float("nan"),
            "time_grid_pass": valid_grid,
            "finite": finite,
            "valid_range_MPa": [PRESSURE_MIN_MPA, PRESSURE_MAX_MPA],
            "gate_pass": in_range,
        })

    hydraulic_records = []
    source_gate = True
    for source_path, (name_a, name_b) in EXPECTED_PROBES.items():
        names = {key[1] for key in source_rows if key[0] == source_path}
        required = {"mdot_A", "rho_A", "rho_B", "Phi_A", "Phi_B", "power"}
        if not required.issubset(names):
            source_gate = False
            continue

        def get(name: str, unit: str) -> np.ndarray:
            return scalar_series(source_rows[source_path, name], unit)

        mdot = get("mdot_A", "kg/s")
        rho_a = get("rho_A", "kg/m^3")
        rho_b = get("rho_B", "kg/m^3")
        phi_a = get("Phi_A", "W")
        phi_b = get("Phi_B", "W")
        power = get("power", "W")
        pressure_a = signals[name_a]["values"][:].reshape(-1) * 1.0e6
        pressure_b = signals[name_b]["values"][:].reshape(-1) * 1.0e6
        rho_mean = 0.5 * (rho_a + rho_b)
        hydraulic = mdot * (pressure_b - pressure_a) / rho_mean
        port_residual = phi_a + phi_b + power
        finite = bool(np.isfinite(hydraulic).all() and np.isfinite(port_residual).all())
        zero_native_power = bool(np.max(np.abs(power)) == 0.0)
        port_balance = float(np.max(np.abs(port_residual)))
        passed = bool(finite and zero_native_power and port_balance <= 1.0e-10)
        source_gate = source_gate and passed
        hydraulic_records.append({
            "source_path": source_path,
            "hydraulic_formula": "mdot_A*(p_B-p_A)/mean(rho_A,rho_B)",
            "hydraulic_min_W": float(np.min(hydraulic)),
            "hydraulic_max_W": float(np.max(hydraulic)),
            "hydraulic_integral_J": float(np.trapezoid(hydraulic, dx=DT_S)),
            "native_power_max_abs_W": float(np.max(np.abs(power))),
            "source_port_energy_residual_max_abs_W": port_balance,
            "source_port_energy_residual_limit_W": 1.0e-10,
            "finite": finite,
            "zero_native_power": zero_native_power,
            "hydraulic_diagnostic_gate": passed,
        })

    contract = read_json(Path(handle.filename).parent / "pump_pressure_probe_contract.json")
    contract_gate = bool(
        contract.get("schema") == "heatdrive_ecc_pump_pressure_probe_contract_v1"
        and contract.get("source_count") == 3
        and contract.get("simulation_run") is True
        and contract.get("state_imported") is False
        and contract.get("production_recovery_allowed") is False
        and set(contract.get("observation_signal_names", ())) == set(EXPECTED_PROBE_NAMES)
    )
    return ({
        "probe_contract_gate": contract_gate,
        "probe_signal_gate": bool(signal_gate and len(pressure_records) == 6),
        "pressure_range_gate": bool(contract_gate and signal_gate and
                                     len(pressure_records) == 6 and
                                     all(row["gate_pass"] for row in pressure_records)),
        "hydraulic_diagnostic_gate": source_gate and len(hydraulic_records) == 3,
    }, pressure_records, hydraulic_records)


def audit_arm(root: Path, arm: str) -> dict:
    folder = root / arm
    metadata = read_json(folder / "inventory_metadata.json")
    with h5py.File(folder / "observations.mat", "r") as handle:
        rows = named_rows(handle, handle["native"])
        if len(rows) != EXPECTED_NATIVE_TRACES[arm]:
            raise ValueError(f"Unexpected {arm} native trace count: {len(rows)}")
        time = next(iter(rows.values()))["time_s"][:].reshape(-1)
        finite = True
        same_grid = check_time_grid(time)
        for row in rows.values():
            candidate = row["time_s"][:].reshape(-1)
            same_grid = same_grid and np.array_equal(candidate, time)
            finite = finite and bool(np.isfinite(row["values"][:]).all())
        pressure_records = []
        p_rows = {(path, name): row for (path, name), row in rows.items() if name == "p_I"}
        for (path, _), row in sorted(p_rows.items()):
            values = pressure_mpa(row)
            pressure_records.append({
                "block_path": path,
                "min_MPa": float(values.min()),
                "max_MPa": float(values.max()),
                "gate_pass": bool(np.isfinite(values).all() and
                                  values.min() >= PRESSURE_MIN_MPA and
                                  values.max() <= PRESSURE_MAX_MPA),
            })
        source_rows = named_rows(handle, handle["source_traces"])
        probe_gate, probe_records, hydraulic_records = audit_probes(handle, source_rows)
        chamber_records = []
        tables = {item["block_path"]: item for item in metadata["settings_tables"]}
        from Audit_HeatDriveECC_TLDomainInventory import resolve_domains
        assignment, _ = resolve_domains(read_json(root / "native/tl_connectivity.json"))
        for path in sorted(CHAMBERS):
            block = next(item for item in metadata["storage_blocks"] if item["block_path"] == path)
            block = materialize_block(block, rows, path)
            from Audit_HeatDriveECC_NativeAccumulation import energy_tables
            table = energy_tables(tables[assignment[path]]["parameters"])
            row, _ = _chamber_ledger(block, table)
            chamber_records.append(row)

    return {
        "arm": arm,
        "native_trace_count": len(rows),
        "time_samples": int(time.size),
        "time_grid_pass": bool(same_grid),
        "finite_native_traces": bool(finite),
        "pressure_state_count": len(pressure_records),
        "pressure_state_gate": bool(len(pressure_records) == 73 and
                                     all(item["gate_pass"] for item in pressure_records)),
        "pressure_state_records": pressure_records,
        "probe_audit": probe_gate,
        "pressure_probe_records": probe_records,
        "hydraulic_records": hydraulic_records,
        "chamber_ledger_gate": bool(all(item["local_chamber_gate"]["mass_closure_pass"] and
                                         item["local_chamber_gate"]["energy_closure_pass"]
                                         for item in chamber_records)),
        "chamber_ledger_records": chamber_records,
    }


def _chamber_ledger(block: dict, table: dict) -> tuple[dict, dict]:
    leaves = {row["name"]: row for row in block["leaf_variables"]}
    get = lambda name, unit: convert(np.asarray(leaves[name]["values"], dtype=float),
                                     leaves[name]["unit"], unit)
    time = np.asarray(leaves["rho_I"]["time_s"], dtype=float)
    volume = convert(block["mask_parameters"]["volume"]["value"],
                     block["mask_parameters"]["volume"]["unit"], "m^3")
    temp, pressure = get("T_I", "K"), get("p_I", "Pa")
    rho, u = get("rho_I", "kg/m^3"), get("u_I", "J/kg")
    coords = np.column_stack((temp, pressure))
    if (abs(table["rho"](coords) - rho).max() > 1.0e-7 or
            abs(table["u"](coords) - u).max() > 1.0e-6):
        raise ValueError("Chamber property/state mismatch")
    mass, energy = volume * rho, volume * rho * u
    gate = ledger(time, mass, energy, get("mdot_A", "kg/s") + get("mdot_B", "kg/s"),
                  get("Phi_A", "W") + get("Phi_B", "W") + get("Q_H", "W"))
    result = {"block_path": block["block_path"], "local_chamber_gate": gate,
              "stored_mass_alias_max_error_kg": None,
              "stored_energy_alias_max_error_J": None}
    if "stored_mass" in leaves:
        result["stored_mass_alias_max_error_kg"] = float(abs(mass - get("stored_mass", "kg")).max())
        result["stored_energy_alias_max_error_J"] = float(abs(energy - get("stored_energy", "J")).max())
    return result, gate


def initial_coordinate_audit(root: Path) -> dict:
    targets = read_json(root / "conservative/public_inventory_targets.json")
    with h5py.File(root / "native/observations.mat", "r") as native_handle, \
            h5py.File(root / "conservative/observations.mat", "r") as conservative_handle:
        native = named_rows(native_handle, native_handle["native"])
        conservative = named_rows(conservative_handle, conservative_handle["native"])
        volumes = {}
        metadata = read_json(root / "native/inventory_metadata.json")
        for block in metadata["storage_blocks"]:
            if block["block_path"] in CHAMBERS:
                p = block["mask_parameters"]["volume"]
                volumes[block["block_path"]] = convert(p["value"], p["unit"], "m^3")
        comparisons = []
        for target in targets["targets"]:
            path, name, unit = target["block_path"], target["state_name"], target["unit"]
            if name in ("stored_mass", "stored_energy"):
                rho = scalar_series(native[path, "rho_I"], "kg/m^3")[0]
                expected = volumes[path] * rho
                if name == "stored_energy":
                    expected *= scalar_series(native[path, "u_I"], "J/kg")[0]
            else:
                expected = scalar_series(native[path, name], unit)[0]
            actual = scalar_series(conservative[path, name], unit)[0]
            comparisons.append({"path": target["path"], "priority": target["priority"],
                                "unit": unit, **compare_initial(actual, expected)})
    return {
        "target_count": len(comparisons),
        "high_priority_count": sum(item["priority"] == "High" for item in comparisons),
        "low_priority_count": sum(item["priority"] == "Low" for item in comparisons),
        "strict_initial_coordinate_match": bool(comparisons and
                                                  all(item["within_strict_comparison"]
                                                      for item in comparisons)),
        "max_abs_error_by_unit": {
            unit: max(item["abs_error"] for item in comparisons if item["unit"] == unit)
            for unit in sorted({item["unit"] for item in comparisons})
        },
        "comparisons": comparisons,
    }


def audit(root: Path) -> dict:
    execution = read_json(root / "cold_chamber_execution.json")
    cases = execution.get("cases", [])
    case_hashes = {item["arm"]: item["observation_sha256"].upper() for item in cases}
    observed_hashes = {arm: sha256(root / arm / "observations.mat") for arm in ("native", "conservative")}
    provenance_gate = bool(
        execution.get("schema") == "heatdrive_ecc_independent_cold_chamber_v2"
        and execution.get("execution_commit") == PRODUCER
        and execution.get("collection_pass") is True
        and execution.get("start_time_s") == 0
        and execution.get("stop_time_s") == STOP_TIME_S
        and execution.get("cycle_count") == 1
        and execution.get("c200_state_imported") is False
        and execution.get("checkpoint_saved") is False
        and execution.get("production_recovery_allowed") is False
        and execution.get("table4_reproduction_claim") is False
        and [item.get("arm") for item in cases] == ["native", "conservative"]
        and case_hashes == observed_hashes
    )
    arms = [audit_arm(root, arm) for arm in ("native", "conservative")]
    coordinates = initial_coordinate_audit(root)
    pressure_gate = all(
        arm["pressure_state_gate"] and arm["probe_audit"]["probe_contract_gate"] and
        arm["probe_audit"]["probe_signal_gate"] and arm["probe_audit"]["pressure_range_gate"] and
        arm["probe_audit"]["hydraulic_diagnostic_gate"] and arm["chamber_ledger_gate"]
        for arm in arms
    )
    return {
        "schema": "heatdrive_ecc_cold_chamber_only_onset_audit_v1",
        "diagnostic_only": True,
        "provenance_gate": provenance_gate,
        "case_hashes": case_hashes,
        "observed_hashes": observed_hashes,
        "arms": arms,
        "initial_coordinates": coordinates,
        "pressure_and_local_inventory_gate": pressure_gate,
        "flow_gate_evaluated": False,
        "mechanism_gates_complete": False,
        "periodic_steady_state": False,
        "full_device_first_law_verified": False,
        "production_recovery_allowed": False,
        "table4_reproduction_claim": False,
        "seed_eligible": False,
        "rejection_reason_if_not_promoted": "0.2 s onset window; full-cycle flow and mechanism gates are intentionally not evaluated.",
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--experiment-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Never overwrite diagnostic evidence")
    root = args.experiment_root.resolve()
    result = audit(root)
    result["input_sha256"] = {
        "cold_chamber_execution.json": sha256(root / "cold_chamber_execution.json"),
        "native_observations.mat": sha256(root / "native/observations.mat"),
        "conservative_observations.mat": sha256(root / "conservative/observations.mat"),
        "native_probe_contract": sha256(root / "native/pump_pressure_probe_contract.json"),
        "conservative_probe_contract": sha256(root / "conservative/pump_pressure_probe_contract.json"),
        "conservative_public_inventory_targets": sha256(root / "conservative/public_inventory_targets.json"),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({key: result[key] for key in (
        "provenance_gate", "pressure_and_local_inventory_gate",
        "flow_gate_evaluated", "mechanism_gates_complete", "seed_eligible",
        "production_recovery_allowed", "table4_reproduction_claim")}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
