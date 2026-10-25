"""Run compact multi-node transport verification and frozen-phase sensible beds.

No production MATLAB model, Operating Point, material history or PI is loaded.
Outputs are diagnostic profiles, not restorable checkpoints. New directory only.
"""
import argparse
from dataclasses import asdict, replace
import json
from pathlib import Path
import platform
import subprocess
import time
import traceback

import h5py
import numpy as np
import scipy

from Analyze_HeatDriveECC_SinglePipeHeatStep import read_traces
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Reference_HeatDriveECC_ConservativeTransport import Bed, advance_segments, affine_exponential


ENERGY_TOL_J = 1e-8  # Existing component numerical-inventory tolerance.
SAMPLES_S = np.array([0., .02, .1, .25, .5, 1., 3.5, 4., 5., 5.1, 6., 8.5, 9., 10.])


def write_json(path, value):
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, indent=2, allow_nan=False)
        stream.write("\n")


def sinusoidal_average(nodes, velocity, diffusivity, elapsed, displacement=None):
    centers = (np.arange(nodes) + .5)/nodes
    shift = velocity*elapsed if displacement is None else displacement
    return np.sinc(1/nodes) * np.exp(-diffusivity*(2*np.pi)**2*elapsed) * np.sin(2*np.pi*(centers-shift))


def smooth_spatial_review():
    """Exact PDE cell averages vs expm of the semidiscrete operator (no time error)."""
    rows = []
    for velocity, diffusivity in ((.4, 0.), (-.4, 0.), (0., .01), (.4, .01), (-.4, .01)):
        errors = []
        for nodes in (32, 64, 128):
            bed = Bed(nodes, 1., 1., 1., 1., diffusivity, 1., 1., 1., 0., 0., periodic=True)
            initial = np.r_[sinusoidal_average(nodes, velocity, diffusivity, 0.), np.zeros(nodes+1)]
            final = affine_exponential(lambda y: bed.rhs(y, velocity), initial, .5)
            exact = sinusoidal_average(nodes, velocity, diffusivity, .5)
            errors.append(float(np.sqrt(np.mean((final[:nodes]-exact)**2))))
        orders = [float(np.log2(a/b)) for a, b in zip(errors[:-1], errors[1:])]
        rows.append({"velocity_m_s": velocity, "diffusivity_m2_s": diffusivity,
                     "nodes": [32, 64, 128], "L2_cell_average_errors_K": errors,
                     "observed_spatial_orders": orders,
                     "second_order_observation_pass": all(1.8 < p < 2.2 for p in orders)})
    nodes = 64
    bed = Bed(nodes, 1., 1., 1., 1., .01, 1., 1., 1., 0., 0., periodic=True)
    initial = np.r_[sinusoidal_average(nodes, .4, .01, 0.), np.zeros(nodes+1)]
    forward = affine_exponential(lambda y: bed.rhs(y, .4), initial, .25)
    reverse = affine_exponential(lambda y: bed.rhs(y, -.4), forward, .25)
    exact = sinusoidal_average(nodes, .4, .01, .5, displacement=0.)
    return {"scope": "periodic smooth constant-property PDE; no phase/pressure/boundary inference",
            "time_propagation": "scipy.sparse.linalg.expm_multiply on affine semidiscrete operator",
            "rows": rows,
            "reversal_L2_error_K": float(np.sqrt(np.mean((reverse[:nodes]-exact)**2))),
            "reversal_energy_residual_J": float(abs(bed.energy(reverse)-bed.energy(initial))),
            "spatial_observations_all_pass": all(r["second_order_observation_pass"] for r in rows)}


