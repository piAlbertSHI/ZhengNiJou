"""Adaptive time reference for the same nonlinear mass/energy EOS equations.

This is not fixed-step Simulink ODE3. No EOS smoothing, pressure projection,
temperature clamp, mass/energy correction, or production-state import occurs.
"""
import argparse
from dataclasses import replace
import hashlib
import inspect
import json
from pathlib import Path
import subprocess
import time
import traceback

import numpy as np
from scipy.integrate import DOP853

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Reference_HeatDriveECC_ConservativeTransport import Bed
from Reference_HeatDriveECC_EnthalpyTransport import EnthalpyBed, EOSDomainError
from Run_HeatDriveECC_ConservativeTransport import write_json
from Run_HeatDriveECC_EnthalpyTransport import load_inputs, MASS_TOL_KG, ENERGY_TOL_J


# A declared numerical invariant target, NOT a Qian mechanism/pressure gate.
# 1 Pa / 850000 Pa = 1.18e-6, well above EOS inversion roundoff and below
# a meaningful hydraulic head scale. It cannot validate a pump or idle closure.
PRESSURE_INVARIANT_TARGET_PA = 1.


class DomainAwareDOP853(DOP853):
    """Reject an invalid internal EOS trial, not the accepted physical state.

    The inspected SciPy step assigns t/y/f only after acceptance. Pin this
    private implementation contract; never restore/reset a partially advanced
    physical state. Only the proposed numerical step length may change.
    """
    step_source_sha256 = "172D2034DC019B2CF3F6E9A2B7A6CF000A1658B8B9DC2D074E9FDEF14CA8BACB"

    def __init__(self, *args, **kwargs):
        source = inspect.getsource(DOP853._step_impl)
        if hashlib.sha256(source.encode()).hexdigest().upper() != self.step_source_sha256:
            raise ValueError("Reinspect installed SciPy step acceptance contract before using domain rejection")
        self.domain_rejections = 0
        self.first_domain_rejection = None
        super().__init__(*args, **kwargs)

    def _step_impl(self):
        old_t, old_y, old_f = self.t, self.y.copy(), self.f.copy()
        for _ in range(20):
            try:
                return super()._step_impl()
            except EOSDomainError as error:
                if self.t != old_t or not np.array_equal(self.y, old_y) or not np.array_equal(self.f, old_f):
                    raise RuntimeError("EOS exception changed accepted physical state; no reset is permitted") from error
                self.domain_rejections += 1
                if self.first_domain_rejection is None:
                    self.first_domain_rejection = {"accepted_time_s": old_t, "proposed_h_s": self.h_abs,
                        "accepted_state_unchanged": True, "cause": str(error), "EOS_trial_details": error.details}
                self.h_abs = min(self.h_abs, self.max_step)*.25
                if self.h_abs <= 10*abs(np.nextafter(self.t, np.inf)-self.t):
                    break
        return False, "No admissible EOS trial step; accepted state retained, no projection applied"


