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
from scipy.io import loadmat

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


def gate_on_clock(trace, clock):
    """Evaluate recorded ZOH command samples, never interpolate physical state."""
    t = np.asarray(trace["time"], dtype=float).ravel()
    v = np.asarray(trace["signals"]["values"], dtype=float).ravel()
    if len(t) != len(v) or not np.isfinite(v).all() or not np.isfinite(t).all() or np.any(np.diff(t) < 0) or t[0] != 0:
        raise ValueError("Invalid actual ZOH control trace")
    # Allow only timestamp roundoff; not a half-step temporal shift.
    ix = np.searchsorted(t, clock+2e-14, side="right")-1
    if np.any(ix < 0) or abs(t[-1]-clock[-1]) > 2e-14:
        raise ValueError("Incomplete control trace clock")
    return v[ix]


def cycle_review(observations, preflights, commit, output):
    source = subprocess.check_output(["git", "show", commit+":gx101r1_R69_remote/Extract_HeatDriveECC_PhysicalLogs.m"])
    if b"offset = 2 * N;" not in source or b"names = {'xM_SMA_21','xM_SE_21','sigma_SMA_21_Pa'" not in source:
        raise ValueError("Reassess changed constitutive output layout")
    summaries, curves, gates = {}, {}, {}
    for arm in ("dual", "shared"):
        raw, p = observations[arm], preflights[arm]
        rows = series_index(raw)
        c = np.asarray(raw["constitutive_output"]["signals"]["values"], dtype=float)
        t = np.asarray(raw["constitutive_output"]["time"], dtype=float).ravel()
        if c.shape != (10001, 252) or not np.allclose(t, np.arange(10001)*.001, rtol=0, atol=2e-14):
            raise ValueError("Not a complete native C1 constitutive observation")
        phase = {"SMA": c[:,42:63], "SE": c[:,63:84]}
        fluid = {}
        energy = np.zeros_like(t)
        for group in ("Hold", "Cooldown"):
            paths = sorted(g["block_path"] for g in p["pipe_geometry"] if "/"+group+"Pipe_" in g["block_path"])
            if paths:
                fluid[group] = np.column_stack([rows[path,"T_I"][1] for path in paths])
        for g in p["pipe_geometry"]:
            u = rows[g["block_path"], "u_I"][1]
            energy += native_mass(g,p["fluid_tables"])*(u-u[0])
        model = p["pipe_geometry"][0]["block_path"].split("/")[0]
        solid = {part: np.column_stack([rows[model+"/%s/Subsystem2/NodeMass_%02d" % (part,i),"T"][1] for i in range(1,22)]) for part in ("SMA","SE")}
        gates[arm] = {name: gate_on_clock(trace,t) for name,trace in raw["gate_commands"].items()}
        stage = []
        for end in (3.5,5.,5.001,5.2,8.5,10.):
            i = round(end/.001)
            stage.append({"time_s":end,"fluid_profiles_K":{k:v[i].tolist() for k,v in fluid.items()},
                          "solid_temperature_min_mean_max_K":{k:[float(v[i].min()),float(v[i].mean()),float(v[i].max())] for k,v in solid.items()},
                          "phase_min_mean_max":{k:[float(v[i].min()),float(v[i].mean()),float(v[i].max())] for k,v in phase.items()},
                          "selected_fluid_native_energy_change_J":float(energy[i])})
        summaries[arm] = {"stage_observations":stage,"phase_full_record_min_max":{k:[float(v.min()),float(v.max())] for k,v in phase.items()}}
        curves[arm] = {"t":t,"fluid":fluid,"energy":energy,"solid":solid,"phase":phase}
    equal = {name: bool(np.array_equal(gates["dual"][name],gates["shared"][name])) for name in ("original_hold","original_cooldown")}
    max_ok = bool(np.array_equal(gates["shared"]["shared_max"], np.maximum(gates["shared"]["original_hold"],gates["shared"]["original_cooldown"])))
    if not max_ok:
        raise ValueError("Actual shared thermal command differs from max of original commands")
    first_active = {arm:{name:float(curves[arm]["t"][np.flatnonzero(v>1e-6)[0]]) for name,v in gs.items()} for arm,gs in gates.items()}
    figure_cycle(curves,output)
    return {"layout_source_sha256":hashlib.sha256(source).hexdigest().upper(),"arms":summaries,
            "original_commands_equal_at_actual_1ms_native_samples":equal,
            "actual_shared_gate_max_rule_pass":max_ok,"gate_first_active_at_1ms_sample_s":first_active,
            "control_trace_event_times_need_not_be_identical_between_variable_step_runs":True,
            "no_thermal_state_reset_during_switch_in_runner_source":True,
            "discrete_selected_pipe_switch_energy_ledger_observed":True,
            "all_hidden_states_or_full_system_switch_gate_proven":False,
            "inactive_dual_hot_pipe_inventory_is_not_an_active_fluid_temperature_jump":True,
            "C1_is_not_a_periodic_or_performance_comparison":True}


