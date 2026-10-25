"""Verify a one-way global energy coordinate against storage and the unobserved study.

This checks numerical energy integration only. It is not independent validation
of the physical heat law, whole-device first law, or any recovery state.
"""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Analyze_HeatDriveECC_SinglePipeHeatStep import read_traces
from Analyze_HeatDriveECC_SinglePipeReference import analyze, BRANCHES, measured_grid_difference
from Audit_HeatDriveECC_SegmentedEvidence import sha256


ENERGY_TOL_J = 1e-8  # Existing local inventory tolerance, not an endpoint-only quadrature gate.


def invariant(mass, internal_energy, observer_energy):
    u, e = np.asarray(internal_energy), np.asarray(observer_energy)
    if (not np.isfinite(mass) or mass <= 0 or u.ndim != 1 or u.shape != e.shape or len(u) < 2
            or not np.isfinite(u).all() or not np.isfinite(e).all() or abs(e[0]) > 1e-12):
        raise ValueError("Require a finite cold-initialized one-way energy coordinate")
    residual = mass*(u-u[0])-(e-e[0])
    return {"max_abs_storage_minus_integrated_net_J": float(np.max(abs(residual))),
            "endpoint_storage_minus_integrated_net_J": float(residual[-1]),
            "observer_initial_J": float(e[0]), "energy_tolerance_J": ENERGY_TOL_J,
            "numerical_inventory_invariant_pass": bool(np.max(abs(residual)) <= ENERGY_TOL_J),
            "basis": "same global integrator advances independent dEobs/dt=Phi_A+Phi_B+QH; no physical feedback",
            "whole_device_first_law_or_heat_law_validation": False}


def audit(root, source_root, local_root, without_observer_root):
    execution_path = root/"single_pipe_execution.json"
    ex = json.loads(execution_path.read_text(encoding="utf-8-sig"))
    if ex.get("one_way_energy_observer_enabled") is not True:
        raise ValueError("Require the explicit one-way energy-observer experiment")
    result, data = analyze(root, source_root, local_root, "global_ODE3")
    baseline_path = without_observer_root/"single_pipe_execution.json"
    baseline = json.loads(baseline_path.read_text(encoding="utf-8-sig"))
    if (baseline["collection_pass"] is not True or baseline["integration"] != "global_ODE3"
            or baseline.get("one_way_energy_observer_enabled", False) or len(baseline["cases"]) != 24
            or baseline["configuration_sha256"] != ex["configuration_sha256"]):
        raise ValueError("Require the completed identical-integration baseline without the observer")
    observer = ("variables (Access = private)\n"
                "    observer_energy = {value = {0, 'J'}, priority = priority.high};\nend\n"
                "equations\n    der(observer_energy) == Phi_A + Phi_B + Q_H;\nend\n\n")
    source_checks = []
    for name in ("observed_pipe.ssc", "reference_pipe.ssc"):
        current = root/"component_build/+ecc_pipe_probe"/name
        old = without_observer_root/"component_build/+ecc_pipe_probe"/name
        current_text, old_text = current.read_text(), old.read_text()
        if current_text.count(observer) != 1 or current_text.count("observer_energy") != 2 or current_text.replace(observer, "") != old_text:
            raise ValueError("Observer changes original physical equations or has feedback")
        source_checks.append({"file": name, "source_sha256": sha256(current),
                              "baseline_sha256": sha256(old), "only_one_way_observer_added": True})
    rows = []
    for row in result["cases"]:
        key = row["material"], row["flow_kgps"], row["wall_step_K"], row["fixed_step_s"]
        c, current = data[key]
        old = next(c0 for c0 in baseline["cases"] if (c0["material"], c0["mass_flow_command_kgps"],
                   c0["wall_step_K"], c0["fixed_step_s"]) == key)
        if c["solver_contract"] != old["solver_contract"]:
            raise ValueError("Observer contrast changed the actual solver contract")
        for field in ("area_m2", "length_m", "Dh_m", "saved_Nu", "fluid_settings", "step_time_s"):
            if c[field] != old[field]:
                raise ValueError("Observer contrast changed physical parameters")
        oldfile = without_observer_root/old["file"]
        if sha256(oldfile) != old["sha256"]:
            raise ValueError("Observer-free raw control changed")
        with h5py.File(oldfile, "r") as f:
            previous = {b: read_traces(f, field, c["fixed_step_s"]) for b, field in BRANCHES.items()}
        comparisons, balances = {}, {}
        for branch, (time, values) in current.items():
            ot, ov = previous[branch]
            comparisons[branch] = {field: measured_grid_difference(ot, ov[field], time, values[field]) for field in ov}
            for field in ov:
                allowance = (row["producer_native_probe_allowances_converted_to_SI"][field]
                             if field in row["producer_native_probe_allowances_converted_to_SI"]
                             else 1e-10*max(1., float(np.max(abs(ov[field])))))
                if comparisons[branch][field]["max_abs_difference"] > allowance:
                    raise ValueError("One-way observer altered observed physical trajectory")
            if branch != "native":
                mass = row["branches"][branch]["sampled_global_energy_diagnostic"]["nominal_mass_kg"]
                balances[branch] = invariant(mass, values["u_I"], values["observer_energy"])
        rows.append({"file": row["file"], "raw_sha256": row["sha256"], "material": row["material"],
                     "flow_kgps": row["flow_kgps"], "wall_step_K": row["wall_step_K"],
                     "fixed_step_s": row["fixed_step_s"], "observer_energy_balances": balances,
                     "observer_free_control_sha256": old["sha256"], "physical_trajectory_comparisons": comparisons})
    result["one_way_energy_observer_audit"] = {
        "source_checks": source_checks, "unobserved_execution_sha256": sha256(baseline_path), "cases": rows,
        "all_72_inventory_invariants_pass": all(b["numerical_inventory_invariant_pass"] for r in rows
                                                 for b in r["observer_energy_balances"].values()),
        "physical_trajectories_unchanged_within_declared_comparison": True,
        "observer_state_added": True, "production_or_OP_structure_unchanged_claim": False,
        "observer_state_is_physical_heat_capacity": False,
        "full_device_first_law_verified": False}
    result["analysis_dependency_sha256"][str(Path(__file__))] = sha256(Path(__file__))
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("root", "source-root", "local-root", "without-observer-root", "output"):
        parser.add_argument("--"+name, type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Never overwrite energy observer evidence")
    record = audit(args.root.resolve(), args.source_root.resolve(), args.local_root.resolve(), args.without_observer_root.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(record, indent=2, allow_nan=False)+"\n", encoding="utf-8")
    print(json.dumps({"output": str(args.output), "sha256": sha256(args.output),
                      "all_72_inventory_invariants_pass": record["one_way_energy_observer_audit"]["all_72_inventory_invariants_pass"],
                      "full_device_first_law_verified": False}))