def adaptive_case(bed, flow, material, stop, rtol, sample_times):
    n = bed.nodes
    left, right = ((393.15, 303.15) if material == "SMA" else (276.95, 303.15))
    initial = bed.initial_state()
    state = initial.copy()
    initial_mass = float(initial[:n].sum())
    # Mass and energy tolerances retain their own dimensions/scales. These are
    # integrator local-error controls, not relaxed conservation thresholds.
    atol = np.r_[np.full(n, rtol*1e-5), np.full(2*n, rtol*.01), rtol*1e-5, rtol*.01]
    saved_times, profiles, temperatures, pressures, faces = [], [], [], [], []
    monitor = {"max_mass_residual_kg": 0., "max_energy_residual_J": 0.,
               "max_pressure_drift_Pa": 0., "fluid_min_K": bed.eos.Tref,
               "fluid_max_K": bed.eos.Tref, "min_step_s": stop, "max_step_s": 0., "accepted_steps": 0}
    def check(values):
        observed = bed.unpack(values)
        monitor["max_mass_residual_kg"] = max(monitor["max_mass_residual_kg"], float(abs(values[:n].sum()-initial_mass-values[-2])))
        monitor["max_energy_residual_J"] = max(monitor["max_energy_residual_J"], float(abs(values[n:3*n].sum()-values[-1])))
        monitor["max_pressure_drift_Pa"] = max(monitor["max_pressure_drift_Pa"], float(np.max(abs(observed["p"]-bed.eos.pref))))
        monitor["fluid_min_K"] = min(monitor["fluid_min_K"], float(observed["T"].min()))
        monitor["fluid_max_K"] = max(monitor["fluid_max_K"], float(observed["T"].max()))
        return observed
    def save(t, values, command):
        observed = check(values)
        _, flux = bed.evaluate(values, command, left, right)
        saved_times.append(t)
        profiles.append(values.copy())
        temperatures.append(np.r_[observed["T"], observed["solid_T"]])
        pressures.append(observed["p"].copy())
        faces.append(flux["mass_faces_kg_s"].copy())
    save(0., state, flow)
    wanted = list(sample_times[1:])
    transitions = []
    begin = 0.
    evaluations = 0
    previous_end = None
    domain_rejections, first_domain_rejections = 0, []
    for end, command in ((stop/2, flow), (stop, -flow)):
        if previous_end is not None:
            transitions.append({"time_s": begin, "all_coordinates_bitwise_unchanged": bool(np.array_equal(state, previous_end))})
        solver = DomainAwareDOP853(lambda t, y: bed.rhs(y, command, left, right), begin, state, end,
                        rtol=rtol, atol=atol, max_step=.001)
        while solver.status == "running":
            old_t = solver.t
            solver.step()
            if solver.status == "failed":
                raise RuntimeError("Adaptive time reference failed; preserve this packet")
            step = solver.t-old_t
            monitor["accepted_steps"] += 1
            monitor["min_step_s"] = min(monitor["min_step_s"], step)
            monitor["max_step_s"] = max(monitor["max_step_s"], step)
            check(solver.y)
            selected = []
            while wanted and wanted[0] <= solver.t:
                selected.append(wanted.pop(0))
            if selected:
                dense = solver.dense_output()
                for t in selected:
                    save(t, dense(t), command)
        state = solver.y.copy()
        previous_end = state.copy()
        evaluations += solver.nfev
        domain_rejections += solver.domain_rejections
        if solver.first_domain_rejection is not None:
            first_domain_rejections.append(solver.first_domain_rejection)
        begin = end
    if wanted or not np.array_equal(saved_times, sample_times):
        raise RuntimeError("Incomplete adaptive sample output")
    return {"time_s": np.asarray(saved_times), "conserved_diagnostic_profiles": np.asarray(profiles),
            "fluid_and_solid_temperature_K": np.asarray(temperatures), "pressure_Pa": np.asarray(pressures),
            "mass_face_kg_s": np.asarray(faces)}, {
        **monitor, "nodes": n, "stop_s": stop, "rtol": rtol, "atol_primary_coordinates": atol.tolist(),
        "RHS_evaluations": evaluations, "left_temperature_K": left, "right_temperature_K": right,
        "internal_EOS_domain_trial_rejections": domain_rejections,
        "first_domain_rejections": first_domain_rejections,
        "flow_magnitude_kg_s": flow, "transitions": transitions,
        "pressure_invariant_numerical_target_Pa": PRESSURE_INVARIANT_TARGET_PA,
        "pressure_invariant_numerical_target_pass": monitor["max_pressure_drift_Pa"] <= PRESSURE_INVARIANT_TARGET_PA,
        "mass_numerical_invariant_pass": monitor["max_mass_residual_kg"] <= MASS_TOL_KG,
        "energy_numerical_invariant_pass": monitor["max_energy_residual_J"] <= ENERGY_TOL_J,
        "total_mass_change_kg": float(state[:n].sum()-initial_mass),
        "net_mass_integral_kg": float(state[-2]), "net_energy_integral_J": float(state[-1]),
        "monitor_scope": "accepted endpoints AND saved dense samples; not every rejected internal stage",
        "saved_sample_method": "DOP853 dense output inside individual accepted steps, never across flow switching",
        "state_or_pressure_projection_applied": False}


