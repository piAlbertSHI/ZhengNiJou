"""Audit independent cold-start pressure envelopes and local inventories.

This is an onset diagnostic only.  It compares two independently generated
0.2 s paired trials and never grants a production recovery or Table 4 claim.
"""
import argparse
import copy
import csv
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdBufferCoupled import topology_check
from Audit_HeatDriveECC_ColdChamberCycle import custom_ledger
from Audit_HeatDriveECC_ColdChamberRejection import CHAMBERS
from Audit_HeatDriveECC_ConservativeChamberResult import MASS_ATOL_KG, ENERGY_ATOL_J
from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_NativeWindowLedger import validate_grid
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field
from Audit_HeatDriveECC_TLDomainInventory import resolve_domains, scalar
from Audit_HeatDriveECC_ConservativeBufferTrial import inventory


ROOT = "heatdrive_ecc_coupled_se21/"
BUFFERS = {ROOT + n for n in ("ColdFluidBuffer", "HotFluidBuffer", "SHEXFluidBuffer", "SMAHotFluidBuffer")}
STORAGE_COUNT = 119
PRESSURE_COMPONENT_COUNT = 73
EXPECTED_NATIVE = 1240
EXPECTED_CONSERVATIVE = 1258
PRESSURE_MIN_MPA = 0.45
PRESSURE_MAX_MPA = 5.0


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def scalar_series(row, unit):
    values = np.asarray(row["values"][:], dtype=float).reshape(-1)
    native = row["unit"] if isinstance(row["unit"], str) else text_field(row["unit"])
    return values if native == unit else convert(values, native, unit)


def local_buffer_ledger(rows, path, table, contract):
    get = lambda name, unit: scalar_series(rows[path, name], unit)
    mass, temp = get("stored_mass", "kg"), get("T_I", "K")
    reconstructed = inventory(table, temp, mass, contract["p_environment_Pa"], contract["tank_area_m2"],
                              contract["gravity_m_s2"], contract["reference_temperature_K"],
                              contract["auxiliary_depth_m"])
    stored_energy = get("stored_energy", "J")
    energy_error = float(abs(reconstructed["total"] - stored_energy).max())
    aliases = {
        "volume": float(abs(reconstructed["volume"] - get("volume", "m^3")).max()),
        "level": float(abs(reconstructed["level"] - get("level", "m")).max()),
        "rho": float(abs(reconstructed["rho"] - get("rho_I", "kg/m^3")).max()),
        "u": float(abs(reconstructed["u"] - get("u_I", "J/kg")).max()),
        "u_port": float(abs(reconstructed["u_port"] - get("u_port", "J/kg")).max()),
        "p_A": float(abs(reconstructed["port_pressure"] - get("p_A", "Pa")).max()),
        "capacity": float(abs(reconstructed["capacity"] - get("auxiliary_capacity", "J/K")).max()),
    }
    time = rows[path, "T_I"]["time_s"]
    mass_flow, power = get("mdot_A", "kg/s"), get("Phi_A", "W") + get("Q_H", "W")
    mass_residual = np.r_[0, np.cumsum(mass_flow[1:] * np.diff(time))] - (mass - mass[0])
    energy_residual = np.r_[0, np.cumsum(power[1:] * np.diff(time))] - (reconstructed["total"] - reconstructed["total"][0])
    return dict(mass_end_residual_kg=float(mass_residual[-1]), energy_end_residual_J=float(energy_residual[-1]),
                mass_max_abs_residual_kg=float(abs(mass_residual).max()),
                energy_max_abs_residual_J=float(abs(energy_residual).max()),
                mass_closure_pass=bool(abs(mass_residual).max() <= MASS_ATOL_KG),
                energy_closure_pass=bool(abs(energy_residual).max() <= ENERGY_ATOL_J),
                inventory_alias_pass=bool(energy_error <= ENERGY_ATOL_J and aliases["u"] <= 1e-6 and
                    aliases["u_port"] <= 1e-6 and aliases["p_A"] <= 1e-6 and aliases["capacity"] <= 1e-8 and
                    aliases["volume"] <= 1e-12 and aliases["level"] <= 1e-10 and aliases["rho"] <= 1e-7),
                alias_errors=aliases, stored_energy_reconstruction_max_error_J=energy_error)


