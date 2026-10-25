"""Recover only durable stage summaries from a known post-simulation I/O failure.

Full physical profiles were not exported and cannot be invented or restored.
This record supports a limited endpoint comparison, not full-trajectory audit,
production recovery, periodic qualification or Table4 performance.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

import numpy as np

from Audit_HeatDriveECC_SMAFlowCoordinates import route_inventory
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Run_HeatDriveECC_ConservativeTransport import write_json


def stage_comparisons(record):
    if (record.get("collection_complete") is not False or record.get("completed_arms") != 2
            or "FileExistsError" not in record.get("error_traceback", "")
            or "completed_arm_evidence.json" not in record.get("error_traceback", "")):
        raise ValueError("Not the diagnosed two-arm post-simulation publication failure")
    cases = {r["arm"]: r for r in record["cases"]}
    if set(cases) != {"counter", "co"}:
        raise ValueError("Missing paired completed calculations")
    for case in cases.values():
        if case["cycles"] != 2 or case["completed_time_s"] != 20.:
            raise ValueError("Incomplete physical calculation; no paired summary")
    rows = []
    for cycle in (1, 2):
        a, b = (next(r for r in cases[name]["cycle_observations"] if r["cycle"] == cycle) for name in ("counter", "co"))
        for stage, end in enumerate((3.5, 5., 8.5, 10.), 1):
            x, y = (r["stage_ends"][stage-1] for r in (a, b))
            if x["time_s"] != y["time_s"] or x["time_s"] != (cycle-1)*10+end:
                raise ValueError("Paired stage summary clocks differ")
            fields = ("SMA_T_range_K", "SE_T_range_K", "SMA_xM_range", "SE_xM_range")
            rows.append({"cycle": cycle, "stage": stage, "time_s": x["time_s"],
                         "counter": {k: x[k] for k in fields}, "co": {k: y[k] for k in fields},
                         "range_endpoint_differences_co_minus_counter": {k: [j-i for i, j in zip(x[k], y[k])] for k in fields},
                         "spatial_pointwise_or_time_maximum_difference_available": False})
    return rows


def analyze(root, output):
    failed = root/"FAILED_DO_NOT_RESUME.json"
    record = json.loads(failed.read_text(encoding="utf-8"))
    for name, expected in record["source_sha256"].items():
        data = subprocess.check_output(["git", "show", record["execution_commit"]+":gx101r1_R69_remote/verification/"+name])
        if hashlib.sha256(data).hexdigest().upper() != expected:
            raise ValueError("Historical failed-run producer hash mismatch")
    if (root/"paired_direction_profiles.npz").exists():
        raise ValueError("Unexpected profile artifact; reassess evidence rather than classify it missing")
    rows = stage_comparisons(record)
    output.mkdir(parents=True, exist_ok=False)
    result = {"schema": "heatdrive_ecc_direction_retained_stage_summary_v1",
              "reader_sha256": sha256(Path(__file__)), "producer_commit": record["execution_commit"],
              "source_failure": str(failed), "source_failure_sha256": sha256(failed),
              "process_exit_code": 1, "physical_arms_reported_complete": 2, "wall_seconds": record["wall_seconds"],
              "failure_class": "second exclusive summary filename collision, after both numerical arms finished",
              "all_saved_profile_arrays_available": False, "original_collection_complete": False,
              "whole_trajectory_readback_possible": False, "first_heat_half_runtime_array_check_completed": False,
              "numerical_local_residuals_are_in_memory_reports_not_recomputed_from_raw": True,
              "reported_local_energy_max_J": {c["arm"]: c["maximum_selected_local_energy_residual_J"] for c in record["cases"]},
              "reported_local_mass_max_kg": {c["arm"]: c["maximum_selected_local_mass_residual_kg"] for c in record["cases"]},
              "stage_comparisons": rows,
              "cycle2_temperature_endpoint_drifts_K": {c["arm"]: c["cycle_observations"][-1]["endpoint_temperature_drift_K"] for c in record["cases"]},
              "co_directed_topology_qualified": False, "SMA_direction_alone_fixes_this_reduced_loading_observation": False,
              "C200_SCP_deviation_causal_attribution": False, "new_scientific_gate": False,
              "production_recovery_or_twenty_cycle_seed_allowed": False,
              "claim_boundary": "Stored stage-range endpoints only; no reconstructed profiles, extrema-between-stages or physical validation"}
    write_json(output/"retained_stage_comparison.json", result)
    figure(rows, output)
    hot = [r for r in rows if r["stage"] == 1]
    return {"output": str(output), "sha256": sha256(output/"retained_stage_comparison.json"),
            "before_hot_blow": [{"cycle": r["cycle"], "counter_min_xM": r["counter"]["SE_xM_range"][0],
                                 "co_min_xM": r["co"]["SE_xM_range"][0]} for r in hot],
            "original_run_collection_complete": False, "production_recovery_allowed": False}


def figure(rows, output):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    hot = [r for r in rows if r["stage"] == 1]
    cycles = [r["cycle"] for r in hot]
    fig, axes = plt.subplots(1, 2, figsize=(8.8, 3.5), layout="constrained")
    for arm, style, color in (("counter", "o", "#666666"), ("co", "x", "#126b59")):
        axes[0].plot(cycles, [r[arm]["SE_xM_range"][0] for r in hot], style, color=color, label=arm+"-directed")
    axes[0].set(xlabel="Cold cycle", ylabel="Minimum SE martensite fraction", ylim=(0., 1.02), xticks=cycles,
                title="Before hot blow")
    axes[0].legend(frameon=False, fontsize=8)
    delta = [r["range_endpoint_differences_co_minus_counter"]["SE_xM_range"][0] for r in hot]
    axes[1].bar(cycles, delta, color="#126b59", width=.35)
    axes[1].axhline(0., color="#777777", linewidth=.6)
    axes[1].set(xlabel="Cold cycle", ylabel="Co minus counter: minimum SE fraction", xticks=cycles,
                ylim=(-1e-6, 1e-6), title="Recorded endpoint difference")
    for ax in axes:
        ax.spines[["top", "right"]].set_visible(False)
    fig.suptitle("Retained stage summaries after publication failure; full profiles unavailable", fontsize=10)
    fig.savefig(output/"retained_stage_summary.png", dpi=180)
    plt.close(fig)


def analyze_inventory(root, output):
    failed = root/"FAILED_DO_NOT_RESUME.json"
    r = json.loads(failed.read_text(encoding="utf-8"))
    stage_comparisons(r)  # Retained scope/terminal-state contract, not trajectory recovery.
    c = r["network_contract"]
    flow = json.loads((root/"native_SMA_flow_coordinates.json").read_text(encoding="utf-8"))
    native = Path(next(p["path"] for p in flow["inputs"] if p["path"].endswith("observations.mat"))).parent
    metadata = native/"inventory_metadata.json"
    expected = next(p["sha256"] for p in c["input_dependencies"] if Path(p["path"]).resolve() == metadata.resolve())
    if sha256(metadata) != expected:
        raise ValueError("Inventory metadata not bound to the same parameter contract")
    fluid = c["fluid_caloric_contracts"]["SMA"]
    cp = float(np.interp(fluid["reference_temperature_K"], fluid["temperature_K"], fluid["cp_J_kgK"]))
    bed = c["fluid_components"]["bed_a"]
    result = route_inventory(json.loads(metadata.read_text(encoding="utf-8")), bed["area_m2"]*bed["length_m"],
        fluid["fixed_density_kg_m3"], cp, c["solid_mass_kg"]["SMA"]*c["materials"]["SMA"]["cp_J_per_kgK"])
    result.update(schema="heatdrive_ecc_SMA_route_inventory_comparison_v1", reference_temperature_K=fluid["reference_temperature_K"],
                  reader_sha256=sha256(Path(__file__)), inventory_reader_sha256=sha256(Path(__file__).with_name("Audit_HeatDriveECC_SMAFlowCoordinates.py")),
                  input_dependencies=[{"path": str(p), "sha256": sha256(p)} for p in (failed, metadata)],
                  C200_inventory_inspected=False, C200_SCP_causal_attribution=False, production_recovery_allowed=False)
    output.mkdir(parents=True, exist_ok=True)
    write_json(output/"SMA_route_inventory.json", result)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--inventory-only", action="store_true")
    a = parser.parse_args()
    operation = analyze_inventory if a.inventory_only else analyze
    print(json.dumps(operation(a.root.resolve(), a.output.resolve()), allow_nan=False))
