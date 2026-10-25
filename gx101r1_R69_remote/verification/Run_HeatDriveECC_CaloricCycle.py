"""Cold coupled thermal network with compact observations, no OP or continuation.

Imports sealed parameters, NEVER a saved trajectory. Mechanism observations are
not production gates; prescribed flow cannot qualify pressure or pump work.
"""
import argparse
import json
from pathlib import Path
import platform
import subprocess
import time
import traceback

import h5py
import numpy as np
import scipy

from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Reference_HeatDriveECC_CaloricCoupling import CaloricFluid, CaloricCycle
from Reference_HeatDriveECC_CompensatedBS3 import CompensatedBS3
from Reference_HeatDriveECC_TwoWayPhase import TwoWaySharedSurfaceCycle
from Run_HeatDriveECC_ConservativeTransport import write_json
from Run_HeatDriveECC_EnthalpyTransport import load_inputs


def load_network(control_root, fluid_execution, metadata, aux_nodes=7, phase_operator="scheduled_reduced"):
    control, eos, _ = load_inputs(control_root, fluid_execution)
    configuration = Path(next(d["path"] for d in control["input_dependencies"] if d["path"].endswith("configuration.mat")))
    witness = json.loads(fluid_execution.read_text(encoding="utf-8-sig"))
    fluids = {}
    for material in ("SMA", "SE"):
        settings = next(r for r in witness["cases"] if r["material"] == material)["fluid_settings"]
        tables = energy_tables(settings["saved_inventory_parameters"])
        e = eos[material]
        cp = tables["cp"](np.c_[e.temperature, np.full(len(e.temperature), e.pref)])
        rho = float(e.properties([e.Tref], [e.pref])["rho"][0])
        fluids[material] = CaloricFluid(e.temperature, cp, e.k, rho, e.Tref)
    c = {"nodes": 21, "geometry": {}, "materials": {}, "kinetics": {}, "fluid_components": {},
         "solid_mass_kg": {}, "mass_flow_kg_s": {}}
    with h5py.File(configuration, "r") as file:
        def scalar(name):
            v = float(np.asarray(file["options/"+name]).item())
            if not np.isfinite(v):
                raise ValueError("Nonfinite required input "+name)
            return v
        for key in ("L_a_m", "L_r_m", "S_a_m2", "S_r_m2"):
            c["geometry"][key] = scalar("geometry/"+key)
        for material, suffix in (("SMA", "a"), ("SE", "r")):
            keys = ("E_m_Pa", "epsilon_T", "T_As_K", "T_Ms_K", "C_A_Pa_per_K", "C_M_Pa_per_K",
                    "cp_J_per_kgK", "Delta_h_J_per_kg", "k_W_per_mK")
            c["materials"][material] = {k: scalar("material/"+material+"/"+k) for k in keys}
            bed = control["physical_contracts"][material]
            c["solid_mass_kg"][material] = bed["bed"]["solid_mass_kg"]
            c["mass_flow_kg_s"][material] = bed["nominal_mass_flow_kg_s"]
            c["fluid_components"]["bed_"+suffix] = {
                "fluid": material, "nodes": 21, "area_m2": bed["bed"]["fluid_area_m2"],
                "length_m": bed["bed"]["length_m"], "solid_area_m2": bed["bed"]["solid_area_m2"],
                "surface_m2": bed["surface_area_m2"], "Dh_m": bed["Dh_m"]}
        for key in ("drive_width_a_Pa", "drive_width_r_Pa", "rate_a_to_A_1_per_s", "rate_a_to_M_1_per_s",
                    "rate_r_load_1_per_s", "rate_r_stage3_unload_1_per_s"):
            c["kinetics"][key] = scalar("constitutive/"+key)
        for key in ("phase_front_smoothing_1_per_s", "se_load_hardening_Pa", "se_loading_assist_Pa",
                    "se_unload_assist_Pa", "se_loading_work_J_per_kg", "se_unloading_work_J_per_kg"):
            if scalar("constitutive/"+key) != 0:
                raise ValueError("Restricted closure cannot silently omit "+key)
        if (scalar("constitutive/rate_r_stage4_unload_1_per_s") != c["kinetics"]["rate_r_stage3_unload_1_per_s"]
                or scalar("constitutive/max_rate_1_per_s") < max(c["kinetics"][k] for k in c["kinetics"] if k.startswith("rate_"))):
            raise ValueError("Restricted phase-rate port is not equivalent on the physical interval")
        c["stage_durations_s"] = np.asarray(file["options/schedule/stage_durations_s"]).ravel().tolist()
        c["bus_capacity_J_K"] = [scalar("system/"+key) for key in
            ("shex_sink_C_J_per_K", "hot_sink_C_J_per_K", "cold_sink_C_J_per_K", "cold_load_C_J_per_K")]
        for key, source in {"source_K": "system/Tshex_source_K", "ambient_K": "system/T0_K",
            "buffer_initial_mass_kg": "system/endpoint_reservoir_mass_kg", "cold_load_W": "system/cold_load_heat_W",
            "source_UA_W_K": "branch/shex_source_to_sink_UA_W_per_K", "ambient_UA_W_K": "branch/hhex_to_ambient_UA_W_per_K",
            "cold_load_UA_W_K": "branch/cold_load_to_chex_UA_W_per_K", "chex_leak_UA_W_K": "branch/chex_environment_leak_UA_W_per_K",
            "se_natural_h_W_m2K": "branch/se_natural_convection_h_W_per_m2K"}.items():
            c[key] = scalar(source)
        inventory = json.loads(metadata.read_text(encoding="utf-8-sig"))
        for name, suffix, material, b, ua in (
            ("shex", "/SHEX/HotPipe", "SMA", 0, "endpoint_UA_sma_shex_W_per_K"),
            ("hhex_a", "/热端换热器/SMAHotPipe", "SMA", 1, "endpoint_UA_sma_the_W_per_K"),
            ("hhex_r", "/热端换热器/HotPipe", "SE", 1, "endpoint_UA_se_the_W_per_K"),
            ("chex", "/冷端换热器/ColdSinkPipe", "SE", 2, "endpoint_UA_se_chex_W_per_K")):
            matches = [r for r in inventory["storage_blocks"] if r["block_path"].endswith(suffix)]
            if len(matches) != 1:
                raise ValueError("Accessory inventory identity not unique: "+suffix)
            row = matches[0]
            c["fluid_components"][name] = {"fluid": material, "nodes": aux_nodes,
                "area_m2": row["mask_parameters"]["area"]["value"],
                "length_m": row["mask_parameters"]["length"]["value"],
                "bus_index": b, "UA_W_K": scalar("branch/"+ua), "saved_block_path": row["block_path"]}
    if c["stage_durations_s"] != [3.5, 1.5, 3.5, 1.5] or c["ambient_K"] != 303.15:
        raise ValueError("This diagnostic requires the declared 10s, 303.15K cold start")
    c["input_dependencies"] = [*control["input_dependencies"], {"path": str(metadata), "sha256": sha256(metadata)}]
    c["fluid_caloric_contracts"] = {m: f.contract() for m, f in fluids.items()}
    c["limitations"] = [
        "prescribed flow, no pressure-loss/pump-work qualification",
        "existing reduced phase law; Af/Mf and probability parameters remain unverified",
        "constant density caloric approximation, not compressible rho/u or SLX equivalence",
        "single persistent bed fluid per material, not two independently stored SMA routes",
        "accessory fluid inventories mapped, connecting-pipe wall allocation remains unresolved",
        "finite mixed chambers with variable liquid amount, no piston pressure or volume qualification",
        "SMA return graph is an explicit engineering reference, not literal paper topology verification",
        "chemical inventory -m*L*xM closes the reduced heat law, not independent calorimetry"]
    if phase_operator == "stage_free_shared_surface":
        c["phase_operator"] = phase_operator
        c["limitations"].append("two-way shared-surface structural ablation, NOT identified MAS/polycrystal material law")
        return TwoWaySharedSurfaceCycle(c, fluids), c
    if phase_operator != "scheduled_reduced":
        raise ValueError("Unknown phase operator")
    return CaloricCycle(c, fluids), c


