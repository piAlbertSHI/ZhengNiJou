"""Locate retained-sample residuals without changing physical closure gates.

Compare identical interval sums with the existing complete-cycle ledger first.
Stage/event partitions retain every interval. Reconstructed derivatives use the
native equations, not an alternative trajectory or a new simulation.
"""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_NativeSystemLedger import stage_endpoints
from Audit_HeatDriveECC_NativeWindowLedger import NativeWindowLedger, evaluate_component
from Audit_HeatDriveECC_NativeWindowPackets import load_packet
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field


def interval_integrals(coefficient, coordinate):
    coefficient, coordinate = np.asarray(coefficient), np.asarray(coordinate)
    if (coefficient.ndim != 1 or coefficient.shape != coordinate.shape or coefficient.size < 2
            or not np.isfinite([coefficient, coordinate]).all()):
        raise ValueError("Require matching finite sample arrays")
    return .5 * (coefficient[:-1] + coefficient[1:]) * np.diff(coordinate)


def backward_euler_integrals(coefficient, coordinate):
    interval_integrals(coefficient, coordinate)
    return np.asarray(coefficient)[1:] * np.diff(coordinate)


def event_mask(time, endpoints, half_width_s):
    if not np.isfinite(half_width_s) or half_width_s <= 0:
        raise ValueError("Event half-width must be positive")
    midpoint = .5 * (time[:-1] + time[1:])
    return np.min(abs(midpoint[:, None] - time[endpoints][None, :]), axis=1) <= half_width_s


def component_terms(block, table):
    reference = evaluate_component(block, table)
    kind = block["mask_type"]
    if kind not in ("Tank (TL)", "Constant Volume Chamber (TL)"):
        raise ValueError("Only the six variable-storage diagnostic components are supported")
    leaves = {r["name"]: r for r in block["leaf_variables"]}
    time = np.asarray(leaves["T_I"]["time_s"])

    def series(name, unit):
        return convert(leaves[name]["values"], leaves[name]["unit"], unit)

    temp, pressure = series("T_I", "K"), series("p_I", "Pa")
    rho, h = series("rho_I", "kg/m^3"), series("h_I", "J/kg")
    coords = np.column_stack((temp, pressure))
    cp, alpha, beta = (table[name](coords) for name in ("cp", "alpha", "beta"))
    ports = sorted(name[5:] for name in leaves if name.startswith("mdot_"))
    mdot = sum((series("mdot_" + port, "kg/s") for port in ports), np.zeros_like(time))
    flow = sum((series("Phi_" + port, "W") for port in ports), np.zeros_like(time)) + series("Q_H", "W")
    terms = dict(energy_flow_J=interval_integrals(flow, time), mass_flow_kg=interval_integrals(mdot, time))
    terms["BE_energy_flow_J"] = backward_euler_integrals(flow, time)
    terms["BE_mass_flow_kg"] = backward_euler_integrals(mdot, time)
    if kind == "Tank (TL)":
        mass = series("mass", "kg")
        terms["energy_temperature_J"] = interval_integrals(mass * cp, temp)
        terms["energy_mass_transport_J"] = interval_integrals(h, mass)
        terms["mass_accumulation_kg"] = np.diff(mass)
        terms["BE_energy_accumulation_J"] = (backward_euler_integrals(mass * cp, temp)
                                              + backward_euler_integrals(h, mass))
        terms["BE_mass_accumulation_kg"] = np.diff(mass)
        dTdt = (flow - h * mdot) / (mass * cp)
        dpdt = np.zeros_like(time)
    else:
        parameter = block["mask_parameters"]["volume"]
        volume = float(convert(parameter["value"], parameter["unit"], "m^3"))
        mass = rho * volume
        dMdp, dMdT = mass / beta, -mass * alpha
        dUdp = (rho * h / beta - temp * alpha) * volume
        dUdT = (cp - h * alpha) * mass
        determinant = dMdp * dUdT - dMdT * dUdp
        if np.any(determinant <= 0) or not np.isfinite(determinant).all():
            raise ValueError("Invalid storage derivative system")
        dpdt = (mdot * dUdT - dMdT * flow) / determinant
        dTdt = (dMdp * flow - dUdp * mdot) / determinant
        terms["energy_pressure_J"] = interval_integrals(dUdp, pressure)
        terms["energy_temperature_J"] = interval_integrals(dUdT, temp)
        terms["mass_pressure_kg"] = interval_integrals(dMdp, pressure)
        terms["mass_temperature_kg"] = interval_integrals(dMdT, temp)
        terms["mass_accumulation_kg"] = terms["mass_pressure_kg"] + terms["mass_temperature_kg"]
        terms["BE_energy_accumulation_J"] = (backward_euler_integrals(dUdp, pressure)
                                              + backward_euler_integrals(dUdT, temp))
        terms["BE_mass_pressure_kg"] = backward_euler_integrals(dMdp, pressure)
        terms["BE_mass_temperature_kg"] = backward_euler_integrals(dMdT, temp)
        terms["BE_mass_accumulation_kg"] = terms["BE_mass_pressure_kg"] + terms["BE_mass_temperature_kg"]
    zero = np.zeros(len(time) - 1)
    terms["energy_accumulation_J"] = (terms["energy_temperature_J"] + terms.get("energy_pressure_J", zero)
                                      + terms.get("energy_mass_transport_J", zero))
    terms["energy_residual_J"] = terms["energy_flow_J"] - terms["energy_accumulation_J"]
    terms["mass_residual_kg"] = terms["mass_flow_kg"] - terms["mass_accumulation_kg"]
    terms["BE_energy_residual_J"] = terms["BE_energy_flow_J"] - terms["BE_energy_accumulation_J"]
    terms["BE_mass_residual_kg"] = terms["BE_mass_flow_kg"] - terms["BE_mass_accumulation_kg"]
    terms["temperature_rate_quadrature_error_K"] = interval_integrals(dTdt, time) - np.diff(temp)
    terms["pressure_rate_quadrature_error_Pa"] = interval_integrals(dpdt, time) - np.diff(pressure)
    terms["temperature_change_K"] = np.diff(temp)
    terms["pressure_change_Pa"] = np.diff(pressure)
    terms["endpoint_mass_change_kg"] = np.diff(mass)
    mapping = {"energy_flow_J": "energy_flow_integral_J", "energy_accumulation_J": "energy_equation_accumulation_J",
               "energy_residual_J": "energy_residual_J", "mass_flow_kg": "mass_flow_integral_kg",
               "mass_accumulation_kg": "mass_equation_accumulation_kg", "mass_residual_kg": "mass_residual_kg"}
    for key, field in mapping.items():
        value = float(terms[key].sum())
        limit = (1e-12 if key.endswith("kg") else 1e-9) + 1e-11 * abs(reference[field])
        if not np.isfinite(value) or abs(value - reference[field]) > limit:
            raise ValueError("Interval decomposition does not match the original ledger")
    return time, terms, reference


