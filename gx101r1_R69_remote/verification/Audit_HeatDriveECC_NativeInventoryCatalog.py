"""Catalog native storage variables and port semantics, without authorizing a run.

Three-step residuals below are numerical diagnostics, not cycle/closure gates.
Quasisteady pipe storage cannot be reconstructed without rho_nominal metadata.
"""
import argparse
import csv
import hashlib
import json
from collections import Counter
from pathlib import Path

import numpy as np


UNITS = {
    "1": ("1", 1),
    "K": ("K", 1), "kg": ("kg", 1), "m^3": ("m^3", 1),
    "kg/s": ("kg/s", 1), "kg/m^3": ("kg/m^3", 1),
    "Pa": ("Pa", 1), "bar": ("Pa", 1e5), "MPa": ("Pa", 1e6),
    "W": ("W", 1), "kW": ("W", 1e3),
    "J": ("J", 1),
    "J/kg": ("J/kg", 1), "kJ/kg": ("J/kg", 1e3),
    "J/(K*kg)": ("J/(K*kg)", 1), "kJ/(K*kg)": ("J/(K*kg)", 1e3),
}


def convert(values, native, target):
    if native not in UNITS or UNITS[native][0] != target:
        raise ValueError(f"Unsupported conversion: {native} -> {target}")
    result = np.asarray(values, dtype=float) * UNITS[native][1]
    if not np.isfinite(result).all():
        raise ValueError("Nonfinite native quantity")
    return result


def audit_block(block):
    kind = block["mask_type"]
    allowed = {"Pipe (TL)", "Tank (TL)", "Constant Volume Chamber (TL)", "Thermal Mass"}
    if kind not in allowed:
        raise ValueError(f"Unregistered storage class: {kind}")
    leaves = {row["name"]: row for row in block["leaf_variables"]}
    if len(leaves) != len(block["leaf_variables"]):
        raise ValueError("Duplicate native variable")
    time = np.asarray(next(iter(leaves.values()))["time_s"], dtype=float)
    if time.ndim != 1 or time.size < 2 or not np.isfinite(time).all() or np.any(np.diff(time) <= 0):
        raise ValueError("Native samples must be finite and strictly increasing")

    def series(name, unit):
        row = leaves[name]
        if not np.array_equal(row["time_s"], time):
            raise ValueError("Mismatched native time grids")
        result = convert(row["values"], row["unit"], unit)
        if result.shape != time.shape:
            raise ValueError("Expected one native scalar per sample")
        return result

    def integral(values):
        return float(np.sum((values[1:] + values[:-1]) * .5 * np.diff(time)))

    temp = series("T" if kind == "Thermal Mass" else "T_I", "K")
    row = {
        "block_path": block["block_path"], "mask_type": kind,
        "reference_block": block["reference_block"], "sample_count": int(time.size),
        "start_s": float(time[0]), "end_s": float(time[-1]),
        "native_temperature_start_K": float(temp[0]),
        "native_temperature_change_K": float(temp[-1] - temp[0]),
        "native_variable_units": {name: leaf["unit"] for name, leaf in leaves.items()},
        "mask_parameters": block["mask_parameters"],
        "equation_matched_cycle_closure_verified": False,
        "periodic_state_verified": False,
    }
    if kind == "Thermal Mass":
        mode = block["model_modes"]["mass_type"]
        if mode not in ("1", "foundation.enum.constant_variable.constant"):
            raise ValueError("Only verified constant Thermal Mass is supported")
        parameter = block["mask_parameters"]["mass"]
        mass = float(convert(parameter["value"], parameter["unit"], "kg"))
        parameter = block["mask_parameters"]["sp_heat"]
        cp = float(convert(parameter["value"], parameter["unit"], "J/(K*kg)"))
        if cp <= 0 or mass <= 0:
            raise ValueError("This diagnostic requires positive fixed thermal mass and cp")
        net_J = integral(series("Q", "W"))
        delta_U = float(mass * cp * (temp[-1] - temp[0]))
        row.update(storage_basis="constant-mass sensible energy only; latent energy is external to this block",
                   integrated_net_energy_J=net_J, sensible_energy_change_J=delta_U,
                   short_window_sensible_residual_J=net_J - delta_U)
        return row

    ports = sorted(name[5:] for name in leaves if name.startswith("mdot_"))
    if not ports or any("Phi_" + port not in leaves for port in ports):
        raise ValueError("Every mass-flow port needs a native energy-flow signal")
    mdot = sum((series("mdot_" + port, "kg/s") for port in ports), np.zeros_like(time))
    phi = sum((series("Phi_" + port, "W") for port in ports), np.zeros_like(time))
    net_J = integral(phi + series("Q_H", "W"))
    row.update(ports=ports, integrated_net_mass_kg=integral(mdot),
               integrated_net_energy_J=net_J, positive_flow_direction="into component")
    if kind == "Pipe (TL)":
        if block["model_modes"]["dynamic_compressibility"] != "false":
            raise ValueError("Expected the verified quasisteady pipe mode")
        row.update(storage_basis="verified quasisteady mode: M=rho_nominal*V, U=M*u_I",
                   nominal_density_reconstructed=False,
                   legacy_rho_I_volume_inventory_is_equation_matched=False)
    elif kind == "Constant Volume Chamber (TL)":
        row["storage_basis"] = "compressible fixed volume: M=rho_I*V, U=M*u_I"
    else:
        mass = series("mass", "kg")
        volume = series("volume", "m^3")
        pressure = series("p_I", "Pa")
        u = series("u_I", "J/kg")
        h = series("h_I", "J/kg")
        delta_U = float(mass[-1] * u[-1] - mass[0] * u[0])
        delta_H = float(mass[-1] * h[-1] - mass[0] * h[0])
        pressure_work = float(np.sum(.5 * (pressure[1:] + pressure[:-1]) * np.diff(volume)))
        row.update(storage_basis="variable-volume tank: inspect delta(M*u), integral(p dV), and delta(M*h) separately",
                   mass_start_kg=float(mass[0]), mass_end_kg=float(mass[-1]),
                   short_window_mass_residual_kg=integral(mdot) - float(mass[-1] - mass[0]),
                   internal_energy_change_J=delta_U, enthalpy_change_J=delta_H,
                   pressure_volume_work_J=pressure_work,
                   pressure_range_Pa=float(np.ptp(pressure)),
                   enthalpy_identity_max_abs_J=float(np.max(np.abs(mass * h - mass * u - pressure * volume))),
                   short_window_U_only_residual_J=net_J - delta_U,
                   short_window_U_plus_pdV_residual_J=net_J - delta_U - pressure_work,
                   short_window_H_residual_J=net_J - delta_H)
    return row


