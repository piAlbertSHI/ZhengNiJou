"""New cold chain using simultaneous conservative midpoint/EOS constraints."""
import argparse
from dataclasses import replace
from pathlib import Path
import subprocess
import time
import traceback

import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Reference_HeatDriveECC_ConservativeTransport import Bed
from Reference_HeatDriveECC_EnthalpyTransport import EnthalpyBed
from Reference_HeatDriveECC_ConstrainedEnthalpy import constrained_midpoint_step
from Run_HeatDriveECC_ConservativeTransport import write_json
from Run_HeatDriveECC_EnthalpyTransport import load_inputs, MASS_TOL_KG, ENERGY_TOL_J


def run_case(bed, material, flow, dt, stop, samples):
    initial = bed.initial_state()
    state = initial.copy()
    n = bed.nodes
    mass0 = float(initial[:n].sum())
    left, right = ((393.15, 303.15) if material == "SMA" else (276.95, 303.15))
    wanted = set(np.rint(samples/dt).astype(int))
    if (not np.allclose(np.rint(samples/dt)*dt, samples, rtol=0, atol=1e-12)
            or abs(round(stop/(2*dt))*dt-stop/2) > 1e-12):
        raise ValueError("Actual fixed grid must align with all events and samples")
    profiles, temperatures, pressures, times = [], [], [], []
    max_mass, max_energy, max_pressure, max_residual, min_T, max_T = 0., 0., 0., 0., bed.eos.Tref, bed.eos.Tref
    nonlinear_evaluations, small_residual_non_success = 0, 0
    numerical_cache, reused_jacobians = {}, 0
    transitions = []
    def save(t):
        obs = bed.unpack(state)
        profiles.append(state.copy())
        temperatures.append(np.r_[obs["T"], obs["solid_T"]])
        pressures.append(obs["p"].copy())
        times.append(t)
    save(0.)
    half, count = int(round(stop/(2*dt))), int(round(stop/dt))
    for index in range(count):
        if index == half:
            before = state.copy()
            # Only the boundary command changes; the complete prior state is
            # supplied unchanged to the next conservative nonlinear solve.
            transitions.append({"time_s": index*dt, "all_coordinates_bitwise_unchanged": bool(np.array_equal(before, state))})
        command = flow if index < half else -flow
        candidate, solve = constrained_midpoint_step(bed, state, command, left, right, dt, numerical_cache)
        state = candidate
        obs = bed.unpack(state)
        max_mass = max(max_mass, abs(float(state[:n].sum()-mass0-state[-2])))
        max_energy = max(max_energy, abs(float(state[n:3*n].sum()-state[-1])))
        max_pressure = max(max_pressure, solve["max_endpoint_pressure_deviation_Pa"])
        max_residual = max(max_residual, solve["max_nonlinear_energy_residual_J"])
        min_T, max_T = min(min_T, float(obs["T"].min())), max(max_T, float(obs["T"].max()))
        nonlinear_evaluations += solve["RHS_evaluations"]
        reused_jacobians += int(solve["numerical_Jacobian_reused"])
        small_residual_non_success += int(not solve["nonlinear_success_flag"])
        if index+1 in wanted:
            save((index+1)*dt)
    if not np.array_equal(times, samples):
        raise ValueError("Missing or misaligned constrained profiles")
    return {"time_s": np.asarray(times), "conserved_diagnostic_profiles": np.asarray(profiles),
            "fluid_and_solid_temperature_K": np.asarray(temperatures), "pressure_Pa": np.asarray(pressures)}, {
        "material": material, "nodes": n, "dt_s": dt, "stop_s": stop, "steps": count,
        "left_temperature_K": left, "right_temperature_K": right, "flow_magnitude_kg_s": flow,
        "max_online_mass_residual_kg": max_mass, "max_online_energy_residual_J": max_energy,
        "max_online_pressure_constraint_residual_Pa": max_pressure, "max_nonlinear_energy_residual_J": max_residual,
        "mass_numerical_invariant_pass": max_mass <= MASS_TOL_KG,
        "energy_numerical_invariant_pass": max_energy <= ENERGY_TOL_J,
        "pressure_numerical_1Pa_target_pass": max_pressure <= 1.,
        "fluid_temperature_range_K_all_major_steps": [min_T, max_T],
        "nonlinear_RHS_evaluations": nonlinear_evaluations,
        "steps_reusing_numerical_Jacobian": reused_jacobians,
        "numerical_cache_saved_as_checkpoint": False,
        "non_success_flags_with_independently_accepted_roundoff_residual": small_residual_non_success,
        "net_mass_integral_kg": float(state[-2]), "net_energy_integral_J": float(state[-1]),
        "transitions": transitions, "production_state_loaded": False,
        "state_projection_after_integration": False,
        "new_states_solve_conservation_and_EOS_together": True}