def totals(terms, selected):
    result = {name: float(values[selected].sum()) for name, values in terms.items()}
    result["absolute_energy_residual_sum_J"] = float(abs(terms["energy_residual_J"][selected]).sum())
    result["absolute_mass_residual_sum_kg"] = float(abs(terms["mass_residual_kg"][selected]).sum())
    if "BE_energy_residual_J" in terms:
        result["BE_absolute_energy_residual_sum_J"] = float(abs(terms["BE_energy_residual_J"][selected]).sum())
        result["BE_absolute_mass_residual_sum_kg"] = float(abs(terms["BE_mass_residual_kg"][selected]).sum())
    return result


def summarize(time, terms, endpoints):
    whole = totals(terms, slice(None))
    stages = [dict(stage=k, start_s=float(time[a]), stop_s=float(time[b]), **totals(terms, slice(a, b)))
              for k, (a, b) in enumerate(zip(endpoints[:-1], endpoints[1:]), 1)]
    events = []
    for width in (.01, .05, .1):
        selected = event_mask(time, endpoints, width)
        inside, outside = totals(terms, selected), totals(terms, ~selected)
        for name in whole:
            if not np.isclose(whole[name], inside[name] + outside[name], atol=1e-12, rtol=1e-10):
                raise ValueError("Event partition dropped or duplicated an interval")
        events.append(dict(half_width_s=width, interval_count=int(selected.sum()),
                           sampled_duration_s=float(np.diff(time)[selected].sum()), inside=inside, outside=outside))
    ranked = np.argsort(abs(terms["energy_residual_J"]))[::-1][:10]
    peaks = [dict(start_s=float(time[k]), stop_s=float(time[k + 1]),
                  **{name: float(values[k]) for name, values in terms.items()}) for k in ranked]
    return dict(whole_cycle=whole, stages=stages, scheduled_switch_neighborhoods=events,
                largest_energy_residual_intervals=peaks, interval_partition_pass=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("cycle-root", "topology", "probe", "metadata", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Do not overwrite diagnostic evidence")
    inputs = {name: getattr(args, name) for name in ("topology", "probe", "metadata")}
    inputs.update(packet=args.cycle_root / "native_window.mat", physical=args.cycle_root / "segment_physical.mat",
                  ledger=args.cycle_root / "native_ledger.json", mechanism=args.cycle_root / "cycle_audit.json")
    original = json.loads(inputs["ledger"].read_text(encoding="utf-8-sig"))
    mechanism = json.loads(inputs["mechanism"].read_text(encoding="utf-8-sig"))
    hashes = {name: sha256(path) for name, path in inputs.items()}
    if (hashes["packet"] != original["packet_sha256"] or not original["ledger_computation_pass"]
            or not original["one_cycle_native_coverage_verified"] or original["production_recovery_allowed"]
            or not mechanism["strict_restore_pass"] or not mechanism["mechanism_pass"]
            or mechanism["production_recovery_allowed"]
            or any(hashes[name] != original["input_sha256"][name] for name in ("topology", "probe", "metadata"))):
        raise ValueError("Source identity or diagnostic scope failed")
    ledger = NativeWindowLedger(*(json.loads(inputs[n].read_text(encoding="utf-8-sig"))
                                  for n in ("topology", "probe", "metadata")))
    header, streams = load_packet(inputs["packet"])
    if any(header[k] != v for k, v in ledger.source.items()):
        raise ValueError("Native packet and source model differ")
    native = streams["native"]
    if set(native) != ledger.keys:
        raise ValueError("Native inventory differs from the frozen model")
    with h5py.File(inputs["physical"], "r") as physical:
        durations = physical["options/schedule/stage_durations_s"][:].reshape(-1)
        solver = physical["options/simscape"]
        solver_options = dict(enabled=bool(solver["local_solver_enabled"][0, 0]),
                              choice=text_field(solver["local_solver_choice"]),
                              sample_time_s=float(solver["local_solver_sample_time_s"][0, 0]))
        if (not solver_options["enabled"] or solver_options["choice"] != "NE_BACKWARD_EULER_ADVANCER"
                or solver_options["sample_time_s"] != header["fixed_step_s"]):
            raise ValueError("BE diagnostic requires the recorded local solver on the native grid")
    time = next(iter(native.values()))["time"]
    endpoints = stage_endpoints(durations, header["fixed_step_s"], len(time))
    rows = []
    old_rows = {r["block_path"]: r for r in original["components"]}
    for path, template in ledger.templates.items():
        if template["mask_type"] not in ("Tank (TL)", "Constant Volume Chamber (TL)"):
            continue
        block = {k: v for k, v in template.items() if k != "leaf_variables"}
        if any(native[path + "::" + leaf["name"]]["unit"] != leaf["unit"] for leaf in template["leaf_variables"]):
            raise ValueError("Native unit changed")
        block["leaf_variables"] = [dict(name=leaf["name"], unit=leaf["unit"], time_s=time,
            values=native[path + "::" + leaf["name"]]["values"][:, 0]) for leaf in template["leaf_variables"]]
        _, terms, reference = component_terms(block, ledger.tables[ledger.basis[path]["settings_path"]])
        for name in ("energy_residual_J", "mass_residual_kg"):
            if reference[name] != old_rows[path][name]:
                raise ValueError("Recomputed component does not match frozen cycle ledger")
        rows.append(dict(block_path=path, mask_type=template["mask_type"], **summarize(time, terms, endpoints)))
    if len(rows) != 6:
        raise ValueError("Require four tanks and two chambers")
    water = [r for r in rows if r["block_path"].split("/")[-1] in
             ("SHEXFluidBuffer", "SMAHotFluidBuffer", "SMA_PumpInletConnectingPipeVolume", "SMA_PumpOutletConnectingPipeVolume")]
    water_stages = []
    for index in range(4):
        stage = [r["stages"][index] for r in water]
        chambers = [r["stages"][index] for r in water if r["mask_type"] == "Constant Volume Chamber (TL)"]
        water_stages.append(dict(stage=index + 1,
            BE_four_component_mass_flow_kg=sum(s["BE_mass_flow_kg"] for s in stage),
            four_component_endpoint_mass_change_kg=sum(s["endpoint_mass_change_kg"] for s in stage),
            chamber_BE_temperature_mass_kg=sum(s["BE_mass_temperature_kg"] for s in chambers),
            chamber_BE_pressure_mass_kg=sum(s["BE_mass_pressure_kg"] for s in chambers),
            chamber_endpoint_mass_change_kg=sum(s["endpoint_mass_change_kg"] for s in chambers)))
    result = dict(schema="heatdrive_ecc_native_residual_localization_v2", components=rows,
                  start_s=float(time[0]), stop_s=float(time[-1]), sample_count=len(time), stage_durations_s=durations.tolist(),
                  input_sha256=hashes, source=ledger.source, simulation_run=False,
                  sma_water_stage_mass_budget=water_stages,
                  original_ledger_recalculation_pass=True, interval_partition_pass=True,
                  local_solver_options=solver_options,
                  derivative_scope="native equation inversion at retained major samples; trapezoid and recorded local BE discretizations kept separate",
                  BE_scope="right-endpoint differential-equation residual, not a replacement for continuous thermodynamic energy closure or step convergence",
                  event_scope="fixed 10/50/100 ms half-width around scheduled stage boundaries, clipped to saved cycle; no endpoint removed",
                  physical_root_cause_verified=False, equation_matched_cycle_closure_verified=False,
                  full_internal_periodicity_verified=False, production_recovery_allowed=False, table4_reproduction_claim=False)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k not in ("components", "input_sha256")}, indent=2))


if __name__ == "__main__":
    main()
