"""Cold active-flow EOS/enthalpy trials with compact, non-recoverable diagnostics."""
import argparse
from dataclasses import replace
import json
from pathlib import Path
import platform
import subprocess
import time
import traceback

import numpy as np
import scipy

from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Reference_HeatDriveECC_ConservativeTransport import Bed, bs3_step
from Reference_HeatDriveECC_EnthalpyTransport import TabulatedEOS, EnthalpyBed
from Run_HeatDriveECC_ConservativeTransport import write_json
from Run_HeatDriveECC_LimitedTransport import verify_control


# Unchanged conservative-chamber inventory criteria; not all mechanism gates.
MASS_TOL_KG = 1e-15
ENERGY_TOL_J = 1e-8


class EnthalpyTrialFailure(RuntimeError):
    def __init__(self, message, time_s, state):
        super().__init__(message)
        self.time_s = time_s
        self.last_valid_state = state.copy()


def load_inputs(control_root, fluid_execution):
    control = verify_control(control_root)
    fluid = json.loads(fluid_execution.read_text(encoding="utf-8-sig"))
    if fluid.get("collection_pass") is not True:
        raise ValueError("Incomplete fluid-settings witness")
    configuration = next(d for d in control["input_dependencies"] if d["path"].endswith("configuration.mat"))
    if configuration["sha256"] != fluid["configuration_sha256"]:
        raise ValueError("Different physical contracts")
    eos, contracts = {}, {}
    for material in ("SMA", "SE"):
        settings = next(r for r in fluid["cases"] if r["material"] == material)["fluid_settings"]
        table = energy_tables(settings["saved_inventory_parameters"])
        t, p = table["rho"].grid
        conductivity = np.asarray(settings["thermal_conductivity_mW_per_mK"])*.001
        eos[material] = TabulatedEOS(t, p, table["rho"].values, table["u"].values, conductivity)
        points = np.array([[v, 850000.] for v in (276.95, 303.15, 393.15)])
        exact = eos[material].properties(points[:, 0], points[:, 1])
        contracts[material] = {"geometry_and_constant_control": control["physical_contracts"][material],
            "fluid_settings": settings,
            "EOS_temperature_K": t.tolist(), "EOS_pressure_Pa": p.tolist(),
            "density_kg_m3": table["rho"].values.tolist(),
            "specific_internal_energy_J_kg": table["u"].values.tolist(),
            "conductivity_W_mK": conductivity.tolist(),
            "reference_temperature_K": eos[material].Tref, "reference_pressure_Pa": eos[material].pref,
            "internal_energy_reference_J_kg": eos[material].uref,
            "table_interpolants_match_native_rho_u_recipe": True,
            "native_differential_coefficients_replaced_by_exact_interpolant_derivatives": True,
            "coefficient_probe_temperature_K": points[:, 0].tolist(),
            "native_interpolated_cp_J_kgK": table["cp"](points).tolist(),
            "exact_dh_dT_of_EOS_J_kgK": exact["dh_dT"].tolist(),
            "cold_rho_kg_m3": float(eos[material].properties([303.15], [850000.])["rho"][0])}
    return control, eos, contracts