def simulate(model, cycles, max_step, rtol=1e-8, stage_sink=None):
    largest_rate = max(v for k, v in model.c["kinetics"].items() if k.startswith("rate_"))
    if model.c.get("phase_operator") == "stage_free_shared_surface":
        largest_rate = max(model.c["kinetics"]["rate_a_to_A_1_per_s"]+model.c["kinetics"]["rate_a_to_M_1_per_s"],
                           model.c["kinetics"]["rate_r_load_1_per_s"]+model.c["kinetics"]["rate_r_stage3_unload_1_per_s"])
    if not np.isfinite(max_step) or max_step <= 0 or max_step*largest_rate > 1:
        raise ValueError("BS3 directional phase interval requires dt*max_rate <= 1")
    y0 = model.initial_state()
    y = y0.copy()
    summation_remainder = np.zeros_like(y)
    samples, clocks, stages, transitions, cycle_rows = [y.copy()], [0.], [1], [], []
    start, evaluations, accepted = 0., 0, 0
    maxima = {"net_energy_residual_J": 0., "SE_mass_residual_kg": 0., "mechanical_exchange_residual_J": 0.,
              "force_residual_N": 0., "displacement_residual_m": 0., "instantaneous_mechanical_residual_W": 0.}
    phase_range = [0., 1.]
    previous_endpoint = None
    duration = sum(model.c["stage_durations_s"])
    # atol has physical units per coordinate: J, fraction, kg. It is not a
    # mixed-unit post hoc error metric and does not change a scientific gate.
    atol = np.full(model.size, 1e-10)
    for name in ("phase_a", "phase_r"):
        atol[model.slices[name]] = 1e-11
    atol[model.slices["buffer_mass_change"]] = 1e-13
    if "boundary_mass" in model.slices:
        atol[model.slices["boundary_mass"]] = 1e-13
    wall = time.perf_counter()
    for cycle in range(1, cycles+1):
        row = {"cycle": cycle, "stage_ends": []}
        for stage, span in enumerate(model.c["stage_durations_s"], 1):
            end = start+span
            if start:
                old = y.copy()
                for test_stage in (stage, (stage-2) % 4+1):
                    model.evaluate(y, test_stage)
                transitions.append({"time_s": start, "to_stage": stage,
                                    "state_bitwise_unchanged": bool(np.array_equal(old, y))})
            solver = CompensatedBS3(lambda t, v: model.evaluate(v, stage)[0], start, y, end,
                                   max_step=max_step, rtol=rtol, atol=atol, compensation=summation_remainder,
                                   controlled_size=getattr(model, "controlled_size", None))
            next_sample = start+.05
            while solver.status == "running":
                message = solver.step()
                if solver.status == "failed":
                    raise RuntimeError("Coupled integration failed: "+str(message))
                y = solver.y.copy()
                accepted += 1
                _, p, m = model.evaluate(y, stage)
                for key, value in model.balance(y, y0).items():
                    maxima[key] = max(maxima[key], abs(float(value)))
                for key in ("force_residual_N", "displacement_residual_m"):
                    maxima[key] = max(maxima[key], abs(float(m[key])))
                maxima["instantaneous_mechanical_residual_W"] = max(maxima["instantaneous_mechanical_residual_W"],
                    abs(float(m["mechanical_a_W"].sum()+m["mechanical_r_W"].sum())))
                phase_range[0] = min(phase_range[0], float(min(p["xa"].min(), p["xr"].min())))
                phase_range[1] = max(phase_range[1], float(max(p["xa"].max(), p["xr"].max())))
                if maxima["net_energy_residual_J"] > 1e-8 or maxima["SE_mass_residual_kg"] > 1e-15:
                    raise RuntimeError("Independent coordinate-sum numerical inventory budget failed")
                if cycle >= max(1, cycles-1):
                    while next_sample < end-1e-12 and next_sample <= solver.t+1e-12:
                        observed = solver.dense_output()(next_sample)
                        model.unpack(observed)
                        clocks.append(next_sample)
                        samples.append(observed.copy())
                        stages.append(stage)
                        next_sample += .05
            evaluations += solver.nfev+solver.initial_control_nfev
            if solver.t != end:
                raise RuntimeError("Stage endpoint was not reached")
            summation_remainder = solver.compensation.copy()
            clocks.append(end)
            samples.append(y.copy())
            stages.append(stage)
            p = model.unpack(y)
            row["stage_ends"].append({"stage": stage, "time_s": end,
                "SMA_T_range_K": [float(p["Ta"].min()), float(p["Ta"].max())],
                "SE_T_range_K": [float(p["Tr"].min()), float(p["Tr"].max())],
                "SMA_xM_range": [float(p["xa"].min()), float(p["xa"].max())],
                "SE_xM_range": [float(p["xr"].min()), float(p["xr"].max())],
                "buffer_temperature_K": p["buffer_T"].tolist(), "bus_temperature_K": p["bus_T"].tolist()})
            if stage_sink is not None:
                stage_sink({"completed_cycle_if_stage4": cycle if stage == 4 else cycle-1,
                            "cycle": cycle, **row["stage_ends"][-1],
                            "wall_seconds": time.perf_counter()-wall,
                            "maximum_numerical_residuals": maxima.copy()})
            start = end
        if previous_endpoint is not None:
            old = model.unpack(previous_endpoint)
            row["endpoint_temperature_drift_K"] = max(float(np.max(abs(p[k]-old[k]))) for k in ("Ta", "Tr", "bus_T", "buffer_T"))
            row["endpoint_phase_drift"] = max(float(np.max(abs(p[k]-old[k]))) for k in ("xa", "xr"))
        previous_endpoint = y.copy()
        row["wall_seconds_since_start"] = time.perf_counter()-wall
        cycle_rows.append(row)
    return {"time_s": np.asarray(clocks), "completed_stage": np.asarray(stages),
            "diagnostic_coordinates_NOT_OP": np.asarray(samples)}, {
        "cycles": cycles, "completed_time_s": start, "accepted_steps": accepted, "RHS_evaluations": evaluations,
        "max_accepted_step_s": max_step, "rtol": rtol, "atol_by_coordinate": atol.tolist(),
        "maximum_online_numerical_residuals": maxima, "phase_range_all_accepted_steps": phase_range,
        "stage_transitions": transitions, "cycle_observations": cycle_rows,
        "independent_inventory_coordinate_sum_pass": True,
        "periodic_qualification": "not evaluated: complete mechanism/pump and material contracts unresolved",
        "before_blow_observation": "stage1/3 endpoints are left limits before prescribed SE flow; no new production gate substituted"}


