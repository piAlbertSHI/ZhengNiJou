"""Compare independently integrated single-cell heat laws on three measured grids.

Native storage, momentum and port transport remain in all branches. This is a
heat-law counterfactual, not Q01's complete distributed solver or system model.
"""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Analyze_HeatDriveECC_SinglePipeHeatStep import read_traces, text, pipe_balance, reference_flux
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_TLDomainInventory import density_table, DENSITY_ATOL_KG_M3


BRANCHES = {"native": "native_traces", "probe": "probe_traces",
            "reference_saved_Nu": "reference_saved_Nu_traces", "reference_Q01": "reference_q01_traces"}


def measured_grid_difference(coarse_t, coarse_y, fine_t, fine_y):
    arrays = [np.asarray(v) for v in (coarse_t, coarse_y, fine_t, fine_y)]
    tc, yc, tf, yf = arrays
    if (any(v.ndim != 1 or not np.isfinite(v).all() for v in arrays)
            or tc.shape != yc.shape or tf.shape != yf.shape or len(tf) < len(tc)
            or len(tc) < 2 or np.any(np.diff(tc) <= 0) or np.any(np.diff(tf) <= 0)):
        raise ValueError("Require finite measured scalar grids")
    fine_dt = tf[1]-tf[0]
    indices = np.rint((tc-tf[0])/fine_dt).astype(int)
    if (np.any(indices < 0) or np.any(indices >= len(tf))
            or not np.allclose(tf[indices], tc, rtol=0, atol=1e-12)):
        raise ValueError("No exact witnessed common grid; interpolation is forbidden")
    return {"max_abs_difference": float(np.max(abs(yc-yf[indices]))),
            "endpoint_abs_difference": float(abs(yc[-1]-yf[indices[-1]])),
            "points_compared": int(len(tc)), "interpolation_used": False}


def refinement_summary(errors):
    if len(errors) != 2 or not np.isfinite(errors).all() or min(errors) < 0:
        raise ValueError("Require two finite nonnegative successive refinement differences")
    ratio = errors[0]/errors[1] if errors[1] > 0 else None
    return {"successive_max_differences": [float(v) for v in errors],
            "decreased": bool(errors[1] < errors[0]),
            "difference_ratio": float(ratio) if ratio is not None else None,
            "observed_log2_ratio": float(np.log2(ratio)) if ratio is not None and ratio > 0 else None,
            "scope": "three-grid short-cell observation, not full temporal/spatial convergence certification"}


def check_sources(root, execution):
    build = root / "component_build/+ecc_pipe_probe"
    probe, reference = build / "observed_pipe.ssc", build / "reference_pipe.ssc"
    if sha256(probe) != execution["probe_source_sha256"] or sha256(reference) != execution["reference_source_sha256"]:
        raise ValueError("Generated source identity mismatch")
    a, b = probe.read_text(), reference.read_text()
    old, new = "    Q_H == Q_conv + Q_cond;", execution["reference_heat_equation"]
    if a.count(old) != 1 or b.count(new) != 1:
        raise ValueError("Ambiguous heat-equation replacement")
    reverted = b.replace(new, old).replace("component reference_pipe", "component observed_pipe").replace(
        "% Reference Heat Pipe (TL) : 2.5", "% Pipe (TL) : 2.5")
    if reverted != a:
        raise ValueError("Reference changes more than its name and one heat equation")
    return {"probe_sha256": sha256(probe), "reference_sha256": sha256(reference),
            "only_declared_heat_equation_and_names_differ": True}


