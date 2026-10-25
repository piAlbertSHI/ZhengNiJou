"""Test an explicit MC face-reconstruction alternative after unlimited-front failure.

Preserves the unlimited control as evidence, imports only its sealed physical
parameters, never its states. No temperature clipping, PI or input smoothing.
The nonlinear limited RHS is NOT propagated by a matrix exponential.
"""
import argparse
from dataclasses import replace
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import time
import traceback

import numpy as np
import scipy
from scipy.integrate import solve_ivp

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Reference_HeatDriveECC_ConservativeTransport import Bed, advance_segments
from Run_HeatDriveECC_ConservativeTransport import SAMPLES_S, ENERGY_TOL_J, segments_for, write_json, sinusoidal_average


def nonlinear_reference(bed, segments, sample_times, max_step=.001):
    state = np.zeros(bed.state_size)
    samples = [state.copy()]
    begin = 0.
    evaluations = 0
    for segment in segments:
        selected = sample_times[(sample_times > begin) & (sample_times <= segment["end_s"])]
        rhs = lambda t, y: bed.rhs(y, segment["mdot_kg_s"], segment["left_K"], segment["right_K"])
        solution = solve_ivp(rhs, (begin, segment["end_s"]), state, method="DOP853",
                             rtol=1e-10, atol=1e-12, max_step=max_step, t_eval=selected)
        if not solution.success or solution.t[-1] != segment["end_s"] or not np.isfinite(solution.y).all():
            raise RuntimeError("Incomplete nonlinear time reference: " + solution.message)
        state = solution.y[:, -1].copy()
        samples.extend(solution.y.T)
        evaluations += solution.nfev
        begin = segment["end_s"]
    return np.asarray(samples), evaluations


def smooth_limited_review():
    rows = []
    for velocity in (.4, -.4):
        errors = []
        for nodes in (32, 64, 128):
            bed = Bed(nodes, 1., 1., 1., 1., .01, 1., 1., 1., 0., 0., periodic=True, slope_limiter="MC")
            initial = np.r_[sinusoidal_average(nodes, velocity, .01, 0.), np.zeros(nodes+1)]
            solution = solve_ivp(lambda t, y: bed.rhs(y, velocity), (0., .5), initial,
                                 method="DOP853", rtol=1e-10, atol=1e-12, max_step=.001, t_eval=[.5])
            if not solution.success:
                raise RuntimeError(solution.message)
            errors.append(float(np.sqrt(np.mean((solution.y[:nodes, -1]-sinusoidal_average(nodes, velocity, .01, .5))**2))))
        rows.append({"velocity_m_s": velocity, "nodes": [32, 64, 128], "L2_cell_average_errors_K": errors,
            "observed_spatial_orders": [float(np.log2(a/b)) for a, b in zip(errors[:-1], errors[1:])]})
    return {"scope": "smooth periodic advection-diffusion, nonlinear MC, DOP853 time reference", "rows": rows,
            "global_TVD_theorem_for_BS3_claim": False}


def verify_control(root):
    path = root/"transport_execution.json"
    record = json.loads(path.read_text(encoding="utf-8"))
    if (record.get("collection_complete") is not True or len(record["cases"]) != 12
            or record["production_state_loaded"] is not False or record["checkpoint_saved"] is not False):
        raise ValueError("Incomplete or unrelated control packet")
    for row in record["cases"] + record["semidiscrete_references"]:
        file = root/row["file"]
        if file.resolve().parent != root.resolve() or sha256(file) != row["sha256"]:
            raise ValueError("Changed control raw file")
    for row in record["input_dependencies"]:
        if sha256(Path(row["path"])) != row["sha256"]:
            raise ValueError("Control physical input changed")
    repo = Path(__file__).resolve().parents[2]
    for name, expected in record["source_sha256"].items():
        relative = Path(name).resolve().relative_to(repo).as_posix()
        blob = subprocess.check_output(["git", "show", record["execution_commit"]+":"+relative], cwd=repo)
        if hashlib.sha256(blob).hexdigest().upper() != expected:
            raise ValueError("Control source does not match its recorded producer commit")
    return record