def run(output, control, witness, metadata, cycles, max_step, rtol=1e-8, phase_operator="scheduled_reduced"):
    output.mkdir(parents=True, exist_ok=False)
    source_names = ["Reference_HeatDriveECC_CaloricCoupling.py", "Run_HeatDriveECC_CaloricCycle.py",
        "Reference_HeatDriveECC_CompensatedBS3.py",
        "Reference_HeatDriveECC_TwoWayPhase.py",
        "Reference_HeatDriveECC_ConservativeTransport.py", "Run_HeatDriveECC_ConservativeTransport.py",
        "Run_HeatDriveECC_EnthalpyTransport.py", "Reference_HeatDriveECC_EnthalpyTransport.py",
        "Run_HeatDriveECC_LimitedTransport.py", "Audit_HeatDriveECC_NativeAccumulation.py",
        "Audit_HeatDriveECC_TLDomainInventory.py", "Audit_HeatDriveECC_SegmentedEvidence.py"]
    record = {"schema": "heatdrive_ecc_caloric_cycle_diagnostic_v1", "collection_complete": False,
        "execution_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "source_sha256": {name: sha256(Path(__file__).with_name(name)) for name in source_names},
        "runtime": {"python": platform.python_version(), "scipy": scipy.__version__, "numpy": np.__version__},
        "cold_start_all_temperature_K": 303.15, "initial_phase": {"SMA_xM": 1., "SE_xM": 0.},
        "integration": "monolithic adaptive compensated BS3 with exact stage stops, not fixed paper ODE3",
        "summation_compensation": "uniform accepted-increment Kahan addition for every coordinate; no inventory-residual feedback",
        "requested_cycles": cycles, "max_step_s": max_step, "requested_rtol": rtol,
        "phase_operator": phase_operator,
        "production_state_loaded": False, "checkpoint_saved": False,
        "production_recovery_allowed": False, "outer_solve_allowed": False, "Table4_reproduction_claim": False,
        "all_production_mechanism_gates_evaluated": False, "scientific_gates_modified": False,
        "raw_policy": "stage endpoints plus 50ms last-two-cycle observations, no full step history or OP"}
    write_json(output/"preflight.json", record)
    begin = time.perf_counter()
    try:
        model, contract = load_network(control, witness, metadata, phase_operator=phase_operator)
        record["network_contract"] = contract
        record["coordinate_slices"] = {k: [v.start, v.stop] for k, v in model.slices.items()}
        # Written by completed simulation stages, not an external monitor.
        # No checkpoint/state coordinates and no console waiting messages.
        with (output/"completed_stage_observations.jsonl").open("x", encoding="utf-8") as progress:
            def stage_sink(row):
                progress.write(json.dumps(row, allow_nan=False)+"\n")
                progress.flush()
            profiles, result = simulate(model, cycles, max_step, rtol, stage_sink)
        raw = output/"selected_coupled_profiles.npz"
        np.savez_compressed(raw, **profiles)
        record.update(result, collection_complete=True, wall_seconds=time.perf_counter()-begin,
                      raw={"file": raw.name, "sha256": sha256(raw), "bytes": raw.stat().st_size})
        write_json(output/"caloric_cycle_execution.json", record)
        print(json.dumps({"output": str(output), "collection_complete": True, "cycles": cycles,
            "wall_seconds": record["wall_seconds"], "raw_bytes": raw.stat().st_size,
            "numerical_residuals": result["maximum_online_numerical_residuals"],
            "execution_sha256": sha256(output/"caloric_cycle_execution.json"), "production_recovery_allowed": False}))
    except Exception:
        record.update(error_traceback=traceback.format_exc(), wall_seconds=time.perf_counter()-begin)
        write_json(output/"FAILED_DO_NOT_RESUME.json", record)
        raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--control-root", required=True, type=Path)
    parser.add_argument("--fluid-settings-execution", required=True, type=Path)
    parser.add_argument("--metadata", required=True, type=Path)
    parser.add_argument("--cycles", required=True, type=int, choices=range(1, 21))
    parser.add_argument("--max-step", type=float, default=.005)
    parser.add_argument("--rtol", type=float, default=1e-8)
    parser.add_argument("--phase-operator", choices=("scheduled_reduced", "stage_free_shared_surface"), default="scheduled_reduced")
    args = parser.parse_args()
    if not np.isfinite(args.max_step) or not 0 < args.max_step <= .005:
        parser.error("Require 0 < max-step <= .005s")
    if not np.isfinite(args.rtol) or not 0 < args.rtol <= 1e-6:
        parser.error("Require 0 < rtol <= 1e-6; numerical study, not a physical gate")
    run(args.output.resolve(), args.control_root.resolve(), args.fluid_settings_execution.resolve(),
        args.metadata.resolve(), args.cycles, args.max_step, args.rtol, args.phase_operator)