def open_boundary_review():
    """Manufactured smooth advection profile checks the actual open-inlet closure.

    Tbar(x,t) is a cell average of sin(2*pi*(x-v*t))+2; boundary values use the
    same exact traveling wave. Diffusion/heat exchange are off. This is not a
    physical reservoir-cycle trial. Adaptive high-order SciPy isolates space.
    """
    from scipy.integrate import solve_ivp
    rows = []
    for velocity in (.4, -.4):
        errors = []
        for nodes in (32, 64, 128):
            bed = Bed(nodes, 1., 1., 1., 1., 0., 1., 1., 1., 0., 0.)
            initial = np.r_[sinusoidal_average(nodes, velocity, 0., 0.)+2., np.zeros(nodes+1)]
            rhs = lambda t, y: bed.rhs(y, velocity,
                np.sin(-2*np.pi*velocity*t)+2., np.sin(2*np.pi*(1-velocity*t))+2.)
            solution = solve_ivp(rhs, (0., .5), initial, method="DOP853", rtol=1e-11, atol=1e-13,
                                 max_step=.001, t_eval=[.5])
            if not solution.success:
                raise RuntimeError(solution.message)
            exact = sinusoidal_average(nodes, velocity, 0., .5)+2.
            errors.append(float(np.sqrt(np.mean((solution.y[:nodes, -1]-exact)**2))))
        orders = [float(np.log2(a/b)) for a, b in zip(errors[:-1], errors[1:])]
        rows.append({"velocity_m_s": velocity, "nodes": [32, 64, 128],
                     "L2_cell_average_errors_K": errors, "observed_spatial_orders": orders,
                     "errors_decrease": all(a > b for a, b in zip(errors[:-1], errors[1:]))})
    return {"scope": "open-inlet smooth traveling-wave boundary verification, not pressure or pump capability",
            "temporal_reference": "SciPy DOP853 rtol=1e-11 atol=1e-13 max_step=0.001s",
            "rows": rows}


def load_cold_contract(source_root, cell_root):
    configuration = source_root/"conservative/configuration.mat"
    execution_path = cell_root/"single_pipe_execution.json"
    execution = json.loads(execution_path.read_text(encoding="utf-8-sig"))
    if (execution.get("collection_pass") is not True or execution.get("integration") != "global_ODE3"
            or execution["configuration_sha256"] != sha256(configuration)):
        raise ValueError("Require the completed matching global-cell input witness")
    contracts, dependencies = {}, [{"path": str(configuration), "sha256": sha256(configuration)},
                                  {"path": str(execution_path), "sha256": sha256(execution_path)}]
    with h5py.File(configuration, "r") as file:
        def scalar(name):
            value = float(np.asarray(file["options/"+name]).item())
            if not np.isfinite(value):
                raise ValueError("Nonfinite physical input: " + name)
            return value
        for material, stem in (("SMA", "driver"), ("SE", "se")):
            row = next(r for r in execution["cases"] if r["material"] == material)
            raw = cell_root/row["file"]
            if raw.resolve().parent != cell_root.resolve() or sha256(raw) != row["sha256"]:
                raise ValueError("Unsealed or external cold-property witness")
            with h5py.File(raw, "r") as case:
                clock, values = read_traces(case, "probe_traces", row["fixed_step_s"], row["stop_time_s"])
            if clock[0] != 0 or values["T_I"][0] != 303.15:
                raise ValueError("Cold-property sample is not at the declared reference temperature")
            prefix = material.lower()
            area = scalar("branch/"+prefix+"_pipe_flow_area_m2")
            length = scalar("branch/"+prefix+"_pipe_length_m")
            diameter = scalar("branch/"+prefix+"_pipe_hydraulic_diameter_m")
            surface = scalar("branch/"+prefix+"_pipe_wetted_area_m2")
            if not np.isclose(surface, 4*area*length/diameter, rtol=1e-12, atol=0):
                raise ValueError("Inconsistent saved heat-transfer geometry")
            contracts[material] = {
                "bed": asdict(Bed(21, length, area, float(values["rho_I"][0]), float(values["cp_I"][0]),
                    float(values["k_I"][0]), scalar("geometry/"+stem+"_cross_section_m2"),
                    scalar("geometry/"+stem+"_mass_kg"), scalar("material/"+material+"/cp_J_per_kgK"),
                    scalar("solid/k_"+prefix+"_W_per_mK"), 3.66*float(values["k_I"][0])*surface/diameter)),
                "reference_temperature_K": 303.15, "Nu_used": 3.66,
                "saved_configuration_Nu_not_silently_used": scalar("branch/"+prefix+"_pipe_Nu"),
                "nominal_mass_flow_kg_s": scalar("branch/m_dot_"+prefix+"_the_kg_per_s"),
                "Dh_m": diameter, "surface_area_m2": surface,
                "fluid_property_basis": "measured cold t=0 rho/cp/k from sealed single-cell probe; frozen for every new run",
                "native_nominal_293p15K_inventory_equivalence_claim": False,
                "property_witness_raw": str(raw), "property_witness_sha256": sha256(raw)}
            dependencies.append({"path": str(raw), "sha256": sha256(raw)})
    return contracts, dependencies