def audit_probe(probe, metadata):
    if (probe.get("schema") != "heatdrive_ecc_native_inventory_probe_v2"
            or not probe["collection_pass"] or not probe["strict_restore_pass"]
            or probe["probe_state_may_resume"]):
        raise ValueError("Require a successful strictly restored, nonresumable v2 probe")
    blocks = probe["storage_blocks"]
    if (metadata["schema"] != "heatdrive_ecc_storage_model_metadata_v1"
            or metadata["source_result_sha256"] != probe["source_result_sha256"]
            or metadata["source_checkpoint_sha256"] != probe["source_checkpoint_sha256"]
            or metadata["simulation_run"] or metadata["checkpoint_saved"]):
        raise ValueError("Model metadata must match the strictly restored probe source")
    modes = {row["block_path"]: row for row in metadata["component_modes"]}
    paths = [block["block_path"] for block in blocks]
    if len(set(paths)) != len(paths) or len(paths) != probe["storage_block_count"]:
        raise ValueError("Duplicate or missing storage component")
    if set(paths) != set(modes) or len(modes) != len(metadata["component_modes"]):
        raise ValueError("Metadata and probe component inventories differ")
    for block in blocks:
        mode = modes[block["block_path"]]
        if mode["mask_type"] != block["mask_type"]:
            raise ValueError("Storage mask type changed")
        block["model_modes"] = mode["parameters"]
    comparisons = probe["buffer_temperature_comparison"]
    if len(comparisons) != 4 or len({r["tank_path"] for r in comparisons}) != 4:
        raise ValueError("Need four independent tank-port comparisons")
    for row in comparisons:
        measured = np.asarray(row["workspace_signal_K"], dtype=float)
        port = np.asarray(row["port_A_T_K"], dtype=float)
        internal = np.asarray(row["internal_T_I_K"], dtype=float)
        if (measured.shape != port.shape or measured.shape != internal.shape
                or not np.isfinite([measured, port, internal]).all()
                or not np.array_equal(measured, port)):
            raise ValueError("Workspace temperature must match native port A in this probe")
    return {
        "schema": "heatdrive_ecc_native_inventory_catalog_v1",
        "source_result_sha256": probe["source_result_sha256"],
        "source_checkpoint_sha256": probe["source_checkpoint_sha256"],
        "component_count": len(blocks), "component_counts": dict(Counter(b["mask_type"] for b in blocks)),
        "scope": "Named native quantities, units and short-window diagnostics; not a 995-coordinate Solver Configuration mapping.",
        "comparison_scope": "same simulation samples; not a comparison across a terminal event",
        "all_four_workspace_signals_match_port_A": True,
        "buffer_temperature_comparison": comparisons,
        "components": [audit_block(block) for block in blocks],
        "equation_matched_cycle_closure_verified": False,
        "complete_internal_state_periodicity_verified": False,
        "production_continuation_allowed": False,
        "diagnostic_checkpoint_recovery_allowed": False,
        "table4_reproduction_claim": False,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("probe", type=Path)
    parser.add_argument("--model-metadata", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    data = args.probe.read_bytes()
    metadata = args.model_metadata.read_bytes()
    result = audit_probe(json.loads(data.decode("utf-8-sig")), json.loads(metadata.decode("utf-8-sig")))
    result["model_metadata_sha256"] = hashlib.sha256(metadata).hexdigest().upper()
    result["probe_json_sha256"] = hashlib.sha256(data).hexdigest().upper()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    rows = [{k: v for k, v in row.items() if not isinstance(v, (dict, list))} for row in result["components"]]
    with args.output.with_suffix(".csv").open("w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(dict.fromkeys(k for row in rows for k in row)))
        writer.writeheader()
        writer.writerows(rows)
    print(json.dumps({k: result[k] for k in ("component_count", "component_counts",
          "all_four_workspace_signals_match_port_A", "equation_matched_cycle_closure_verified")}))