def run(output, control_root, fluid_execution, study):
    output.mkdir(parents=True, exist_ok=False)
    sources = [Path(__file__), Path(__file__).with_name("Reference_HeatDriveECC_ConstrainedEnthalpy.py"),
               Path(__file__).with_name("Reference_HeatDriveECC_EnthalpyTransport.py"),
               Path(__file__).with_name("Run_HeatDriveECC_EnthalpyTransport.py"),
               Path(__file__).with_name("Reference_HeatDriveECC_ConservativeTransport.py"),
               Path(__file__).with_name("Audit_HeatDriveECC_NativeAccumulation.py"),
               Path(__file__).with_name("Audit_HeatDriveECC_TLDomainInventory.py")]
    record = {"schema": "heatdrive_ecc_constrained_enthalpy_execution_v1", "study": study,
        "execution_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=Path(__file__).parent, text=True).strip(),
        "source_sha256": {str(p): sha256(p) for p in sources},
        "fluid_settings_execution_path": str(fluid_execution), "fluid_settings_execution_sha256": sha256(fluid_execution),
        "control_execution_path": str(control_root/"transport_execution.json"),
        "control_execution_sha256": sha256(control_root/"transport_execution.json"),
        "collection_complete": False, "cases": [],
        "method": "conservative simultaneous EOS + mass/energy implicit midpoint; NOT fixed ODE3 or pressure projection",
        "boundary_contract": "open ACTIVE prescribed-inlet component, p=0.85MPa, outflow includes thermal expansion",
        "mass_tolerance_kg": MASS_TOL_KG, "energy_tolerance_J": ENERGY_TOL_J,
        "pressure_numerical_target_Pa": 1., "pressure_target_is_a_paper_mechanism_gate": False,
        "same_rho_u_tables_and_heat_law_as_explicit_and_adaptive_trials": True,
        "numerical_Jacobian_recycling": "MINPACK final QR; invalidated at flow reversal; no physical or PI state cached/reset",
        "production_state_loaded": False, "checkpoint_saved": False, "production_recovery_allowed": False,
        "full_coupled_qualification": False, "outer_solve_allowed": False, "Table4_reproduction_claim": False,
        "sealed_dwell_supported": False, "phase_or_mechanical_power_included": False,
        "scientific_gates_modified": False, "temperature_or_pressure_projection": False}
    write_json(output/"preflight.json", record)
    started = time.perf_counter()
    try:
        control, eos, contracts = load_inputs(control_root, fluid_execution)
        record["physical_contracts"] = contracts
        stop = .1 if study == "smoke" else 10.
        samples = np.array([0., .01, .02, .025, .05, .06, .075, .1] if study == "smoke" else
            [0., .01, .05, .1, .25, .5, 1., 3.5, 5., 5.1, 6., 8.5, 9., 10.])
        steps = (.001, .0005, .00025) if study == "smoke" else (.001, .0005)
        for material in ("SMA", "SE"):
            c = control["physical_contracts"][material]
            bed = EnthalpyBed(replace(Bed(**c["bed"]), slope_limiter="MC"), eos[material], 3.66, c["Dh_m"], c["surface_area_m2"])
            for dt in steps:
                record["active_case"] = {"material": material, "dt_s": dt, "stop_s": stop}
                begin = time.perf_counter()
                profiles, row = run_case(bed, material, c["nominal_mass_flow_kg_s"], dt, stop, samples)
                file = output/f"{material}_n21_dt{dt:g}_{study}.npz"
                np.savez_compressed(file, **profiles)
                record["cases"].append({**row, "file": file.name, "bytes": file.stat().st_size,
                    "sha256": sha256(file), "wall_seconds": time.perf_counter()-begin})
        record.update(collection_complete=True, wall_seconds=time.perf_counter()-started,
            all_numerical_invariants_pass=all(r["mass_numerical_invariant_pass"] and r["energy_numerical_invariant_pass"]
                and r["pressure_numerical_1Pa_target_pass"] for r in record["cases"]),
            raw_npz_bytes=sum(r["bytes"] for r in record["cases"]),
            retention="selected diagnostic profiles only; no checkpoints or nonlinear iteration histories")
        write_json(output/"constrained_execution.json", record)
        print(__import__("json").dumps({"output": str(output), "collection_complete": True, "cases": len(record["cases"]),
            "all_numerical_invariants_pass": record["all_numerical_invariants_pass"],
            "max_pressure_residual_Pa": max(r["max_online_pressure_constraint_residual_Pa"] for r in record["cases"]),
            "wall_seconds": record["wall_seconds"], "raw_npz_bytes": record["raw_npz_bytes"],
            "execution_sha256": sha256(output/"constrained_execution.json"), "production_recovery_allowed": False}))
    except Exception:
        record.update(error_traceback=traceback.format_exc(), wall_seconds=time.perf_counter()-started)
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