def segments_for(material, flow):
    if material == "SMA":
        drives = [(5., flow, 5., 0.), (10., -flow, 5., 0.)]
    else:
        drives = [(3.5, 0., 0., 0.), (5., flow, 5., 0.),
                  (8.5, 0., 0., 0.), (10., -flow, 0., -5.)]
    return [{"end_s": t, "mdot_kg_s": m, "left_K": a, "right_K": b} for t, m, a, b in drives]


def exact_samples(bed, segments, sample_times):
    state = np.zeros(bed.state_size)
    result = [state.copy()]
    current = 0.
    for segment in segments:
        rhs = lambda y: bed.rhs(y, segment["mdot_kg_s"], segment["left_K"], segment["right_K"])
        for target in sample_times[(sample_times > current) & (sample_times <= segment["end_s"])]:
            state = affine_exponential(rhs, state, float(target-current))
            current = target
            result.append(state.copy())
    return np.asarray(result)


def run(output, source_root, cell_root):
    output.mkdir(parents=True, exist_ok=False)
    started = time.perf_counter()
    sources = [Path(__file__), Path(__file__).with_name("Reference_HeatDriveECC_ConservativeTransport.py"),
               Path(__file__).with_name("Analyze_HeatDriveECC_SinglePipeHeatStep.py")]
    producer = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=Path(__file__).parent, text=True).strip()
    record = {"schema": "heatdrive_ecc_conservative_transport_execution_v1", "execution_commit": producer,
        "source_sha256": {str(p): sha256(p) for p in sources},
        "runtime": {"python": platform.python_version(), "numpy": np.__version__, "scipy": scipy.__version__},
        "collection_complete": False, "full_coupled_qualification": False, "production_state_loaded": False,
        "checkpoint_saved": False, "production_recovery_allowed": False, "outer_solve_allowed": False,
        "Table4_reproduction_claim": False, "scientific_gates_modified": False,
        "scope": "constant-property, frozen-phase, independent conjugate sensible beds; no hydraulics/accessories/coupling force",
        "boundary_contract": "advective prescribed reservoir inlet; insulated axial conductive ends; adiabatic solid ends",
        "temporal_method": "fixed-step BS3 coefficients; event-aligned drives; no local BE solver",
        "drive_scope": "5K small-signal directional tests; NOT the Q01 hot-source or complete-cycle boundary contract",
        "state_basis": "fixed-location fluid/solid cell-average temperature deviations; constant per-cell masses; external energy ledger",
        "claims_not_made": ["variable-property enthalpy transport", "Q01 literal boundary stencil",
                            "pump capability", "phase completion", "whole-device first law", "periodicity", "C200 restore"]}
    write_json(output/"preflight.json", record)
    try:
        contracts, dependencies = load_cold_contract(source_root, cell_root)
        record.update(input_dependencies=dependencies, physical_contracts=contracts)
        record["periodic_smooth_spatial_review"] = smooth_spatial_review()
        record["open_boundary_review"] = open_boundary_review()
        results, arrays = [], {}
        for material, contract in contracts.items():
            segments = segments_for(material, contract["nominal_mass_flow_kg_s"])
            exact = None
            for nodes, dt, order in ((21, .001, 2), (42, .001, 2), (84, .001, 2),
                                      (84, .0005, 2), (84, .00025, 2), (21, .001, 1)):
                bed = replace(Bed(**contract["bed"]), nodes=nodes, advection_order=order)
                identifier = f"{material}_n{nodes}_dt{dt:g}_upwind{order}"
                begin = time.perf_counter()
                samples, meta = advance_segments(bed, segments, dt, SAMPLES_S)
                if nodes == 84 and exact is None:
                    exact = exact_samples(bed, segments, SAMPLES_S)
                path = output/(identifier+".npz")
                np.savez_compressed(path, time_s=SAMPLES_S, temperature_deviations_and_energy=samples,
                                    cell_centers_m=(np.arange(nodes)+.5)*bed.dx)
                error = None if nodes != 84 else float(np.max(abs(samples[:, :2*nodes]-exact[:, :2*nodes])))
                results.append({"id": identifier, "material": material, "nodes": nodes,
                    "dt_s": dt, "advection_order": order, "segments": segments,
                    "file": path.name, "bytes": path.stat().st_size, "sha256": sha256(path),
                    "run_wall_seconds": time.perf_counter()-begin,
                    "fluid_mass_kg": bed.fluid_mass, "solid_mass_kg": bed.solid_mass_kg,
                    "max_abs_temperature_error_vs_semidiscrete_expm_K_at_saved_times": error,
                    "advection_CFL": contract["nominal_mass_flow_kg_s"]/(bed.fluid_rho_kg_m3*bed.fluid_area_m2)*dt/bed.dx,
                    "numerical_energy_pass": meta["max_abs_energy_residual_J"] <= ENERGY_TOL_J,
                    "diagnostics": meta})
                arrays[(material, nodes, dt, order)] = samples
            path = output/(material+"_n84_semidiscrete_expm.npz")
            np.savez_compressed(path, time_s=SAMPLES_S, temperature_deviations_and_energy=exact)
            record.setdefault("semidiscrete_references", []).append({"file": path.name, "bytes": path.stat().st_size,
                "sha256": sha256(path), "material": material, "nodes": 84,
                "scope": "independent time propagation of SAME spatial operator; not independent physical validation"})
        record["cases"] = results
        record["energy_tolerance_J"] = ENERGY_TOL_J
        record["all_12_numerical_energy_invariants_pass"] = all(r["numerical_energy_pass"] for r in results)
        temporal, spatial, order_contrasts = [], [], []
        for material in contracts:
            rows = [r for r in results if r["material"] == material and r["nodes"] == 84]
            errors = [r["max_abs_temperature_error_vs_semidiscrete_expm_K_at_saved_times"] for r in rows]
            temporal.append({"material": material, "steps_s": [r["dt_s"] for r in rows],
                "max_temperature_errors_vs_expm_K_at_saved_times": errors,
                "observed_temporal_orders": [float(np.log2(a/b)) for a, b in zip(errors[:-1], errors[1:])],
                "errors_decrease": all(a > b for a, b in zip(errors[:-1], errors[1:]))})
            differences = []
            for coarse, fine in ((21, 42), (42, 84)):
                a, b = arrays[(material, coarse, .001, 2)], arrays[(material, fine, .001, 2)]
                averaged = np.concatenate([b[:, :fine].reshape(len(SAMPLES_S), coarse, 2).mean(axis=2),
                    b[:, fine:2*fine].reshape(len(SAMPLES_S), coarse, 2).mean(axis=2)], axis=1)
                differences.append(float(np.max(abs(a[:, :2*coarse]-averaged))))
            spatial.append({"material": material, "nodes": [21, 42, 84],
                "max_nested_volume_average_differences_K_at_saved_times": differences,
                "interpolation_used": False, "grid_converged_for_full_cycle_claim": False,
                "note": "step fronts; observed periodic smooth order is not a proof for this entire boundary transient"})
            first, second = arrays[(material, 21, .001, 1)], arrays[(material, 21, .001, 2)]
            order_contrasts.append({"material": material,
                "max_first_vs_second_order_temperature_difference_K_at_saved_times": float(np.max(abs(first[:, :42]-second[:, :42]))),
                "native_TL_network_equated_to_first_order": False})
        record.update(temporal_review=temporal, actual_bed_spatial_review=spatial, first_second_order_contrasts=order_contrasts,
                      collection_complete=True, total_wall_seconds=time.perf_counter()-started,
                      raw_npz_bytes=sum(r["bytes"] for r in results+record["semidiscrete_references"]),
                      raw_retention="selected diagnostic profiles only; no per-step full-state history or OP/checkpoints")
        write_json(output/"transport_execution.json", record)
        print(json.dumps({"output": str(output), "collection_complete": True, "cases": len(results),
            "all_numerical_energy_pass": record["all_12_numerical_energy_invariants_pass"],
            "periodic_smooth_spatial_pass": record["periodic_smooth_spatial_review"]["spatial_observations_all_pass"],
            "wall_seconds": record["total_wall_seconds"], "raw_npz_bytes": record["raw_npz_bytes"],
            "execution_sha256": sha256(output/"transport_execution.json"), "production_recovery_allowed": False}))
    except Exception:
        record.update(error_traceback=traceback.format_exc(), production_recovery_allowed=False)
        write_json(output/"FAILED_DO_NOT_RESUME.json", record)
        raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--cell-root", type=Path, required=True)
    arguments = parser.parse_args()
    run(arguments.output.resolve(), arguments.source_root.resolve(), arguments.cell_root.resolve())
