"""Falsify schedule-dependent material rates using sealed coupled observations.

Only changes the algebraic evaluation label at identical observed coordinates;
never feeds counterfactual states into an integration or recovery chain.
Separately reads an actual same-parameter cold two-way structural-control run.
"""
import argparse
import copy
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from Analyze_HeatDriveECC_CaloricCycle import read_packet, independent_energies
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Reference_HeatDriveECC_CaloricCoupling import compatibility, reduced_phase_rates
from Reference_HeatDriveECC_TwoWayPhase import shared_surface_rates, shared_surface_coefficients
from Run_HeatDriveECC_ConservativeTransport import write_json


def check_ablation_contract(old, new):
    a, b = copy.deepcopy(old), copy.deepcopy(new)
    if b.pop("phase_operator", None) != "stage_free_shared_surface":
        raise ValueError("Expected the named structural ablation")
    extra = "two-way shared-surface structural ablation, NOT identified MAS/polycrystal material law"
    if not b["limitations"] or b["limitations"][-1] != extra:
        raise ValueError("Missing structural-control limitation")
    b["limitations"] = b["limitations"][:-1]
    if a != b:
        raise ValueError("Another physical parameter or boundary changed")


def material_fluxes(p, m):
    mechanical = compatibility(p["xa"], p["xr"], m.c["geometry"], m.c["materials"])
    rows = {}
    c = m.c["kinetics"]
    for material, tf, phase, stress, width, plus, minus in (
        ("SMA", "Ta", "xa", "sigma_a_Pa", "drive_width_a_Pa", "rate_a_to_M_1_per_s", "rate_a_to_A_1_per_s"),
        ("SE", "Tr", "xr", "sigma_r_Pa", "drive_width_r_Pa", "rate_r_load_1_per_s", "rate_r_stage3_unload_1_per_s")):
        forward, reverse = shared_surface_coefficients(p[tf], p[phase], mechanical[stress], m.c["materials"][material],
                                                       c[width], c[plus], c[minus])
        rows[material] = {"forward_flux": forward*(1-p[phase]), "reverse_flux": reverse*p[phase]}
    return rows, mechanical


def scheduled_structure(r, m, t, p):
    statistics = {key: {"max_same_state_hot_cold_rate_difference_per_s": 0.,
                        "max_suppressed_opposite_flux_per_s": 0., "max_difference_witness": None} for key in ("SMA", "SE")}
    for clock, state in zip(t, p):
        rows, mechanical = material_fluxes(state, m)
        hot = reduced_phase_rates(state["Ta"], state["Tr"], state["xa"], state["xr"], mechanical,
                                  m.c["materials"], m.c["kinetics"], 1)
        cold = reduced_phase_rates(state["Ta"], state["Tr"], state["xa"], state["xr"], mechanical,
                                   m.c["materials"], m.c["kinetics"], 3)
        stage = 1+int(np.searchsorted([3.5, 5., 8.5], float(clock % 10), side="left"))
        # Exact t=10k observations are left limits of stage4, except t=0.
        if clock > 0 and clock % 10 == 0:
            stage = 4
        for index, material in enumerate(("SMA", "SE")):
            difference = abs(hot[index]-cold[index])
            node = int(np.argmax(difference))
            stats = statistics[material]
            if float(difference[node]) > stats["max_same_state_hot_cold_rate_difference_per_s"]:
                stats["max_same_state_hot_cold_rate_difference_per_s"] = float(difference[node])
                phase, temp, stress = ("xa", "Ta", "sigma_a_Pa") if material == "SMA" else ("xr", "Tr", "sigma_r_Pa")
                stats["max_difference_witness"] = {
                    "time_s": float(clock), "node_zero_based": node, "phase": float(state[phase][node]),
                    "temperature_K": float(state[temp][node]), "stress_MPa": float(mechanical[stress])/1e6,
                    "scheduled_hot_rate_per_s": float(hot[index][node]), "scheduled_cold_rate_per_s": float(cold[index][node]),
                    "two_way_net_rate_per_s": float(rows[material]["forward_flux"][node]-rows[material]["reverse_flux"][node]),
                    "forward_flux_per_s": float(rows[material]["forward_flux"][node]),
                    "reverse_flux_per_s": float(rows[material]["reverse_flux"][node])}
            forward_suppressed = (material == "SMA" and stage in (1, 2)) or (material == "SE" and stage in (3, 4))
            suppressed = rows[material]["forward_flux" if forward_suppressed else "reverse_flux"]
            stats["max_suppressed_opposite_flux_per_s"] = max(stats["max_suppressed_opposite_flux_per_s"], float(suppressed.max()))
    return {"scope": "algebra at identical saved coordinates; not an alternative trajectory, time fraction or new gate",
            "selected_observations": len(t), "materials": statistics,
            "both_fluxes_positive_alone_is_not_a_thermodynamic_failure": True,
            "finding": "explicit stage argument changes the material rate even when T, stress and phase are unchanged"}