def run(output, fixed_root, control_root, fluid_execution, study):
    output.mkdir(parents=True, exist_ok=False)
    fixed_path = fixed_root/"enthalpy_execution.json"
    fixed = json.loads(fixed_path.read_text(encoding="utf-8"))
    if fixed.get("collection_complete") is not True:
        raise ValueError("Preserve and diagnose a completed fixed-BS3 smoke control first")
    sources = [Path(__file__), Path(__file__).with_name("Reference_HeatDriveECC_EnthalpyTransport.py"),
               Path(__file__).with_name("Run_HeatDriveECC_EnthalpyTransport.py"),
               Path(__file__).with_name("Reference_HeatDriveECC_ConservativeTransport.py"),
               Path(__file__).with_name("Audit_HeatDriveECC_NativeAccumulation.py"),
               Path(__file__).with_name("Audit_HeatDriveECC_TLDomainInventory.py")]
    record = {"schema": "heatdrive_ecc_active_enthalpy_adaptive_reference_v1", "study": study,
        "execution_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=Path(__file__).parent, text=True).strip(),
        "source_sha256": {str(p): sha256(p) for p in sources},
        "fixed_control_execution_path": str(fixed_path), "fixed_control_execution_sha256": sha256(fixed_path),
        "fluid_settings_execution_path": str(fluid_execution), "fluid_settings_execution_sha256": sha256(fluid_execution),
        "physical_equations_changed_from_fixed_control": False,
        "integration": "adaptive DOP853, max_step=1ms; NOT fixed-step ODE3",
        "internal_domain_trial_handling": "reject proposed numerical step only, never reset/project accepted physical state",
        "installed_SciPy_step_source_sha256": DomainAwareDOP853.step_source_sha256,
        "rtol_levels": [1e-10, 1e-11], "collection_complete": False, "cases": [],
        "pressure_invariant_target_Pa": PRESSURE_INVARIANT_TARGET_PA,
        "pressure_target_scope": "numerical active-component invariant, not a literature mechanism gate or pump capability",
        "sealed_dwell_supported": False, "phase_transformation_or_mechanical_power_included": False,
        "mass_tolerance_kg": MASS_TOL_KG, "energy_tolerance_J": ENERGY_TOL_J,
        "production_state_loaded": False, "checkpoint_saved": False, "production_recovery_allowed": False,
        "full_coupled_qualification": False, "outer_solve_allowed": False, "Table4_reproduction_claim": False,
        "scientific_gates_modified": False, "state_projection_applied": False}
    write_json(output/"preflight.json", record)
    started = time.perf_counter()
    try:
        control, eos, contracts = load_inputs(control_root, fluid_execution)
        if contracts != fixed["physical_contracts"]:
            raise ValueError("Adaptive reference changed physical inputs")
        record["physical_contracts"] = contracts
        stop = .1 if study == "smoke" else 10.
        sample_times = np.array([0., .01, .02, .025, .05, .06, .075, .1] if study == "smoke" else
            [0., .01, .05, .1, .25, .5, 1., 3.5, 5., 5.1, 6., 8.5, 9., 10.])
        for material in ("SMA", "SE"):
            geometry_contract = control["physical_contracts"][material]
            geometry = replace(Bed(**geometry_contract["bed"]), slope_limiter="MC")
            bed = EnthalpyBed(geometry, eos[material], 3.66, geometry_contract["Dh_m"], geometry_contract["surface_area_m2"])
            for rtol in record["rtol_levels"]:
                record["active_case"] = {"material": material, "rtol": rtol, "stop_s": stop}
                begin = time.perf_counter()
                profiles, row = adaptive_case(bed, geometry_contract["nominal_mass_flow_kg_s"], material, stop, rtol, sample_times)
                file = output/f"{material}_n21_rtol{rtol:g}_{study}.npz"
                np.savez_compressed(file, **profiles)
                record["cases"].append({**row, "material": material, "file": file.name,
                    "sha256": sha256(file), "bytes": file.stat().st_size, "wall_seconds": time.perf_counter()-begin})
        record.update(collection_complete=True, wall_seconds=time.perf_counter()-started,
            all_four_numerical_invariants_pass=all(r["mass_numerical_invariant_pass"] and r["energy_numerical_invariant_pass"]
                and r["pressure_invariant_numerical_target_pass"] for r in record["cases"]),
            raw_npz_bytes=sum(r["bytes"] for r in record["cases"]),
            retention="selected profiles only; accepted/rejected solver-stage histories are not retained")
        write_json(output/"enthalpy_reference_execution.json", record)
        print(json.dumps({"output": str(output), "collection_complete": True, "cases": len(record["cases"]),
            "all_numerical_invariants_pass": record["all_four_numerical_invariants_pass"],
            "max_pressure_drift_Pa": max(r["max_pressure_drift_Pa"] for r in record["cases"]),
            "wall_seconds": record["wall_seconds"], "raw_npz_bytes": record["raw_npz_bytes"],
            "execution_sha256": sha256(output/"enthalpy_reference_execution.json"), "production_recovery_allowed": False}))
    except Exception:
        record.update(error_traceback=traceback.format_exc(), wall_seconds=time.perf_counter()-started)
        write_json(output/"FAILED_DO_NOT_RESUME.json", record)
        raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--fixed-root", required=True, type=Path)
    parser.add_argument("--control-root", required=True, type=Path)
    parser.add_argument("--fluid-settings-execution", required=True, type=Path)
    parser.add_argument("--study", choices=("smoke", "active_10s"), required=True)
    arguments = parser.parse_args()
    run(arguments.output.resolve(), arguments.fixed_root.resolve(), arguments.control_root.resolve(),
        arguments.fluid_settings_execution.resolve(), arguments.study)