def load_rows(folder, expected, stop_time):
    with h5py.File(folder / "observations.mat") as handle:
        rows = named_rows(handle, handle["native"])
        if len(rows) != expected:
            raise ValueError(f"Unexpected native trace count in {folder}: {len(rows)}")
        time = None
        for row in rows.values():
            candidate = row["time_s"][:].reshape(-1)
            if time is None:
                time = candidate
            if not np.array_equal(candidate, time) or not np.isfinite(row["values"][:]).all():
                raise ValueError("Nonidentical or nonfinite diagnostic grid")
        validate_grid(time, 0, stop_time, 0.001)
        materialized = {key: {"unit": text_field(row["unit"]),
                              "time_s": row["time_s"][:].reshape(-1),
                              "values": row["values"][:].reshape(-1)}
                       for key, row in rows.items()}
        return materialized, time


def pressure_rows(rows, require_auxiliary):
    selected = {(path, name): row for (path, name), row in rows.items()
                if name in ("p_I", "p_A")}
    expected = PRESSURE_COMPONENT_COUNT + (4 if require_auxiliary else 0)
    if len(selected) != expected or sum(name == "p_I" for _, name in selected) != PRESSURE_COMPONENT_COUNT:
        raise ValueError("Expected p_I for all fluid stores and the declared p_A buffer traces")
    if require_auxiliary and sum(name == "p_A" for _, name in selected) != 4:
        raise ValueError("Expected p_A for four conservative buffers")
    return selected


def pressure_envelope(rows, assignment, require_auxiliary):
    selected = pressure_rows(rows, require_auxiliary)
    records = []
    for (path, name), row in sorted(selected.items()):
        if name == "p_A" and path not in BUFFERS:
            raise ValueError("Unexpected p_A trace")
        pressure_mpa = scalar_series(row, "Pa") / 1e6
        if name == "p_A":
            settings_path = assignment[path]
        else:
            settings_path = assignment[path]
        with np.errstate(all="raise"):
            finite = bool(np.isfinite(pressure_mpa).all())
        minimum = PRESSURE_MIN_MPA
        maximum = PRESSURE_MAX_MPA
        record = dict(block_path=path, state_name=name, settings_path=settings_path,
                      min_MPa=float(pressure_mpa.min()), max_MPa=float(pressure_mpa.max()),
                      start_MPa=float(pressure_mpa[0]), end_MPa=float(pressure_mpa[-1]),
                      lower_margin_MPa=float(pressure_mpa.min() - minimum),
                      upper_margin_MPa=float(maximum - pressure_mpa.max()), finite=finite,
                      valid_range_MPa=[minimum, maximum],
                      gate_pass=bool(finite and pressure_mpa.min() >= minimum and pressure_mpa.max() <= maximum))
        records.append(record)
    if len(records) != PRESSURE_COMPONENT_COUNT + (4 if require_auxiliary else 0):
        raise ValueError("Pressure record coverage failed")
    fluid = [r for r in records if r["state_name"] == "p_I"]
    return dict(component_count=len(records), physical_state_count=len(fluid), auxiliary_port_pressure_count=sum(r["state_name"] == "p_A" for r in records),
                min_MPa=min(r["min_MPa"] for r in records), max_MPa=max(r["max_MPa"] for r in records),
                min_margin_MPa=min(r["lower_margin_MPa"] for r in records),
                min_upper_margin_MPa=min(r["upper_margin_MPa"] for r in records),
                pressure_range_gate=all(r["gate_pass"] for r in records), records=records)