def run(root, control_root):
    root.mkdir(parents=True, exist_ok=False)
    started = time.perf_counter()
    source_files = [Path(__file__), Path(__file__).with_name("Reference_HeatDriveECC_ConservativeTransport.py"),
                    Path(__file__).with_name("Run_HeatDriveECC_ConservativeTransport.py")]
    record = {"schema": "heatdrive_ecc_MC_transport_comparison_v1", "collection_complete": False,
        "execution_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=Path(__file__).parent, text=True).strip(),
        "source_sha256": {str(p): sha256(p) for p in source_files},
        "runtime": {"python": platform.python_version(), "numpy": np.__version__, "scipy": scipy.__version__},
        "control_execution": str(control_root/"transport_execution.json"),
        "control_execution_sha256": sha256(control_root/"transport_execution.json"),
        "method": "MC face slopes + same fixed-step BS3; identical inventories/boundaries/Nu/properties",
        "temperature_clipping": False, "input_smoothing": False, "phase_or_pressure_model_added": False,
        "control_states_imported": False, "checkpoint_saved": False, "production_recovery_allowed": False,
        "Q01_literal_algorithm_equivalence_claim": False, "full_coupled_qualification": False,
        "outer_solve_allowed": False, "Table4_reproduction_claim": False, "scientific_gates_modified": False}
    write_json(root/"preflight.json", record)
    try:
        control = verify_control(control_root)
        record["physical_contracts"] = control["physical_contracts"]
        record["physical_boundaries_and_scope"] = {key: control[key] for key in
            ("scope", "boundary_contract", "drive_scope", "state_basis", "claims_not_made")}
        record["smooth_limited_review"] = smooth_limited_review()
        rows, comparisons, references = [], [], []
        for material, contract in control["physical_contracts"].items():
            segments = segments_for(material, contract["nominal_mass_flow_kg_s"])
            bed = replace(Bed(**contract["bed"]), nodes=84, slope_limiter="MC")
            reference, evaluations = nonlinear_reference(bed, segments, SAMPLES_S)
            # Independent refinement of the adaptive reference, not a fixed-BS3 rerun.
            reference_fine, fine_evaluations = nonlinear_reference(bed, segments, SAMPLES_S, max_step=.0005)
            reference_error = float(np.max(abs(reference[:, :168]-reference_fine[:, :168])))
            reference_path = root/(material+"_n84_MC_DOP853_reference.npz")
            np.savez_compressed(reference_path, time_s=SAMPLES_S, temperature_deviations_and_energy=reference_fine)
            references.append({"material": material, "file": reference_path.name, "sha256": sha256(reference_path),
                "bytes": reference_path.stat().st_size, "rtol": 1e-10, "atol": 1e-12,
                "max_steps_compared_s": [.001, .0005], "max_temperature_difference_K_at_saved_times": reference_error,
                "RHS_evaluations": [evaluations, fine_evaluations],
                "same_nonlinear_spatial_operator_not_physical_validation": True})
            profiles, time_errors = {}, []
            for nodes, dt in ((21, .001), (42, .001), (84, .001), (84, .0005), (84, .00025)):
                bed = replace(Bed(**contract["bed"]), nodes=nodes, slope_limiter="MC")
                begin = time.perf_counter()
                sampled, diagnostics = advance_segments(bed, segments, dt, SAMPLES_S)
                path = root/f"{material}_n{nodes}_dt{dt:g}_MC.npz"
                np.savez_compressed(path, time_s=SAMPLES_S, temperature_deviations_and_energy=sampled,
                                    cell_centers_m=(np.arange(nodes)+.5)*bed.dx)
                lower, upper = ((0., 5.) if material == "SMA" else (-5., 5.))
                observed_min, observed_max = diagnostics["fluid_deviation_range_K_all_major_steps"]
                temperature_error = None
                if nodes == 84:
                    temperature_error = float(np.max(abs(sampled[:, :168]-reference_fine[:, :168])))
                    time_errors.append(temperature_error)
                rows.append({"material": material, "nodes": nodes, "dt_s": dt, "file": path.name,
                    "sha256": sha256(path), "bytes": path.stat().st_size, "wall_seconds": time.perf_counter()-begin,
                    "segments": segments, "diagnostics": diagnostics,
                    "observed_bound_violation_K_all_major_steps": float(max(0., lower-observed_min, observed_max-upper)),
                    "bound_basis": "constant-property passive bed with zero initial deviations and prescribed boundary extrema",
                    "max_temperature_error_vs_DOP853_K_at_saved_times": temperature_error,
                    "numerical_energy_pass": diagnostics["max_abs_energy_residual_J"] <= ENERGY_TOL_J})
                profiles[(nodes, dt)] = sampled
            differences = []
            for coarse, fine in ((21, 42), (42, 84)):
                a, b = profiles[(coarse, .001)], profiles[(fine, .001)]
                avg = np.concatenate([b[:, :fine].reshape(len(SAMPLES_S), coarse, 2).mean(axis=2),
                    b[:, fine:2*fine].reshape(len(SAMPLES_S), coarse, 2).mean(axis=2)], axis=1)
                differences.append(float(np.max(abs(a[:, :2*coarse]-avg))))
            old = next(r for r in control["cases"] if r["material"] == material and r["nodes"] == 84 and r["dt_s"] == .00025)
            comparisons.append({"material": material, "nodes": [21, 42, 84],
                "max_nested_volume_average_differences_K_at_saved_times": differences,
                "max_time_errors_vs_DOP853_K_at_saved_times": time_errors,
                "observed_temporal_orders": [float(np.log2(a/b)) for a, b in zip(time_errors[:-1], time_errors[1:])],
                "unlimited_n84_dt0p25ms_fluid_range_K": old["diagnostics"]["fluid_deviation_range_K_all_major_steps"],
                "grid_converged_for_full_cycle_claim": False, "interpolation_used": False})
        record.update(cases=rows, nonlinear_references=references, comparisons=comparisons,
            all_10_numerical_energy_invariants_pass=all(r["numerical_energy_pass"] for r in rows),
            max_observed_fluid_bound_violation_K=max(r["observed_bound_violation_K_all_major_steps"] for r in rows),
            bound_observation_not_a_global_TVD_proof=True, energy_tolerance_J=ENERGY_TOL_J,
            collection_complete=True, total_wall_seconds=time.perf_counter()-started,
            raw_npz_bytes=sum(r["bytes"] for r in rows+references),
            retention="selected profiles + refined DOP853 reference only; no recoverable checkpoints/per-step states")
        write_json(root/"limited_transport_execution.json", record)
        print(json.dumps({"output": str(root), "collection_complete": True, "cases": len(rows),
            "all_numerical_energy_pass": record["all_10_numerical_energy_invariants_pass"],
            "max_observed_fluid_bound_violation_K": record["max_observed_fluid_bound_violation_K"],
            "wall_seconds": record["total_wall_seconds"], "raw_npz_bytes": record["raw_npz_bytes"],
            "execution_sha256": sha256(root/"limited_transport_execution.json"), "production_recovery_allowed": False}))
    except Exception:
        record.update(error_traceback=traceback.format_exc(), production_recovery_allowed=False)
        write_json(root/"FAILED_DO_NOT_RESUME.json", record)
        raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--control-root", type=Path, required=True)
    arguments = parser.parse_args()
    run(arguments.output.resolve(), arguments.control_root.resolve())
