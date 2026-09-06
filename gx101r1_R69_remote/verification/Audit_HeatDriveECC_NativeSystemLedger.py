"""Assemble the measured no-load thermal boundary and native component ledger.

This is a diagnostic coefficient-equation balance, not complete-device COP or
permission to resume production. Nonzero cold-load cases require another boundary.
"""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_NativeAccumulation import path_integral
from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_NativeWindowPackets import load_packet
from Audit_HeatDriveECC_NativeWindowLedger import validate_grid
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field


def align_steps(native, physical, start, stop, dt):
    validate_grid(native, start, stop, dt)
    validate_grid(physical, start, stop, dt)
    if not np.array_equal(np.rint((native - start) / dt), np.rint((physical - start) / dt)):
        raise ValueError("Physical and native integer step indices differ")
    return dict(sample_count=len(native), bitwise_time_equal=bool(np.array_equal(native.view(np.uint64), physical.view(np.uint64))),
                differing_time_samples=int(np.count_nonzero(native != physical)),
                max_time_difference_s=float(np.max(abs(native - physical))),
                fixed_step_indices_equal=True, original_time_axes_retained=True, samples_interpolated=False,
                scope="assembler alignment only; the shared physical extractor retains its existing grid interpolation")


def stage_endpoints(durations, dt, sample_count):
    durations = np.asarray(durations, dtype=float)
    if (durations.shape != (4,) or not np.isfinite(durations).all() or np.any(durations <= 0)
            or not np.isfinite(dt) or dt <= 0 or sample_count < 5):
        raise ValueError("Require four finite positive stages and a positive fixed step")
    steps = np.concatenate(([0.], np.cumsum(durations))) / dt
    rounded = np.rint(steps)
    if (np.any(abs(steps - rounded) > 16 * np.spacing(np.maximum(abs(steps), 1)))
            or np.any(np.diff(rounded) < 1) or rounded[-1] != sample_count - 1):
        raise ValueError("Stage boundaries must align to and cover the complete cycle grid")
    return rounded.astype(int)