def compare_cold(old_root, new_root):
    a, ma, ta, ya, pa = read_packet(old_root)
    b, mb, tb, yb, pb = read_packet(new_root)
    check_ablation_contract(a["network_contract"], b["network_contract"])
    if a["cycles"] != 1 or b["cycles"] != 1 or not np.array_equal(ta, tb):
        raise ValueError("Require complete identical-clock C1 cold controls")
    if b["source_sha256"]["Reference_HeatDriveECC_TwoWayPhase.py"] != sha256(Path(__file__).with_name("Reference_HeatDriveECC_TwoWayPhase.py")):
        raise ValueError("Two-way helper changed since the control executed")
    residuals = []
    for m, values in ((ma, ya), (mb, yb)):
        energy = independent_energies(m, values)
        residual = float(np.max(abs(energy-energy[0]-values[:, m.slices["ledgers"]][:, :3].sum(axis=1))))
        if residual > 1e-8:
            raise ValueError("Saved numerical invariant failed")
        residuals.append(residual)
    report = {"only_phase_operator_and_its_declared_limitation_changed": True,
              "same_observation_clocks": True, "all_initial_coordinates_bitwise_equal": bool(np.array_equal(ya[0], yb[0])),
              "old_execution_sha256": sha256(old_root/"caloric_cycle_execution.json"),
              "new_execution_sha256": sha256(new_root/"caloric_cycle_execution.json"),
              "saved_energy_residuals_J": residuals}
    for name in ("Ta", "Tr", "xa", "xr", "buffer_T", "bus_T"):
        report["maximum_selected_"+name+"_difference"] = max(float(np.max(abs(x[name]-y[name]))) for x, y in zip(pa, pb))
    report["units"] = "temperature differences K, xa/xr differences fraction; no mixed-unit error metric"
    i = int(np.flatnonzero(ta == 3.5)[0])
    report["before_hot_blow"] = [{"operator": name, "SE_xM_range": [float(profiles[i]["xr"].min()), float(profiles[i]["xr"].max())]}
                                  for name, profiles in (("scheduled", pa), ("two_way_shared_surface", pb))]
    report.update(Qian_MAS_material_identified=False, production_seed_allowed=False,
                  operator_replacement_alone_solves_before_blow_completion=False,
                  causal_scope="one operator ablation in the reduced thermal reference only; not attribution of the native SCP gap")
    return report, ta, pa, pb


def run(scheduled_c20, cold_control, two_way_control, output):
    output.mkdir(parents=True, exist_ok=False)
    r, m, t, _, p = read_packet(scheduled_c20)
    comparison, clock, a, b = compare_cold(cold_control, two_way_control)
    report = {"schema": "heatdrive_ecc_phase_operator_structure_v1", "analysis_sha256": sha256(Path(__file__)),
        "scheduled_C20_path": str(scheduled_c20), "scheduled_C20_execution_sha256": sha256(scheduled_c20/"caloric_cycle_execution.json"),
        "same_state_analysis": scheduled_structure(r, m, t, p), "cold_operator_ablation": comparison,
        "claims": {"material_stage_independence_required_by_Qian_equation_structure": True,
                   "shared_surface_ablation_is_published_MAS": False, "MAS_kernel_numerical_tests_are_material_validation": False,
                   "production_or_C200_modified": False, "outer_solve_allowed": False}}
    plt.rcParams.update({"font.size": 9, "axes.spines.top": False, "axes.spines.right": False, "savefig.dpi": 180})
    fig, axes = plt.subplots(2, 2, figsize=(9.3, 6.4), layout="constrained")
    for row, (material, key) in enumerate((("SMA", "xa"), ("SE", "xr"))):
        for profiles, style, color, label in ((a, "-", "#17627b", "Stage-selected"), (b, "--", "#a94442", "Two-way control")):
            phases = np.array([v[key] for v in profiles])
            axes[row, 0].plot(clock, phases.min(axis=1), style, color=color, label=label+" range")
            axes[row, 0].plot(clock, phases.max(axis=1), style, color=color, linewidth=.7)
            axes[row, 0].fill_between(clock, phases.min(axis=1), phases.max(axis=1), color=color, alpha=.10)
        axes[row, 0].set(xlabel="Time (s)", ylabel=material+" martensite fraction", ylim=(-.03, 1.03), title="C1 axial minimum/maximum")
        axes[row, 0].legend(frameon=False, fontsize=8)
        w = report["same_state_analysis"]["materials"][material]["max_difference_witness"]
        axes[row, 1].bar(["Hot label", "Cold label", "Two-way net"],
                        [w["scheduled_hot_rate_per_s"], w["scheduled_cold_rate_per_s"], w["two_way_net_rate_per_s"]],
                        color=["#17627b", "#a94442", "#555555"])
        axes[row, 1].axhline(0, color="black", linewidth=.6)
        axes[row, 1].set(ylabel=material+" phase rate (1/s)", title="C20 same-state witness, t=%.2f s" % w["time_s"])
    for ax in axes[:, 0]:
        for event in (3.5, 5., 8.5):
            ax.axvline(event, color="#aaaaaa", linewidth=.6, linestyle=":")
    fig.suptitle("Phase-operator structure control, not an identified Qian material model", fontsize=11)
    fig.canvas.draw()
    report["figure_files"] = []
    for extension in ("png", "svg"):
        file = output/("phase_operator_control."+extension)
        fig.savefig(file)
        report["figure_files"].append({"file": file.name, "sha256": sha256(file), "bytes": file.stat().st_size})
    plt.close(fig)
    write_json(output/"phase_operator_review.json", report)
    print(json.dumps({"output": str(output), "review_sha256": sha256(output/"phase_operator_review.json"),
                      "cold_temperature_difference_K": comparison["maximum_selected_Tr_difference"],
                      "cold_phase_difference": comparison["maximum_selected_xr_difference"], "outer_solve_allowed": False}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scheduled-c20", type=Path, required=True)
    parser.add_argument("--cold-control", type=Path, required=True)
    parser.add_argument("--two-way-control", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    run(args.scheduled_c20.resolve(), args.cold_control.resolve(), args.two_way_control.resolve(), args.output.resolve())