def analyze(root, source_root, prior_root):
    path = root / "single_pipe_execution.json"
    ex = json.loads(path.read_text(encoding="utf-8-sig"))
    if (ex["schema"] != "heatdrive_ecc_single_pipe_reference_v1" or ex["collection_pass"] is not True
            or ex["reference_heat_laws_independently_integrated"] is not True
            or ex["checkpoint_saved"] is not False or ex["production_model_loaded"] is not False
            or ex["production_state_loaded"] is not False or len(ex["cases"]) != 24):
        raise ValueError("Require the completed independent reference study")
    sources = check_sources(root, ex)
    cfgpath = source_root / "conservative/configuration.mat"
    meta = source_root / "conservative/inventory_metadata.json"
    if sha256(cfgpath) != ex["configuration_sha256"] or sha256(meta) != ex["inventory_metadata_sha256"]:
        raise ValueError("Source configuration changed")
    with h5py.File(cfgpath, "r") as cfg:
        pressure = float(cfg["options/branch/network_absolute_pressure_MPa"][0, 0])*1e6
        flow_targets = {name: float(cfg["options/branch/m_dot_"+name.lower()+"_the_kg_per_s"][0, 0]) for name in ("SMA", "SE")}
    prior_path = prior_root / "single_pipe_execution.json"
    prior = json.loads(prior_path.read_text(encoding="utf-8-sig"))
    if prior["collection_pass"] is not True or prior["configuration_sha256"] != ex["configuration_sha256"]:
        raise ValueError("Require completed matching prior native baseline")
    seen, rows, data = set(), [], {}
    for c in ex["cases"]:
        name, flow, delta, step = c["material"], c["mass_flow_command_kgps"], c["wall_step_K"], c["fixed_step_s"]
        key = name, flow, delta, step
        if (name not in flow_targets or abs(flow) != flow_targets[name] or delta not in (-5, 5)
                or step not in (.001, .0005, .00025) or key in seen or c["reference_states_independently_integrated"] is not True):
            raise ValueError("Invalid or duplicate reference matrix member")
        seen.add(key)
        if c["nominal_inventory_temperature_K"] != 293.15 or c["nominal_inventory_pressure_Pa"] != pressure:
            raise ValueError("Nominal mass coordinates changed")
        file = root / c["file"]
        if file.parent.resolve() != root.resolve() or sha256(file) != c["sha256"]:
            raise ValueError("Raw reference case changed")
        with h5py.File(file, "r") as f:
            sealed = json.loads(text(f["record_json"]))
            if any(c[k] != value for k, value in sealed.items()):
                raise ValueError("Sealed case/manifest mismatch")
            branches = {name: read_traces(f, field, step) for name, field in BRANCHES.items()}
        t, native = branches["native"]
        if any(not np.array_equal(tc, t) for tc, _ in branches.values()):
            raise ValueError("Branch clocks differ")
        lookup = density_table(c["fluid_settings"]["saved_inventory_parameters"])
        mass = float(lookup([[293.15, pressure]])[0])*c["area_m2"]*c["length_m"]
        summaries = {}
        for branch, (_, values) in branches.items():
            wall = values.get("probe_wall_T", branches["probe"][1]["probe_wall_T"])
            if (np.max(abs(wall[t <= .02-step]-303.15)) > 1e-9
                    or np.max(abs(wall[t >= .02+step]-(303.15+delta))) > 1e-9):
                raise ValueError("Missing actual heat step")
            rho_error = float(np.max(abs(lookup(np.column_stack((values["T_I"], values["p_I"])))-values["rho_I"])))
            if rho_error > DENSITY_ATOL_KG_M3:
                raise ValueError("Density-table reconstruction failed")
            ledger = pipe_balance(t, values, mass)
            summaries[branch] = {"final_temperature_K": float(values["T_I"][-1]),
                "final_heat_into_fluid_W": float(values["Q_H"][-1]),
                "heat_into_fluid_BE_J": float(np.sum(values["Q_H"][1:]*np.diff(t))),
                "density_lookup_max_error_kg_m3": rho_error, "local_energy_ledger": ledger}
            if branch.startswith("reference_"):
                nu = c["reference_saved_Nu"] if branch == "reference_saved_Nu" else c["reference_Q01_Nu"]
                expected = reference_flux(c, values, nu)
                error = float(np.max(abs(values["Q_H"]-expected)))
                allowance = 1024*np.finfo(float).eps*max(1., float(np.max(abs(expected))))
                if error > allowance:
                    raise ValueError("Reference does not implement its declared heat law")
                summaries[branch]["own_state_heat_equation_max_error_W"] = error
                summaries[branch]["temperature_difference_from_native_at_end_K"] = float(values["T_I"][-1]-native["T_I"][-1])
        probe_differences = {}
        for field in native:
            error = float(np.max(abs(native[field]-branches["probe"][1][field])))
            if error > 1e-10*max(1., float(np.max(abs(native[field])))):
                raise ValueError("Passive probe changes native trajectory")
            probe_differences[field] = error
        baseline = None
        if step == .001:
            old = next(c0 for c0 in prior["cases"] if c0["material"] == name
                       and c0["mass_flow_command_kgps"] == flow and c0["wall_step_K"] == delta)
            oldfile = prior_root / old["file"]
            if sha256(oldfile) != old["sha256"]:
                raise ValueError("Prior raw baseline changed")
            with h5py.File(oldfile, "r") as f:
                ot, ov = read_traces(f, "native_traces")
            baseline = {field: measured_grid_difference(ot, ov[field], t, native[field]) for field in native}
            for field in native:
                if baseline[field]["max_abs_difference"] > 1e-10*max(1., float(np.max(abs(ov[field])))):
                    raise ValueError("Native reference baseline changed beyond declared numerical comparison")
        equal_ref = None
        if c["reference_saved_Nu"] == c["reference_Q01_Nu"]:
            equal_ref = {field: float(np.max(abs(branches["reference_saved_Nu"][1][field]-branches["reference_Q01"][1][field])))
                         for field in native}
            if any(value > 1e-10*max(1., float(np.max(abs(native[field])))) for field, value in equal_ref.items()):
                raise ValueError("Equal reference laws produce inconsistent states")
        rows.append({"file": c["file"], "sha256": c["sha256"], "material": name, "flow_kgps": flow,
                     "wall_step_K": delta, "fixed_step_s": step, "branches": summaries,
                     "native_probe_max_differences_SI": probe_differences,
                     "prior_native_comparison": baseline, "equal_Nu_reference_control_differences_SI": equal_ref})
        data[key] = (c, branches)
    convergence = []
    for name in ("SMA", "SE"):
        for flow in (-flow_targets[name], flow_targets[name]):
            for delta in (-5, 5):
                for branch in ("native", "reference_saved_Nu", "reference_Q01"):
                    sequence = [data[name, flow, delta, step][1][branch] for step in (.001, .0005, .00025)]
                    metrics = {}
                    for field in ("T_I", "Q_H"):
                        comparisons = [measured_grid_difference(a[0], a[1][field], b[0], b[1][field])
                                       for a, b in zip(sequence, sequence[1:])]
                        metrics[field] = {"comparisons": comparisons,
                            **refinement_summary([r["max_abs_difference"] for r in comparisons])}
                    convergence.append({"material": name, "flow_kgps": flow, "wall_step_K": delta,
                                        "branch": branch, "metrics": metrics})
    result = {"schema": "heatdrive_ecc_integrated_single_pipe_reference_review_v1",
        "execution_commit": ex["execution_commit"], "execution_sha256": sha256(path),
        "raw_root": str(root), "configuration_sha256": ex["configuration_sha256"],
        "prior_native_execution_sha256": sha256(prior_path), "generated_source_check": sources,
        "analysis_dependency_sha256": {str(Path(__file__)): sha256(Path(__file__)),
            str(Path(__file__).with_name("Analyze_HeatDriveECC_SinglePipeHeatStep.py")):
            sha256(Path(__file__).with_name("Analyze_HeatDriveECC_SinglePipeHeatStep.py"))},
        "cases": rows, "three_grid_observations": convergence,
        "reference_states_independently_integrated": True,
        "scope": "one-cell heat-law counterfactual only; native TL storage/ports/momentum remain in every branch",
        "spatial_order_or_grid_convergence_verified": False,
        "paper_full_equation_solver_reproduced": False, "full_device_first_law_verified": False,
        "coupled_performance_gap_attributed": False, "production_recovery_allowed": False,
        "outer_solve_allowed": False, "paired_Table4_allowed": False}
    return result, data


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--prior-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Never overwrite integrated-reference evidence")
    result, _ = analyze(args.root.resolve(), args.source_root.resolve(), args.prior_root.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False)+"\n", encoding="utf-8")
    print(json.dumps({"output": str(args.output), "sha256": sha256(args.output), "cases": len(result["cases"]),
        "all_temperature_refinement_differences_decreased": all(
            r["metrics"]["T_I"]["decreased"] for r in result["three_grid_observations"]),
        "coupled_performance_claim": False}))