def component_block(template, rows):
    block = copy.deepcopy(template)
    block["leaf_variables"] = []
    path = block["block_path"]
    for (candidate, name), row in rows.items():
        if candidate == path:
            block["leaf_variables"].append(dict(name=name,
                unit=row["unit"] if isinstance(row["unit"], str) else text_field(row["unit"]),
                time_s=np.asarray(row["time_s"]).reshape(-1), values=np.asarray(row["values"]).reshape(-1)))
    return block


def local_inventory(folder, rows, assignment):
    metadata = read_json(folder / "inventory_metadata.json")
    contracts = {r["block_path"]: r for r in
                 read_json(folder / "buffer_replacement_contract.json")["buffers"]}
    tables = {r["block_path"]: energy_tables(r["parameters"]) for r in metadata["settings_tables"]}
    diagnostics = []
    for template in metadata["storage_blocks"]:
        path = template["block_path"]
        if path not in BUFFERS and path not in CHAMBERS:
            continue
        block = component_block(template, rows)
        table = tables[assignment[path]]
        if template["mask_type"] == "Conservative Buffer (TL)":
            audit = local_buffer_ledger(rows, path, table, contracts[path])
            mass = scalar_series(rows[path, "stored_mass"], "kg")
            flow = scalar_series(rows[path, "mdot_A"], "kg/s")
            energy = scalar_series(rows[path, "stored_energy"], "J")
            energy_input = scalar_series(rows[path, "Phi_A"], "W") + scalar_series(rows[path, "Q_H"], "W")
            diagnostics.append(dict(block_path=path, kind="buffer", mass_end_residual_kg=audit["mass_end_residual_kg"],
                energy_end_residual_J=audit["energy_end_residual_J"], mass_max_abs_residual_kg=audit["mass_max_abs_residual_kg"],
                energy_max_abs_residual_J=audit["energy_max_abs_residual_J"], mass_gate_pass=audit["mass_closure_pass"],
                energy_gate_pass=audit["energy_closure_pass"],
                inventory_alias_pass=audit["inventory_alias_pass"],
                max_abs_flow_kg_s=float(abs(flow).max()),
                integrated_input_energy_J=float(np.sum(energy_input[1:] * np.diff(rows[path, "stored_energy"]["time_s"]))),
                endpoint_mass_change_kg=float(mass[-1] - mass[0]), endpoint_energy_change_J=float(energy[-1] - energy[0])))
        else:
            row, history = custom_ledger(block, table)
            mass = scalar_series(rows[path, "stored_mass"], "kg")
            flow = scalar_series(rows[path, "mdot_A"], "kg/s") + scalar_series(rows[path, "mdot_B"], "kg/s")
            diagnostics.append(dict(block_path=path, kind="chamber", mass_end_residual_kg=float(history["endpoint_mass_residual_kg"][-1]),
                energy_end_residual_J=float(history["endpoint_energy_residual_J"][-1]),
                mass_max_abs_residual_kg=float(abs(history["endpoint_mass_residual_kg"]).max()),
                energy_max_abs_residual_J=float(abs(history["endpoint_energy_residual_J"]).max()),
                mass_gate_pass=bool(abs(history["endpoint_mass_residual_kg"]).max() <= MASS_ATOL_KG),
                energy_gate_pass=bool(abs(history["endpoint_energy_residual_J"]).max() <= ENERGY_ATOL_J),
                inventory_alias_pass=bool(row["stored_mass_alias_max_error_kg"] <= MASS_ATOL_KG and row["stored_energy_alias_max_error_J"] <= ENERGY_ATOL_J),
                max_abs_flow_kg_s=float(abs(flow).max()),
                endpoint_mass_change_kg=float(mass[-1] - mass[0]), endpoint_energy_change_J=float(scalar_series(rows[path, "stored_energy"], "J")[-1] - scalar_series(rows[path, "stored_energy"], "J")[0])))
    if len(diagnostics) != 6:
        raise ValueError("Expected two chambers and four conservative buffers")
    return dict(component_count=6, components=diagnostics,
                all_local_inventory_gates=all(r["mass_gate_pass"] and r["energy_gate_pass"] and r["inventory_alias_pass"] for r in diagnostics),
                max_abs_mass_residual_kg=max(r["mass_max_abs_residual_kg"] for r in diagnostics),
                max_abs_energy_residual_J=max(r["energy_max_abs_residual_J"] for r in diagnostics),
                max_abs_flow_kg_s=max(r["max_abs_flow_kg_s"] for r in diagnostics))


