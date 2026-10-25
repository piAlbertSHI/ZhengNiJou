"""Read native matched cold probes, using native quasisteady pipe ledgers.

rho_nominal*V*u is the native stored energy, not rho(T,p)*V*u. A short
successful initialization is not a switch, periodic, complete-mechanism or
Table4 qualification. No state is reconstructed for resuming a simulation.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Run_HeatDriveECC_ConservativeTransport import write_json


def series_index(raw):
    rows = {}
    expected_units = {"T_I": "K", "T": "K", "p_I": "Pa", "u_I": "J/kg", "rho_I": "kg/m^3",
                      "Phi_A": "W", "Phi_B": "W", "Q_H": "W", "mdot_A": "kg/s", "mdot_B": "kg/s"}
    for row in raw["series"]:
        key = (row["block_path"], row["state_name"])
        if key in rows or row["unit"] != expected_units[row["state_name"]]:
            raise ValueError("Duplicate coordinate or incompatible SI ledger unit")
        t, v = (np.asarray(row[k], dtype=float).reshape(-1) for k in ("time_s", "values"))
        if len(t) != len(v) or len(t) < 2 or not np.isfinite(t).all() or not np.isfinite(v).all() or np.any(np.diff(t) <= 0):
            raise ValueError("Incomplete or nonmonotone actual native samples")
        rows[key] = (t, v)
    return rows


def native_mass(geometry, tables):
    # Same 30-point native 1-D property expansion, independently recomputed.
    if tables["native_settings_source_sha256"] != "D0B8A66CBD6AFE7BBF14402A78BFE975BCBE009A5817D346CCBC5F64A85E1693" or tables["pressure_axis_count"] != 30:
        raise ValueError("Unreviewed native density expansion source")
    p = np.logspace(np.log10(tables["p_min_1D"]*1e6), np.log10(tables["p_max_1D"]*1e6), 30)
    factors = np.exp((p-tables["p_ref_4"]*1e6)/(tables["beta_const_4"]*1e9))
    rho = np.interp(geometry["nominal_temperature_K"], np.asarray(tables["T_TLU"]).ravel(), np.asarray(tables["rho_TLU_4"]).ravel())
    rho *= np.interp(geometry["nominal_pressure_Pa"], p, factors)
    if not np.isclose(rho, geometry["native_nominal_density_kg_m3"], rtol=2e-14, atol=0.):
        raise ValueError("Nominal density differs from actual-table reconstruction")
    return float(rho*geometry["volume_m3"])


def pipe_ledger(rows, geometry, tables, duration):
    path = geometry["block_path"]
    t, u = rows[path, "u_I"]
    clock = np.arange(round(duration/.001)+1)*.001
    if t.shape != clock.shape or not np.allclose(t, clock, rtol=0., atol=2e-14):
        raise ValueError("Ledger requires actual complete 1 ms local-BE samples; no interpolation")
    def v(name):
        nt, values = rows[path, name]
        if not np.array_equal(t, nt):
            raise ValueError("Native port/state clocks differ")
        return values
    mass = native_mass(geometry, tables)
    power = v("Phi_A")+v("Phi_B")+v("Q_H")
    cumulative = np.r_[0., np.cumsum(np.diff(t)*power[1:])]
    residual = mass*(u-u[0])-cumulative
    return {"block_path": path, "constant_native_mass_kg": mass,
            "BE_energy_residual_max_J": float(abs(residual).max()),
            "mass_port_sum_max_kg_s": float(abs(v("mdot_A")+v("mdot_B")).max()),
            "initial_temperature_K": float(v("T_I")[0]), "final_temperature_K": float(v("T_I")[-1]),
            "pressure_min_max_Pa": [float(v("p_I").min()), float(v("p_I").max())],
            "wall_heat_BE_J": float(np.dot(np.diff(t), v("Q_H")[1:])),
            "native_energy_change_J": float(mass*(u[-1]-u[0])),
            "ledger_rule": "rho_nominal*V*delta(u_I) minus right-endpoint local backward-Euler port sum"}


def analyze(root, output):
    execution_path = root/"cold_initial_execution.json"
    execution = json.loads(execution_path.read_text(encoding="utf-8"))
    if not execution["collection_complete"] or execution["checkpoint_loaded_or_saved"] or execution["hydraulic_storage_variant"] != "native_foundation_chambers_and_buffers":
        raise ValueError("Not a complete, fresh native probe")
    duration = execution["stop_time_s"]
    if duration not in (.01, .2):
        raise ValueError("Outside the explicit short diagnostic scope")
    sources = {"runner": "Run_HeatDriveECC_SharedSMAColdInitial.m", "applicator": "Apply_HeatDriveECC_SharedSMAFluidDiagnostic.m",
               "observer": "HeatDriveECC_ShortColdTimeObserver.m", "observer_delegate": "HeatDriveECC_ProcessLocalTimeObserver.m"}
    for role, name in sources.items():
        code = subprocess.check_output(["git", "show", execution["execution_commit"]+":gx101r1_R69_remote/verification/"+name])
        if hashlib.sha256(code).hexdigest().upper() != execution["source_sha256"][role]:
            raise ValueError("Historical runtime producer hash mismatch")
    results = []
    observations = {}
    dependencies = [{"path": str(execution_path), "sha256": sha256(execution_path)}]
    for arm, count in (("dual", 42), ("shared", 21)):
        completed = next(c for c in execution["completed_arms"] if c["arm"] == arm)
        raw_path = root/arm/"selected_observations.json"
        if sha256(raw_path) != completed["raw_sha256"]:
            raise ValueError("Native raw observations changed")
        preflight_path = root/arm/"cold_preflight.json"
        p = json.loads(preflight_path.read_text(encoding="utf-8"))
        if p["local_solver_step_s"] != .001 or p["native_pipe_source_sha256"] != "CC478BAB8A9B5DD6156ACE2239BF837FE0849843EF5BDBFE6F55C315343FAC3E":
            raise ValueError("Native ledger formula / local integration needs re-review")
        raw = json.loads(raw_path.read_text(encoding="utf-8"))
        rows = series_index(raw)
        observations[arm] = raw
        if len(p["pipe_geometry"]) != count or len(rows) != count*9+42+18:
            raise ValueError("Incomplete native pipe/solid/chamber observation coverage")
        pipes = [pipe_ledger(rows, g, p["fluid_tables"], duration) for g in p["pipe_geometry"]]
        initial_error = max(abs(r["initial_temperature_K"]-303.15) for r in pipes)
        if initial_error >= 1e-6 or initial_error != completed["maximum_initial_pipe_temperature_error_K"]:
            raise ValueError("Actual initial bed temperature does not match the declared protocol")
        observer_path = root/arm/"solver_time.jsonl"
        events = [json.loads(line) for line in observer_path.read_text(encoding="utf-8").splitlines()]
        if len({r["run_id"] for r in events}) != 1 or len({r["process_pid"] for r in events}) != 1 or events[-1]["simulation_time_s"] != duration:
            raise ValueError("No same-process solver-clock completion witness")
        samples = [e["simulation_time_s"] for e in events if e["phase"] == "solver_time_sample"]
        if len(samples) != round(duration/.001) or not np.allclose(samples, np.arange(1,len(samples)+1)*.001, atol=2e-14, rtol=0.):
            raise ValueError("Incomplete actual solver-time samples")
        dependencies.extend({"path": str(f), "sha256": sha256(f)} for f in (raw_path, preflight_path, observer_path))
        results.append({"arm": arm, "actual_duration_s": duration, "simulation_wall_seconds": completed["simulation_wall_seconds"],
                        "actual_native_pipe_count": count, "maximum_initial_temperature_error_K": initial_error,
                        "native_constant_mass_kg": sum(r["constant_native_mass_kg"] for r in pipes),
                        "maximum_selected_pipe_BE_energy_residual_J": max(r["BE_energy_residual_max_J"] for r in pipes),
                        "maximum_selected_pipe_mass_port_sum_kg_s": max(r["mass_port_sum_max_kg_s"] for r in pipes),
                        "selected_pipe_wall_heat_BE_J": sum(r["wall_heat_BE_J"] for r in pipes),
                        "selected_pipe_native_energy_change_J": sum(r["native_energy_change_J"] for r in pipes),
                        "sampled_pipe_pressure_min_max_Pa": [min(r["pressure_min_max_Pa"][0] for r in pipes), max(r["pressure_min_max_Pa"][1] for r in pipes)],
                        "pipe_ledgers": pipes})
    a, b = (observations[arm]["constitutive_output"] for arm in ("dual", "shared"))
    initial_constitutive_equal = np.array_equal(np.asarray(a["signals"]["values"])[0], np.asarray(b["signals"]["values"])[0])
    result = {"schema": "heatdrive_ecc_shared_SMA_native_cold_review_v1", "producer_commit": execution["execution_commit"],
              "reader_sha256": sha256(Path(__file__)), "input_dependencies": dependencies, "arms": results,
              "initial_constitutive_output_array_equal": initial_constitutive_equal,
              "matched_measured_bed_temperature_pass": True, "full_system_initial_state_equality_proven": False,
              "actual_native_initialization_and_short_integration_completed": True,
              "ledger_numerical_residuals_are_observations_not_new_production_thresholds": True,
              "native_quasisteady_mass_is_not_instantaneous_rho_times_volume": True,
              "all_pump_A_B_pressure_gates_or_full_device_first_law_evaluated": False,
              "minimal_compiled_state_count_proven": False, "switch_or_periodic_qualified": False,
              "twenty_cycle_seed_or_production_recovery_allowed": False, "C200_causal_attribution_or_Table4_reproduction": False}
    output.mkdir(parents=True, exist_ok=False)
    write_json(output/"shared_SMA_cold_review.json", result)
    print(json.dumps({"output": str(output), "sha256": sha256(output/"shared_SMA_cold_review.json"),
                      "arms": [{k:v for k,v in r.items() if k != "pipe_ledgers"} for r in results],
                      "production_recovery_allowed": False}))
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    analyze(args.root.resolve(), args.output.resolve())