def assemble(time, physical, native_energy, native_mass, ledger, cold_load_W, native_time=None):
    if native_time is None:
        native_time = time
    if cold_load_W != 0 or ledger["schema"] != "heatdrive_ecc_native_window_ledger_v1" or not ledger["ledger_computation_pass"]:
        raise ValueError("Require a computed native ledger and the measured no-load boundary")
    required = ("Q_SHEX_source_to_sink_W", "Q_HHEX_sink_to_ambient_W", "Q_CHEX_fixed_source_W",
                "Q_CHEX_load_to_sink_W", "P_pressure_source_native_W", "pump_power_SMA_W", "pump_power_SE_W")
    for name in required:
        if physical[name].shape != time.shape or not np.isfinite(physical[name]).all():
            raise ValueError("Incomplete or nonfinite boundary signal")
    for values in (native_energy, native_mass):
        if values.shape != time.shape or not np.isfinite(values).all():
            raise ValueError("Incomplete native flow sum")
    if np.max(abs(physical["Q_CHEX_load_to_sink_W"])) > 1e-9:
        raise ValueError("Nonzero load branch requires its external heater/ColdLoadMass audit")
    q_constitutive = np.zeros_like(time)
    for name in ("Q_SMA_constitutive_21_W", "Q_SE_constitutive_21_W"):
        values = physical[name]
        if values.shape != (len(time), 21) or not np.isfinite(values).all():
            raise ValueError("Need both measured 21-node constitutive source arrays")
        q_constitutive += values.sum(axis=1)
    if np.max(abs(physical["P_pressure_source_native_W"])) > 1e-9:
        raise ValueError("Only the verified zero thermal-power pressure-source mode is covered")
    external = (physical["Q_SHEX_source_to_sink_W"] - physical["Q_HHEX_sink_to_ambient_W"]
                - physical["Q_CHEX_fixed_source_W"])
    total_input = external + q_constitutive
    rows = ledger["components"]
    if len(rows) != 119 or len({r["block_path"] for r in rows}) != 119:
        raise ValueError("Incomplete or duplicate native storage inventory")
    energy_accumulation = sum(r["energy_equation_accumulation_J"] for r in rows)
    energy_input = path_integral(total_input, time)
    source_J = path_integral(physical["Q_SHEX_source_to_sink_W"], time)
    rejected_J = path_integral(physical["Q_HHEX_sink_to_ambient_W"], time)
    mass_endpoint = sum(r.get("mass_endpoint_change_kg", 0) for r in rows)
    mass_coefficient = sum(r.get("mass_equation_accumulation_kg", 0) for r in rows)
    mass_start = sum(r.get("mass_start_kg", 0) for r in rows)
    duration = float(time[-1] - time[0])
    return dict(schema="heatdrive_ecc_native_system_ledger_diagnostic_v1",
                window_start_s=float(time[0]), window_stop_s=float(time[-1]), sample_count=len(time),
                source_input_J=source_J, ambient_rejection_J=rejected_J,
                fixed_CHEX_input_J=-path_integral(physical["Q_CHEX_fixed_source_W"], time),
                external_thermal_net_input_J=path_integral(external, time),
                measured_constitutive_net_input_J=path_integral(q_constitutive, time),
                native_component_net_input_J=path_integral(native_energy, native_time),
                spatial_energy_boundary_identity_rms_W=float(np.sqrt(np.mean((total_input - native_energy) ** 2))),
                spatial_mass_boundary_identity_max_kg_s=float(np.max(abs(native_mass))),
                native_equation_accumulation_J=energy_accumulation,
                native_equation_energy_residual_J=energy_input - energy_accumulation,
                native_equation_energy_residual_relative=abs(energy_input - energy_accumulation) / max(abs(source_J), abs(rejected_J), duration),
                native_mass_start_kg=mass_start, native_endpoint_mass_change_kg=mass_endpoint,
                native_coefficient_mass_accumulation_kg=mass_coefficient,
                integrated_net_mass_flow_kg=path_integral(native_mass, native_time),
                endpoint_mass_drift_relative=abs(mass_endpoint) / mass_start,
                pressure_source_thermal_power_J=path_integral(physical["P_pressure_source_native_W"], time),
                engineering_pump_work_proxy_J=path_integral(physical["pump_power_SMA_W"] + physical["pump_power_SE_W"], time),
                buffer_changes=[dict(block_path=r["block_path"], delta_T_K=r["temperature_end_K"] - r["temperature_start_K"],
                                     delta_mass_kg=r["mass_endpoint_change_kg"],
                                     relative_mass_change=r["mass_endpoint_change_kg"] / r["mass_start_kg"])
                                for r in rows if r["mask_type"] == "Tank (TL)"],
                scope="119 native storage components, measured no-load thermal boundaries; latent/mechanical sources retained explicitly",
                latent_heat_double_counted=False, cold_load_boundary_supported="no_load_only",
                equation_matched_cycle_closure_verified=False, component_residuals_require_review=True,
                full_internal_periodicity_verified=False, full_device_first_law_verified=False,
                production_recovery_allowed=False, table4_reproduction_claim=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cycle-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Do not overwrite system ledger evidence")
    paths = {"packet": args.cycle_root / "native_window.mat", "physical": args.cycle_root / "segment_physical.mat",
             "ledger": args.cycle_root / "native_ledger.json", "mechanism": args.cycle_root / "cycle_audit.json"}
    ledger = json.loads(paths["ledger"].read_text(encoding="utf-8-sig"))
    mechanism = json.loads(paths["mechanism"].read_text(encoding="utf-8-sig"))
    if not mechanism["strict_restore_pass"] or not mechanism["mechanism_pass"] or mechanism["production_recovery_allowed"]:
        raise ValueError("Require strictly restored mechanism-valid diagnostic data")
    if sha256(paths["packet"]) != ledger["packet_sha256"]:
        raise ValueError("Native ledger input changed")
    header, streams = load_packet(paths["packet"])
    native = streams["native"]
    time = next(iter(native.values()))["time"]
    with h5py.File(paths["physical"], "r") as file:
        group = file["physical"]
        raw_time = group["time_s"][:].reshape(-1)
        time_alignment = align_steps(time, raw_time, header['start_s'], header['stop_s'], header['fixed_step_s'])
        physical = {name: value[:].T if "constitutive_21" in name else value[:].reshape(-1)
                    for name, value in group.items() if name.startswith(("Q_", "pump_power_", "P_pressure_"))}
        load = float(file["options/system/cold_load_heat_W"][0, 0])
        stage_durations = file["options/schedule/stage_durations_s"][:].reshape(-1)
        if text_field(file["options/system/cold_load_mode"]) != "no_load":
            raise ValueError("Unsupported external load boundary")
    energy, mass = np.zeros_like(time), np.zeros_like(time)
    for row in ledger["components"]:
        path = row["block_path"]
        leaves = {key.split("::", 1)[1]: trace for key, trace in native.items() if trace["block_path"] == path}
        def series(name, unit):
            leaf = leaves[name]
            return convert(leaf["values"][:, 0], leaf["unit"], unit)
        if row["mask_type"] == "Thermal Mass":
            energy += series("Q", "W")
        else:
            ports = [name[5:] for name in leaves if name.startswith("mdot_")]
            for port in ports:
                mass += series("mdot_" + port, "kg/s")
                energy += series("Phi_" + port, "W")
            energy += series("Q_H", "W")
    result = assemble(raw_time, physical, energy, mass, ledger, load, time)
    result["time_alignment"] = time_alignment
    endpoints = stage_endpoints(stage_durations, header["fixed_step_s"], len(time))
    transport = []
    for row in ledger["components"]:
        if row["mask_type"] != "Tank (TL)":
            continue
        path = row["block_path"]
        mass_trace = native[path + "::mass"]
        mass_values = convert(mass_trace["values"][:, 0], mass_trace["unit"], "kg")
        flow_keys = [k for k, v in native.items() if v["block_path"] == path and k.split("::", 1)[1].startswith("mdot_")]
        mass_flow = sum((convert(native[k]["values"][:, 0], native[k]["unit"], "kg/s") for k in flow_keys), np.zeros_like(time))
        for stage, (begin, end) in enumerate(zip(endpoints[:-1], endpoints[1:]), 1):
            selected = slice(begin, end + 1)
            port_integrals = {key.split("::", 1)[1]: path_integral(
                convert(native[key]["values"][selected, 0], native[key]["unit"], "kg/s"), time[selected])
                for key in sorted(flow_keys)}
            transport.append(dict(block_path=path, stage=stage, start_s=float(time[begin]), stop_s=float(time[end]),
                                  integrated_mass_into_tank_kg=path_integral(mass_flow[selected], time[selected]),
                                  port_integrated_mass_into_tank_kg=port_integrals,
                                  native_mass_change_kg=float(mass_values[end] - mass_values[begin])))
    result["buffer_stage_mass_transport"] = transport
    result["stage_transport_scope"] = "actual four-stage schedule; trapezoid quadrature includes each shared endpoint; incoming sign at each tank port"
    result["input_sha256"] = {name: sha256(path) for name, path in paths.items()}
    result["source_result_sha256"] = header["source_result_sha256"]
    result["source_checkpoint_sha256"] = header["source_checkpoint_sha256"]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