def arm(root, arm_name, expected, stop_time, assignment=None):
    folder = root / arm_name
    rows, time = load_rows(folder, expected, stop_time)
    if assignment is None:
        assignment, count = resolve_domains(read_json(folder / "tl_connectivity.json"))
        if count != 2:
            raise ValueError("Expected two thermal-liquid domains")
    return dict(rows=rows, time=time, assignment=assignment,
                pressure=pressure_envelope(rows, assignment, arm_name == "conservative"),
                inventory=local_inventory(folder, rows, assignment) if arm_name == "conservative" else None)


def compare_runs(low, high):
    deltas = []
    for key in sorted(set(low["rows"]) & set(high["rows"])):
        if key[1] not in ("p_I", "p_A"):
            continue
        a = scalar_series(low["rows"][key], "Pa") / 1e6
        b = scalar_series(high["rows"][key], "Pa") / 1e6
        if not np.array_equal(low["time"], high["time"]):
            raise ValueError("Paired grids differ")
        delta = b - a
        deltas.append(dict(block_path=key[0], state_name=key[1], start_delta_MPa=float(delta[0]),
                           end_delta_MPa=float(delta[-1]), min_delta_MPa=float(delta.min()),
                           max_delta_MPa=float(delta.max()), mean_delta_MPa=float(delta.mean())))
    return dict(pair_count=len(deltas), expected_datum_shift_MPa=0.1, records=deltas,
                endpoint_shift_mean_MPa=float(np.mean([r["end_delta_MPa"] for r in deltas])),
                endpoint_shift_min_MPa=float(min(r["end_delta_MPa"] for r in deltas)),
                endpoint_shift_max_MPa=float(max(r["end_delta_MPa"] for r in deltas)))


def audit(repo, low_root, high_root, stop_time):
    low_record = read_json(low_root / "cold_chamber_execution.json")
    high_record = read_json(high_root / "cold_chamber_execution.json")
    for record, expected in ((low_record, 0.75), (high_record, 0.85)):
        if (not record["collection_pass"] or record["stop_time_s"] != stop_time or record["diagnostic_network_absolute_pressure_MPa"] != expected
                or record["c200_state_imported"] or record["checkpoint_saved"] or record["production_recovery_allowed"]
                or record["periodic_steady_state"] or record["full_device_first_law_verified"]):
            raise ValueError("Diagnostic scope or execution contract failed")
    low_native = arm(low_root, "native", EXPECTED_NATIVE, stop_time)
    high_native = arm(high_root, "native", EXPECTED_NATIVE, stop_time)
    low = arm(low_root, "conservative", EXPECTED_CONSERVATIVE, stop_time, low_native["assignment"])
    high = arm(high_root, "conservative", EXPECTED_CONSERVATIVE, stop_time, high_native["assignment"])
    topology = topology_check(read_json(low_root / "native/tl_connectivity.json"),
                              read_json(low_root / "conservative/tl_connectivity.json"),
                              "ecc_inventory_specific.conservative_chamber")
    return dict(schema="heatdrive_ecc_cold_pressure_envelope_v1", diagnostic_only=True,
                low_datum_MPa=0.75, high_datum_MPa=0.85, stop_time_s=stop_time,
                sample_count=round(stop_time / 0.001) + 1,
                topology=topology, native=dict(low=low_native["pressure"], high=high_native["pressure"],
                    pair_comparison=compare_runs(low_native, high_native)),
                conservative=dict(low=low["pressure"], high=high["pressure"],
                    pair_comparison=compare_runs(low, high), low_inventory=low["inventory"], high_inventory=high["inventory"]),
                pressure_range_gate=all(x["pressure"]["pressure_range_gate"] for x in (low, high, low_native, high_native)),
                local_inventory_gate=low["inventory"]["all_local_inventory_gates"] and high["inventory"]["all_local_inventory_gates"],
                endpoint_comparison_scope="same-path paired onset traces; not a production-cycle continuation",
                full_device_first_law_verified=False, periodic_steady_state=False,
                production_recovery_allowed=False, table4_reproduction_claim=False)


