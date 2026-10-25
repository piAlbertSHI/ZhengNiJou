"""Read sealed compact profiles and distinguish numerical evidence from adoption.

The online all-major-step monitors are producer/source evidence. The selected
saved profiles allow independent selected-time checks, not every-step replay.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Reference_HeatDriveECC_ConservativeTransport import Bed
from Run_HeatDriveECC_ConservativeTransport import SAMPLES_S, ENERGY_TOL_J, write_json
from Run_HeatDriveECC_LimitedTransport import verify_control


def require_source_provenance(record):
    repo = Path(__file__).resolve().parents[2]
    for source, expected in record["source_sha256"].items():
        relative = Path(source).resolve().relative_to(repo).as_posix()
        blob = subprocess.check_output(["git", "show", record["execution_commit"]+":"+relative], cwd=repo)
        if hashlib.sha256(blob).hexdigest().upper() != expected:
            raise ValueError("Source does not match recorded Git producer")


def read_case(root, row, nodes, reference=False):
    path = root/row["file"]
    if (path.resolve().parent != root.resolve() or path.stat().st_size != row["bytes"]
            or sha256(path) != row["sha256"]):
        raise ValueError("Raw profile bytes changed or path escaped packet")
    with np.load(path, allow_pickle=False) as file:
        times = file["time_s"]
        values = file["temperature_deviations_and_energy"]
        if not np.array_equal(times, SAMPLES_S) or values.shape != (len(SAMPLES_S), 2*nodes+1):
            raise ValueError("Missing time samples or inventory coordinates")
        if not np.isfinite(values).all() or np.any(values[0] != 0.):
            raise ValueError("Nonfinite or non-cold diagnostic; state import forbidden")
        if not reference:
            if "cell_centers_m" not in file or file["cell_centers_m"].shape != (nodes,):
                raise ValueError("Missing fixed physical coordinates")
        return values


def nested_metrics(coarse, fine, nodes):
    """Compare actual nested volume averages, never interpolate front positions."""
    if coarse.shape != (len(SAMPLES_S), 2*nodes+1) or fine.shape != (len(SAMPLES_S), 4*nodes+1):
        raise ValueError("Require complete nested fixed-location inventories")
    rows = {}
    for i, name in enumerate(("fluid", "solid")):
        fine_average = fine[:, i*2*nodes:(i+1)*2*nodes].reshape(len(SAMPLES_S), nodes, 2).mean(axis=2)
        error = abs(coarse[:, i*nodes:(i+1)*nodes]-fine_average)
        rows[name] = {"max_over_saved_times_mean_abs_difference_K": float(np.max(np.mean(error, axis=1))),
            "max_over_saved_times_pointwise_difference_K": float(np.max(error)),
            "last_saved_time_mean_abs_difference_K": float(np.mean(error[-1]))}
    return {"coarse_nodes": nodes, "fine_nodes": 2*nodes, "fields": rows,
            "max_over_saved_times_integrated_boundary_energy_difference_J": float(np.max(abs(coarse[:, -1]-fine[:, -1]))),
            "scope": "nested differences, not error to continuum", "interpolation_used": False}


def saved_inventory_check(values, bed, material):
    energy = bed.fluid_capacity * values[:, :bed.nodes].sum(axis=1) + bed.solid_capacity * values[:, bed.nodes:2*bed.nodes].sum(axis=1)
    error = float(np.max(abs(energy-values[:, -1])))
    lower, upper = ((0., 5.) if material == "SMA" else (-5., 5.))
    fluid, solid = values[:, :bed.nodes], values[:, bed.nodes:2*bed.nodes]
    return {"saved_time_max_abs_energy_residual_J": error, "saved_time_energy_pass": error <= ENERGY_TOL_J,
        "saved_time_fluid_bound_violation_K": float(max(0., lower-fluid.min(), fluid.max()-upper)),
        "saved_time_solid_bound_violation_K": float(max(0., lower-solid.min(), solid.max()-upper)),
        "all_major_steps_independently_reconstructed": False}


def analyze(control_root, limited_root):
    control = verify_control(control_root)
    limited_path = limited_root/"limited_transport_execution.json"
    limited = json.loads(limited_path.read_text(encoding="utf-8"))
    require_source_provenance(limited)
    if (limited["collection_complete"] is not True or len(limited["cases"]) != 10
            or limited["physical_contracts"] != control["physical_contracts"]
            or limited["control_execution_sha256"] != sha256(control_root/"transport_execution.json")
            or limited["temperature_clipping"] or limited["input_smoothing"] or limited["control_states_imported"]):
        raise ValueError("Incomplete candidate or changed physical comparison")
    expected = {(m, n, dt) for m in ("SMA", "SE") for n, dt in
                ((21, .001), (42, .001), (84, .001), (84, .0005), (84, .00025))}
    actual = [(r["material"], r["nodes"], r["dt_s"]) for r in limited["cases"]]
    if len(set(actual)) != len(actual) or set(actual) != expected:
        raise ValueError("Missing/duplicate candidate matrix member")
    saved, profiles = [], {}
    for method, root, record in (("unlimited_control", control_root, control), ("MC_candidate", limited_root, limited)):
        if method == "unlimited_control":
            control_keys = [(r["material"], r["nodes"], r["dt_s"], r["advection_order"]) for r in record["cases"]]
            expected_control = {(m, n, dt, order) for m in ("SMA", "SE") for n, dt, order in
                ((21, .001, 2), (42, .001, 2), (84, .001, 2), (84, .0005, 2), (84, .00025, 2), (21, .001, 1))}
            if len(set(control_keys)) != len(control_keys) or set(control_keys) != expected_control:
                raise ValueError("Missing/duplicate unlimited matrix member")
        for row in record["cases"]:
            nodes, material = row["nodes"], row["material"]
            bed_args = dict(record["physical_contracts"][material]["bed"], nodes=nodes)
            if method == "MC_candidate":
                bed_args["slope_limiter"] = "MC"
            bed = Bed(**bed_args)
            values = read_case(root, row, nodes)
            with np.load(root/row["file"], allow_pickle=False) as file:
                if not np.array_equal(file["cell_centers_m"], (np.arange(nodes)+.5)*bed.dx):
                    raise ValueError("Cell coordinates do not match fixed physical volumes")
            saved.append({"method": method, "file": row["file"], "sha256": row["sha256"],
                          "material": material, "nodes": nodes, "dt_s": row["dt_s"],
                          "independent_saved_profile_check": saved_inventory_check(values, bed, material),
                          "producer_online_monitor": row["diagnostics"]})
            profiles[(method, material, nodes, row["dt_s"], row.get("advection_order", 2))] = values
    nonlinear_references = []
    for row in limited["nonlinear_references"]:
        values = read_case(limited_root, row, 84, reference=True)
        calculated = []
        for dt in (.001, .0005, .00025):
            candidate = profiles[("MC_candidate", row["material"], 84, dt, 2)]
            calculated.append(float(np.max(abs(candidate[:, :168]-values[:, :168]))))
        declared = next(r for r in limited["comparisons"] if r["material"] == row["material"])
        if calculated != declared["max_time_errors_vs_DOP853_K_at_saved_times"]:
            raise ValueError("Declared nonlinear temporal errors do not match raw profiles")
        nonlinear_references.append({**row, "errors_recomputed_from_raw": calculated})
    nested = []
    for method in ("unlimited_control", "MC_candidate"):
        for material in ("SMA", "SE"):
            nested.append({"method": method, "material": material,
                "pairs": [nested_metrics(profiles[(method, material, n, .001, 2)],
                                         profiles[(method, material, 2*n, .001, 2)], n) for n in (21, 42)]})
    result = {"schema": "heatdrive_ecc_transport_direction_review_v1",
        "analysis_source_sha256": sha256(Path(__file__)),
        "control_execution_path": str(control_root/"transport_execution.json"),
        "control_execution_sha256": sha256(control_root/"transport_execution.json"),
        "candidate_execution_path": str(limited_path), "candidate_execution_sha256": sha256(limited_path),
        "all_22_selected_profile_energy_checks_pass": all(r["independent_saved_profile_check"]["saved_time_energy_pass"] for r in saved),
        "saved_profiles": saved, "nested_volume_comparisons": nested,
        "nonlinear_time_references": nonlinear_references,
        "unlimited_decision": "do not promote unlimited sharp-front transport to phase-coupled path; numerical overshoot remains at smaller dt and in semidiscrete expm",
        "MC_decision": "provisional conservative bounded-front candidate; not a literal Q01 algorithm or complete-cycle qualification",
        "current_direction": "retain fixed physical inventories and shared fluxes; use an explicitly named limited reconstruction for robust reference development, with smooth and front error budgets separated",
        "unresolved": ["SMA front pointwise grid differences are not decreasing at every refinement",
            "nonlinear limiter switching reduces observed temporal orders; no blanket third-order assertion",
            "all-step solid bound was not separately logged; only saved solid profiles can be rechecked",
            "temperature-dependent enthalpy/mass law", "SMA/SE transformation surfaces and probability coefficients",
            "full mechanical coupling and cycle boundary topology", "buffer/accessory/pump budgets", "C200 compatible recovery", "periodic outer solve and paired Table4"],
        "scientific_gates_modified": False, "production_recovery_allowed": False,
        "full_coupled_qualification": False, "outer_solve_allowed": False, "Table4_reproduction_claim": False,
        "raw_npz_bytes_retained": control["raw_npz_bytes"] + limited["raw_npz_bytes"],
        "raw_retention": "26 small files, distinct methods/grids/time references; no duplicates claimed, no per-step checkpoints",
        "deletion_performed": False}
    return result, profiles, control, limited


def assert_rendered_text_bounds(fig):
    """Check rendered labels, not locator-generated ticks outside the view.

    Matplotlib's tick locator can allocate labels outside xlim/ylim which the
    Axis draw path skips. Recursing over every Text incorrectly rejects these.
    """
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    texts = list(fig.texts)
    for ax in fig.axes:
        texts.extend([ax.title, ax.xaxis.label, ax.yaxis.label,
                      ax.xaxis.offsetText, ax.yaxis.offsetText])
        legend = ax.get_legend()
        if legend is not None:
            texts.extend(legend.get_texts())
            texts.append(legend.get_title())
        for axis in (ax.xaxis, ax.yaxis):
            lower, upper = sorted(axis.get_view_interval())
            for minor in (False, True):
                locations = axis.get_ticklocs(minor=minor)
                ticks = axis.get_minor_ticks(len(locations)) if minor else axis.get_major_ticks(len(locations))
                for location, tick in zip(locations, ticks):
                    if lower <= location <= upper:
                        texts.extend([tick.label1, tick.label2])
    for text in texts:
        if text.get_visible() and text.get_text():
            bounds = text.get_window_extent(renderer)
            canvas = fig.bbox
            if bounds.x0 < canvas.x0-1 or bounds.x1 > canvas.x1+1 or bounds.y0 < canvas.y0-1 or bounds.y1 > canvas.y1+1:
                raise ValueError("Rendered text outside figure: " + text.get_text())


def plot(output, profiles, result):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    plt.rcParams.update({"font.family": "Arial", "font.size": 9, "axes.titlesize": 10,
                         "axes.spines.top": False, "axes.spines.right": False, "svg.fonttype": "none"})
    output.mkdir(parents=True, exist_ok=False)
    files = []
    def save(fig, stem):
        assert_rendered_text_bounds(fig)
        for suffix in ("png", "svg"):
            path = output/(stem+"."+suffix)
            fig.savefig(path, dpi=220)
            files.append({"file": path.name, "sha256": sha256(path), "bytes": path.stat().st_size})
        plt.close(fig)
    fig, axes = plt.subplots(2, 2, figsize=(8.2, 5.5), layout="constrained")
    styles = [("unlimited_control", 1, "First order", "#777777", ":"),
              ("unlimited_control", 2, "Unlimited second order", "#b23a48", "--"),
              ("MC_candidate", 2, "MC candidate", "#007f73", "-")]
    for i, (material, elapsed) in enumerate((("SMA", .1), ("SE", 9.))):
        index = int(np.flatnonzero(SAMPLES_S == elapsed)[0])
        for j, field in enumerate(("fluid", "solid")):
            ax = axes[i, j]
            for method, order, label, color, line in styles:
                values = profiles[(method, material, 21, .001, order)]
                ax.plot((np.arange(21)+.5)/21, values[index, j*21:(j+1)*21],
                        label=label, color=color, linestyle=line, linewidth=1.4)
            ax.set(title=f"({chr(97+2*i+j)}) {material} {field}, t = {elapsed:g} s",
                   xlabel="Physical position x/L", ylabel="Temperature deviation (K)")
            ax.grid(alpha=.2)
    axes[0, 0].legend(fontsize=8)
    fig.suptitle("Isolated sensible-bed transport: identical 21-cell inventories")
    save(fig, "Fig01_transport_fronts")
    fig, axes = plt.subplots(1, 2, figsize=(8.2, 3.8), layout="constrained")
    for ax, material in zip(axes, ("SMA", "SE")):
        row = next(r for r in result["nested_volume_comparisons"] if r["method"] == "MC_candidate" and r["material"] == material)
        for field, metric, label, color, line in (("fluid", "max_over_saved_times_mean_abs_difference_K", "Fluid mean absolute", "#007f73", "-"),
                ("solid", "max_over_saved_times_mean_abs_difference_K", "Solid mean absolute", "#3c6eab", "-"),
                ("fluid", "max_over_saved_times_pointwise_difference_K", "Fluid pointwise maximum", "#b23a48", "--")):
            ax.semilogy([1, 2], [p["fields"][field][metric] for p in row["pairs"]], marker="o", color=color, linestyle=line, label=label)
        ax.set_xticks([1, 2], ["21 vs 42", "42 vs 84"])
        ax.set(title=material+" MC candidate", xlabel="Nested cell-volume comparison", ylabel="Maximum over saved times (K)")
        ax.grid(alpha=.2)
    axes[1].legend(fontsize=8, loc="lower left")
    fig.suptitle("Step fronts: pointwise and volume-mean differences are distinct")
    save(fig, "Fig02_transport_grid_metrics")
    write_json(output/"figure_manifest.json", {"files": files, "text_bounds_pass": True,
        "scope": "isolated sensible transport, not main-paper performance plots"})


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--control-root", type=Path, required=True)
    parser.add_argument("--limited-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    result, profiles, control, limited = analyze(arguments.control_root.resolve(), arguments.limited_root.resolve())
    arguments.output.mkdir(parents=True, exist_ok=False)
    write_json(arguments.output/"transport_direction_review.json", result)
    plot(arguments.output/"figures", profiles, result)
    print(json.dumps({"output": str(arguments.output), "selected_energy_checks_pass": result["all_22_selected_profile_energy_checks_pass"],
        "review_sha256": sha256(arguments.output/"transport_direction_review.json"), "raw_npz_bytes_retained": result["raw_npz_bytes_retained"]}))