def run_case(bed, flow, material, dt, stop, sample_times):
    segments = [(stop/2, flow), (stop, -flow)]
    left, right = ((393.15, 303.15) if material == "SMA" else (276.95, 303.15))
    initial = bed.initial_state()
    state = initial.copy()
    initial_mass = float(initial[:bed.nodes].sum())
    rows, temperatures, pressures, flows, times = [], [], [], [], []
    sample_indices = np.rint(np.asarray(sample_times)/dt).astype(int)
    if (not np.allclose(sample_indices*dt, sample_times, rtol=0, atol=1e-12)
            or sample_times[0] != 0 or sample_times[-1] != stop or np.any(np.diff(sample_indices) <= 0)
            or abs(round(stop/(2*dt))*dt-stop/2) > 1e-12):
        raise ValueError("Events and samples must be on the actual fixed grid")
    wanted = set(sample_indices)
    max_mass, max_energy, max_pressure_drift = 0., 0., 0.
    maximum_pressure_rate = 0.
    tmin, tmax = bed.eos.Tref, bed.eos.Tref
    pmin, pmax = bed.eos.pref, bed.eos.pref
    previous_end = None
    transitions = []

    def sample(index, command):
        _, observed = bed.evaluate(state, command, left, right)
        rows.append(state.copy())
        temperatures.append(np.r_[observed["T"], observed["solid_T"]])
        pressures.append(observed["p"].copy())
        flows.append(observed["mass_faces_kg_s"].copy())
        times.append(index*dt)
        return float(np.max(abs(observed["pressure_rate_Pa_s"])))

    maximum_pressure_rate = sample(0, flow)
    start = 0
    for end, command in segments:
        if previous_end is not None:
            transitions.append({"time_s": start*dt, "all_coordinates_bitwise_unchanged": bool(np.array_equal(state, previous_end))})
        rhs = lambda t, y: bed.rhs(y, command, left, right)
        final = int(round(end/dt))
        for index in range(start, final):
            previous = state.copy()
            try:
                candidate = bs3_step(rhs, index*dt, state, dt)
                observed = bed.unpack(candidate)
            except Exception as error:
                raise EnthalpyTrialFailure(str(error), index*dt, previous) from error
            state = candidate
            max_mass = max(max_mass, abs(state[:bed.nodes].sum()-initial_mass-state[-2]))
            max_energy = max(max_energy, abs(state[bed.nodes:3*bed.nodes].sum()-state[-1]))
            max_pressure_drift = max(max_pressure_drift, float(np.max(abs(observed["p"]-bed.eos.pref))))
            tmin, tmax = min(tmin, float(observed["T"].min())), max(tmax, float(observed["T"].max()))
            pmin, pmax = min(pmin, float(observed["p"].min())), max(pmax, float(observed["p"].max()))
            if index+1 in wanted:
                maximum_pressure_rate = max(maximum_pressure_rate, sample(index+1, command))
        previous_end = state.copy()
        start = final
    return {"time_s": np.asarray(times), "conserved_diagnostic_profiles": np.asarray(rows),
            "fluid_and_solid_temperature_K": np.asarray(temperatures), "pressure_Pa": np.asarray(pressures),
            "mass_face_kg_s": np.asarray(flows)}, {
        "nodes": bed.nodes, "dt_s": dt, "stop_s": stop, "steps": start,
        "inlet_flow_magnitude_kg_s": flow, "left_temperature_K": left, "right_temperature_K": right,
        "flow_reversal_time_s": stop/2, "transitions": transitions,
        "sample_at_switch_flux_convention": "state continuous; flux from the completed segment (left limit)",
        "max_online_mass_residual_kg": float(max_mass), "max_online_energy_residual_J": float(max_energy),
        "mass_numerical_invariant_pass": bool(max_mass <= MASS_TOL_KG),
        "energy_numerical_invariant_pass": bool(max_energy <= ENERGY_TOL_J),
        "fluid_temperature_range_K_all_major_steps": [tmin, tmax],
        "pressure_range_Pa_all_major_steps": [pmin, pmax],
        "max_pressure_invariant_drift_Pa_all_major_steps": max_pressure_drift,
        "max_sampled_reconstructed_abs_pressure_rate_Pa_s": maximum_pressure_rate,
        "total_fluid_mass_change_kg": float(state[:bed.nodes].sum()-initial_mass),
        "integrated_boundary_net_mass_kg": float(state[-2]),
        "integrated_boundary_net_energy_relative_J": float(state[-1]),
        "state_projection_or_reinitialization_applied": False,
        "pressure_drift_corrected_by_hand": False,
        "mass_and_energy_ledger_basis": "primary M and E=M*(u-uref), same-stage boundary ledgers; rigid V",
        "finite_step_pressure_constraint_exact_claim": False,
        "pressure_drift_is_numerical_not_a_pump_or_pressure_loss_model": True}