def audit_single(repo, root, datum, stop_time):
    record = read_json(root / "cold_chamber_execution.json")
    if (not record["collection_pass"] or record["stop_time_s"] != stop_time
            or record["diagnostic_network_absolute_pressure_MPa"] != datum
            or record["c200_state_imported"] or record["checkpoint_saved"]
            or record["production_recovery_allowed"] or record["periodic_steady_state"]
            or record["full_device_first_law_verified"]):
        raise ValueError("Single diagnostic scope or execution contract failed")
    native = arm(root, "native", EXPECTED_NATIVE, stop_time)
    conservative = arm(root, "conservative", EXPECTED_CONSERVATIVE, stop_time, native["assignment"])
    topology = topology_check(read_json(root / "native/tl_connectivity.json"),
                              read_json(root / "conservative/tl_connectivity.json"),
                              "ecc_inventory_specific.conservative_chamber")
    return dict(schema="heatdrive_ecc_cold_pressure_envelope_v1", diagnostic_only=True,
                single_datum_MPa=datum, stop_time_s=stop_time,
                sample_count=round(stop_time / 0.001) + 1, topology=topology,
                native=native["pressure"], conservative=conservative["pressure"],
                conservative_inventory=conservative["inventory"],
                pressure_range_gate=native["pressure"]["pressure_range_gate"] and conservative["pressure"]["pressure_range_gate"],
                local_inventory_gate=conservative["inventory"]["all_local_inventory_gates"],
                paired_comparison_performed=False,
                endpoint_comparison_scope="single independent preflight; no cross-datum pairing",
                full_device_first_law_verified=False, periodic_steady_state=False,
                production_recovery_allowed=False, table4_reproduction_claim=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--low-root", type=Path)
    parser.add_argument("--high-root", type=Path)
    parser.add_argument("--single-root", type=Path)
    parser.add_argument("--datum", type=float)
    parser.add_argument("--stop-time", type=float, default=0.2)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Do not overwrite diagnostic evidence")
    if args.stop_time not in (0.2, 1.0, 10.0):
        raise ValueError("This audit supports only the 0.2 s onset, 1.0 s preflight, and 10 s full-cycle windows")
    paired = args.low_root is not None or args.high_root is not None
    single = args.single_root is not None
    if paired == single or (paired and (args.low_root is None or args.high_root is None)):
        raise ValueError("Provide either both --low-root/--high-root or --single-root")
    if single:
        if args.datum not in (0.75, 0.85):
            raise ValueError("Single diagnostic datum must be 0.75 or 0.85 MPa")
        result = audit_single(args.repo, args.single_root, args.datum, args.stop_time)
    else:
        result = audit(args.repo, args.low_root, args.high_root, args.stop_time)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    rows = []
    if "conservative_inventory" in result:
        for r in result["conservative_inventory"]["components"]:
            rows.append(dict(arm="single", **r))
    else:
        for arm_name in ("low", "high"):
            for r in result["conservative"][arm_name + "_inventory"]["components"]:
                rows.append(dict(arm=arm_name, **r))
    with args.output.with_suffix(".csv").open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=sorted({k for row in rows for k in row}), extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
    print(json.dumps({k: v for k, v in result.items() if k not in ("native", "conservative")}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