def figure_cycle(curves, output):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(2,2,figsize=(10,7),layout="constrained")
    colors = {"dual":"#666666","shared":"#007A78"}
    axes[0,0].plot(curves["dual"]["t"],curves["dual"]["fluid"]["Hold"].mean(axis=1),color="#C43C39",label="Dual: hot-route inventory")
    axes[0,0].plot(curves["dual"]["t"],curves["dual"]["fluid"]["Cooldown"].mean(axis=1),color="#666666",label="Dual: cold-route inventory")
    axes[0,0].plot(curves["shared"]["t"],curves["shared"]["fluid"]["Hold"].mean(axis=1),color=colors["shared"],label="Shared inventory")
    for arm,label in (("dual","Dual inventory"),("shared","Shared inventory")):
        r=curves[arm]
        axes[0,1].plot(r["t"],r["energy"]/1000,color=colors[arm],label=label)
        axes[1,0].plot(r["t"],r["solid"]["SMA"].mean(axis=1),color=colors[arm],label=label)
        axes[1,1].plot(r["t"],r["phase"]["SE"].mean(axis=1),color=colors[arm],label=label)
    titles=("(a) Persistent fluid thermal histories","(b) Selected fluid stored-energy change","(c) Mean SMA solid temperature","(d) Mean SE martensite fraction")
    labels=("Mean fluid temperature (K)","Native fluid energy change (kJ)","Mean solid temperature (K)","Martensite fraction")
    for ax,title,label in zip(axes.ravel(),titles,labels):
        ax.set(title=title,xlabel="Time (s)",ylabel=label,xlim=(0,10))
        ax.axvline(5,color="#999999",ls=":",lw=.8)
        ax.spines[["top","right"]].set_visible(False)
        ax.legend(frameon=False,fontsize=8)
    axes[1,1].set_ylim(-.02,1.02)
    fig.suptitle("One native cold cycle: not periodic and not Table 4 reproduction",fontsize=11)
    fig.savefig(output/"shared_SMA_cold_cycle.png",dpi=200)
    plt.close(fig)


def analyze(root, output):
    execution_path = root/"cold_initial_execution.json"
    execution = json.loads(execution_path.read_text(encoding="utf-8"))
    if execution.get("capture_profile","selected_sma_v1") != "selected_sma_v1":
        raise ValueError("Use the coupled CV packet reader, not the selected-SMA observation reader")
    if not execution["collection_complete"] or execution["checkpoint_loaded_or_saved"] or execution["hydraulic_storage_variant"] != "native_foundation_chambers_and_buffers":
        raise ValueError("Not a complete, fresh native probe")
    duration = execution["stop_time_s"]
    if duration not in (.01, .2, 10):
        raise ValueError("Outside the explicit short diagnostic scope")
    observer = execution.get("observer_function_name", "HeatDriveECC_ShortColdTimeObserver")
    if observer not in {"HeatDriveECC_ShortColdTimeObserver", "HeatDriveECC_ProcessLocalTimeObserver"}:
        raise ValueError("Unreviewed clock observer")
    sources = {"runner": "Run_HeatDriveECC_SharedSMAColdInitial.m", "applicator": "Apply_HeatDriveECC_SharedSMAFluidDiagnostic.m",
               "observer": observer+".m", "observer_delegate": "HeatDriveECC_ProcessLocalTimeObserver.m"}
    for role, name in sources.items():
        code = subprocess.check_output(["git", "show", execution["execution_commit"]+":gx101r1_R69_remote/verification/"+name])
        if hashlib.sha256(code).hexdigest().upper() != execution["source_sha256"][role]:
            raise ValueError("Historical runtime producer hash mismatch")
    results = []
    observations = {}
    preflights = {}
    dependencies = [{"path": str(execution_path), "sha256": sha256(execution_path)}]
    for arm, count in (("dual", 42), ("shared", 21)):
        completed = next(c for c in execution["completed_arms"] if c["arm"] == arm)
        raw_path = root/arm/Path(completed["raw_file"]).name
        if sha256(raw_path) != completed["raw_sha256"]:
            raise ValueError("Native raw observations changed")
        preflight_path = root/arm/"cold_preflight.json"
        p = json.loads(preflight_path.read_text(encoding="utf-8"))
        preflights[arm] = p
        if p["local_solver_step_s"] != .001 or p["native_pipe_source_sha256"] != "CC478BAB8A9B5DD6156ACE2239BF837FE0849843EF5BDBFE6F55C315343FAC3E":
            raise ValueError("Native ledger formula / local integration needs re-review")
        raw = loadmat(raw_path, simplify_cells=True)["traces"] if raw_path.suffix == ".mat" else json.loads(raw_path.read_text(encoding="utf-8"))
        if raw.get("partial_diagnostic_only", False):
            raise ValueError("Partial diagnostic is not a completed cold cycle")
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
        observer_dt = p.get("observer_sample_time_s", .001)
        if len(samples) != round(duration/observer_dt) or not np.allclose(samples, np.arange(1,len(samples)+1)*observer_dt, atol=2e-14, rtol=0.):
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
    if duration == 10:
        result["cold_cycle_observations"] = cycle_review(observations,preflights,execution["execution_commit"],output)
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