def run(output, control_root, fluid_execution, study):
    output.mkdir(parents=True, exist_ok=False)
    sources = [Path(__file__), Path(__file__).with_name("Reference_HeatDriveECC_EnthalpyTransport.py"),
               Path(__file__).with_name("Reference_HeatDriveECC_ConservativeTransport.py"),
               Path(__file__).with_name("Audit_HeatDriveECC_NativeAccumulation.py"),
               Path(__file__).with_name("Audit_HeatDriveECC_TLDomainInventory.py")]
    record = {"schema": "heatdrive_ecc_active_enthalpy_transport_v1", "study": study,
        "execution_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=Path(__file__).parent, text=True).strip(),
        "source_sha256": {str(p): sha256(p) for p in sources},
        "runtime": {"python": platform.python_version(), "numpy": np.__version__, "scipy": scipy.__version__},
        "control_execution_path": str(control_root/"transport_execution.json"),
        "control_execution_sha256": sha256(control_root/"transport_execution.json"),
        "fluid_settings_execution_path": str(fluid_execution), "fluid_settings_execution_sha256": sha256(fluid_execution),
        "collection_complete": False, "cases": [], "production_state_loaded": False, "checkpoint_saved": False,
        "production_recovery_allowed": False, "full_coupled_qualification": False, "outer_solve_allowed": False,
        "Table4_reproduction_claim": False, "scientific_gates_modified": False,
        "primary_state": "N masses, N relative internal energies, N solid sensible energies, boundary mass and energy integrals",
        "boundary_contract": "open ACTIVE prescribed-inlet flow; constant-p differential invariant; downstream expansion flow solved, not forced equal",
        "sealed_dwell_or_full_hydraulic_loop_supported": False,
        "phase_transformation_or_mechanical_power_included": False,
        "state_clipping_or_pressure_projection": False,
        "solid_conduction_ends": "adiabatic", "fluid_conduction_ends": "insulated",
        "mass_tolerance_kg": MASS_TOL_KG, "energy_tolerance_J": ENERGY_TOL_J,
        "numerical_inventory_tolerance_source": "Audit_HeatDriveECC_ConservativeChamberResult.py",
        "source_equations": "exact derivatives of the SAME bilinear rho/u interpolants; variable k(T), Nu=3.66, MC h-face reconstruction"}
    write_json(output/"preflight.json", record)
    begin = time.perf_counter()
    try:
        control, eos, contracts = load_inputs(control_root, fluid_execution)
        record["physical_contracts"] = contracts
        stop = .1 if study == "smoke" else 10.
        sample_times = ([0., .01, .02, .025, .05, .06, .075, .1] if study == "smoke" else
                        [0., .01, .05, .1, .25, .5, 1., 3.5, 5., 5.1, 6., 8.5, 9., 10.])
        for material in ("SMA", "SE"):
            contract = control["physical_contracts"][material]
            for dt in (.001, .0005, .00025):
                geometry = replace(Bed(**contract["bed"]), slope_limiter="MC")
                bed = EnthalpyBed(geometry, eos[material], 3.66, contract["Dh_m"], contract["surface_area_m2"])
                record["active_case"] = {"material": material, "dt_s": dt, "stop_s": stop, "nodes": bed.nodes}
                started = time.perf_counter()
                profiles, row = run_case(bed, contract["nominal_mass_flow_kg_s"], material, dt, stop, sample_times)
                file = output/f"{material}_n21_dt{dt:g}_{study}.npz"
                np.savez_compressed(file, **profiles)
                record["cases"].append({**row, "material": material, "file": file.name,
                    "sha256": sha256(file), "bytes": file.stat().st_size, "wall_seconds": time.perf_counter()-started})
        record.update(collection_complete=True, wall_seconds=time.perf_counter()-begin,
            all_six_mass_energy_numerical_invariants_pass=all(r["mass_numerical_invariant_pass"] and r["energy_numerical_invariant_pass"] for r in record["cases"]),
            raw_npz_bytes=sum(r["bytes"] for r in record["cases"]),
            raw_retention="selected diagnostic profiles, not production checkpoints; no per-step full-state history")
        write_json(output/"enthalpy_execution.json", record)
        print(json.dumps({"output": str(output), "collection_complete": True, "cases": len(record["cases"]),
            "all_mass_energy_numerical_invariants_pass": record["all_six_mass_energy_numerical_invariants_pass"],
            "maximum_pressure_drift_Pa": max(r["max_pressure_invariant_drift_Pa_all_major_steps"] for r in record["cases"]),
            "wall_seconds": record["wall_seconds"], "raw_npz_bytes": record["raw_npz_bytes"],
            "execution_sha256": sha256(output/"enthalpy_execution.json"), "production_recovery_allowed": False}))
    except Exception as error:
        if isinstance(error, EnthalpyTrialFailure):
            file = output/"failed_case_last_valid_diagnostic_NOT_CHECKPOINT.npz"
            np.savez_compressed(file, time_s=[error.time_s], diagnostic_state=error.last_valid_state)
            record["failed_case_diagnostic"] = {"file": file.name, "bytes": file.stat().st_size,
                "sha256": sha256(file), "time_s": error.time_s, "production_recovery_allowed": False}
        record.update(error_traceback=traceback.format_exc(), wall_seconds=time.perf_counter()-begin)
        write_json(output/"FAILED_DO_NOT_RESUME.json", record)
        raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--control-root", required=True, type=Path)
    parser.add_argument("--fluid-settings-execution", required=True, type=Path)
    parser.add_argument("--study", choices=("smoke", "active_10s"), required=True)
    arguments = parser.parse_args()
    run(arguments.output.resolve(), arguments.control_root.resolve(), arguments.fluid_settings_execution.resolve(), arguments.study)
