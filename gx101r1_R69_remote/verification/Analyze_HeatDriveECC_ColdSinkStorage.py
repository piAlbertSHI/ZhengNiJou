"""Transient CHEX stream/storage decomposition, not steady cooling performance.

Read retained reduced C20 and isolated-observer C1 only; no simulation/OP input.
Qstream = Qsensor + Qleak - dU_CHEX_bus - dH_CHEX_fluid.
An independent C1 port-integral check tests this identity's actual graph/signs.
It does NOT attribute the frozen C200 SCP deviation or qualify any endpoint.
"""
import argparse
import json
import math
from pathlib import Path
import subprocess

import numpy as np

from Analyze_HeatDriveECC_CaloricCycle import read_packet, reconstruct
from Analyze_HeatDriveECC_LocalBoundaryProtocol import readback
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Run_HeatDriveECC_ConservativeTransport import write_json


def exact_window(t, start, end, cycle_s):
    if (not np.isfinite([start, end, cycle_s]).all() or cycle_s <= 0 or start < 0 or end <= start
            or start/cycle_s != round(start/cycle_s) or end/cycle_s != round(end/cycle_s)):
        raise ValueError("Complete cycle-aligned window required")
    hits = [np.flatnonzero(t == value) for value in (start, end)]
    if any(len(row) != 1 for row in hits):
        raise ValueError("Missing exact window endpoint; no interpolation")
    return int(hits[0][0]), int(hits[1][0])


def passive_leak_bound(ambient, initial_pair, fluid_range, load_capacity, load_W, ua, duration):
    """Analytic interval for the passive cold-bus/load-node pair, not sample extrema.

    With positive capacities and nonnegative UA, the pair has a maximum principle
    driven by the CHEX fluid temperatures and ambient. Constant imposed load
    changes its extreme by at most |Qload|*duration/Cload. The model's caloric
    evaluator rejects fluid states outside the supplied table on every RHS call.
    """
    if (not np.isfinite([ambient, *initial_pair, *fluid_range, load_capacity, load_W, ua, duration]).all()
            or len(initial_pair) != 2 or fluid_range[0] > fluid_range[1]
            or load_capacity <= 0 or ua < 0 or duration <= 0):
        raise ValueError("Invalid passive thermal-pair contract")
    low = min(ambient, *initial_pair, fluid_range[0])+min(load_W, 0)*duration/load_capacity
    high = max(ambient, *initial_pair, fluid_range[1])+max(load_W, 0)*duration/load_capacity
    return [ua*(ambient-high)*duration, ua*(ambient-low)*duration]


def decompose(load_J, sensor_J, sensor_storage_J, bus_storage_J, fluid_storage_J, leak_box_J):
    if (not np.isfinite([load_J, sensor_J, sensor_storage_J, bus_storage_J, fluid_storage_J, *leak_box_J]).all()
            or len(leak_box_J) != 2 or leak_box_J[0] > leak_box_J[1]):
        raise ValueError("Finite ordered energy observations required")
    sensor_residual = sensor_storage_J-(load_J-sensor_J)
    if abs(sensor_residual) > 1e-8:
        raise ValueError("Stored sensor coordinate and retained load/sensor ledgers disagree")
    base = math.fsum([sensor_J, -bus_storage_J, -fluid_storage_J])
    return {"imposed_external_load_J": load_J, "sensor_to_CHEX_bus_J": sensor_J,
            "load_sensor_storage_change_J": sensor_storage_J, "CHEX_bus_storage_change_J": bus_storage_J,
            "CHEX_fluid_enthalpy_storage_change_J": fluid_storage_J, "ambient_leak_energy_interval_J": leak_box_J,
            "stream_enthalpy_gain_without_leak_J": base,
            "stream_enthalpy_gain_interval_J": [base+v for v in leak_box_J],
            "sensor_coordinate_balance_residual_J": sensor_residual,
            "combined_cold_inventory_change_J": math.fsum([sensor_storage_J, bus_storage_J, fluid_storage_J]),
            "stream_gain_is_not_imposed_load_during_cooldown": True,
            "stream_integral_inferred_from_inventory_not_independent_for_this_packet": True}


def window(model, t, states, start, end, exact_leak=None):
    cycle_s = sum(model.c["stage_durations_s"])
    i, j = exact_window(t, start, end, cycle_s)
    change = states[j]-states[i]
    ledgers = dict(zip(model.LEDGERS, change[model.slices["ledgers"]]))
    bus = change[model.slices["bus_E"]]
    fluid = math.fsum(change[model.slices["chex"]])
    if abs(ledgers["load"]-model.c["cold_load_W"]*(end-start)) > 1e-8:
        raise ValueError("Retained load integral differs from declared constant boundary")
    hx = model.components["chex"]
    if (hx["bus_index"] != 2 or hx["fluid"] != "SE" or hx["UA_W_K"] < 0
            or model.c["cold_load_UA_W_K"] < 0 or min(model.bus_capacity[2:]) <= 0):
        raise ValueError("Unsupported cold-side thermal graph; do not reuse this decomposition")
    initial = model.unpack(states[i])["bus_T"][2:]
    leak = ([exact_leak, exact_leak] if exact_leak is not None else passive_leak_bound(
        model.c["ambient_K"], initial, [model.fluids["SE"].t[0], model.fluids["SE"].t[-1]],
        model.bus_capacity[3], model.c["cold_load_W"], model.c["chex_leak_UA_W_K"], end-start))
    row = decompose(float(ledgers["load"]), float(ledgers["chex"]), float(bus[3]), float(bus[2]), float(fluid), leak)
    row.update(window_s=[start, end], duration_s=end-start, complete_cycles=int((end-start)/cycle_s),
               matches_Qian_ten_cycle_duration=(end-start == 10*cycle_s),
               periodic_or_material_qualification_claim=False, formal_Eq9_or_Eq10_reported=False)
    return row


def geometry_case(model):
    g, c = model.c["geometry"], model.c
    # Table2 printed area is kept distinct from an unrounded wire-circle area.
    table2 = {"SMA_area_m2": 14.14e-6, "SE_area_m2": 4e-6, "SMA_length_m": .45, "SE_length_m": .2,
              "SMA_solid_mass_kg": 6500*14.14e-6*.45, "SE_solid_mass_kg": 6500*4e-6*.2}
    table2["driver_to_SE_mass_ratio"] = table2["SMA_solid_mass_kg"]/table2["SE_solid_mass_kg"]
    current = {"SMA_area_m2": g["S_a_m2"], "SE_area_m2": g["S_r_m2"], "SMA_length_m": g["L_a_m"],
               "SE_length_m": g["L_r_m"], "SMA_solid_mass_kg": c["solid_mass_kg"]["SMA"],
               "SE_solid_mass_kg": c["solid_mass_kg"]["SE"]}
    current["driver_to_SE_mass_ratio"] = current["SMA_solid_mass_kg"]/current["SE_solid_mass_kg"]
    if (not np.isclose(g["S_a_m2"], 32*np.pi*(.001)**2/4, rtol=1e-12, atol=0.)
            or not np.isclose(g["S_r_m2"], 2*.0005*.017, rtol=1e-12, atol=0.)
            or not np.isclose(current["driver_to_SE_mass_ratio"], 3.2, rtol=1e-12, atol=0.)):
        raise ValueError("This case is not the declared Table4-derived prototype geometry")
    for suffix, material, solid_area, expected in (("a", "SMA", g["S_a_m2"], .75), ("r", "SE", g["S_r_m2"], .42)):
        ratio = c["fluid_components"]["bed_"+suffix]["area_m2"]/solid_area
        if not np.isclose(ratio, expected, rtol=1e-12, atol=0.):
            raise ValueError("Saved void/solid ratio does not match the explicit Qian2019 convention")
        current[material+"_void_over_solid"] = ratio
    return {"published_Table2_PDF_page": 6, "Table2_literal_geometry": table2,
            "retained_C20_Table4_derived_geometry": current,
            "same_geometry": False, "same_case_as_Q01_Fig3_to_Fig6": False,
            "Table2_flow_magnitudes_found_in_Table2_or_Fig1c": False,
            "Table4_flow_must_not_silently_fill_Table2_gap": True,
            "source_Fig1c_visual_readback": "Schematic sequence only, no numerical flow axis ticks",
            "porosity_interpretation_error_found_in_current_defaults": False}


def direct_C1_crosscheck(root):
    audit = readback(root)
    execution = root/"local_boundary_execution.json"
    r = json.loads(execution.read_text(encoding="utf-8"))
    model = reconstruct(r["network_contract"])
    with np.load(root/r["raw"]["file"], allow_pickle=False) as data:
        t, y, e = [data[n].copy() for n in ("time_s", "diagnostic_coordinates_NOT_OP", "boundary_integral_J")]
    index = {v["name"]: i for i, v in enumerate(r["control_volume_contract"]["edges"])}
    change = e[-1]-e[0]
    direct = float(change[index["chex_to_cold"]]-change[index["SE_to_chex"]])
    leak = float(change[index["cold_ambient_leak"]])
    balance = window(model, t, y, 0., 10., leak)
    error = direct-balance["stream_enthalpy_gain_interval_J"][0]
    if abs(error) > 1e-8:
        raise ValueError("C1 direct inlet/outlet enthalpy integral contradicts cold inventory decomposition")
    return {"execution": str(execution), "execution_sha256": sha256(execution), "raw_sha256": r["raw"]["sha256"],
            "direct_stream_enthalpy_integral_J": direct, "direct_leak_integral_J": leak,
            "decomposition_minus_direct_max_J": abs(error), "decomposition": balance,
            "isolated_observer_base_coordinates_bitwise_control": audit["all_saved_base_coordinates_bitwise_equal_to_control"],
            "scope": "Same-model discrete boundary-integral cross-check, not independent physical validation"}


def analyze(root, local_root, q01_pdf, output):
    if sha256(q01_pdf) != "2D0EB5F84AA515BA651638974414D426A3806FD417A1EAD96EFA36EDA08034CC":
        raise ValueError("Changed Q01 primary source")
    r, model, t, states, _ = read_packet(root)
    if r["cycles"] != 20:
        raise ValueError("This readback is scoped to the retained reduced C20, not arbitrary production results")
    cases = geometry_case(model)
    cross = direct_C1_crosscheck(local_root)
    rows = [window(model, t, states, 10.*i, 10.*(i+1)) for i in range(20)]
    windows = [window(model, t, states, 0., 100.), window(model, t, states, 100., 200.)]
    record = {"schema": "heatdrive_ecc_cold_storage_decomposition_v1", "collection_complete": True,
              "execution_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], encoding="utf-8").strip(),
              "source_sha256": {n: sha256(Path(__file__).with_name(n)) for n in (
                  Path(__file__).name, "Analyze_HeatDriveECC_CaloricCycle.py", "Analyze_HeatDriveECC_LocalBoundaryProtocol.py",
                  "Reference_HeatDriveECC_CaloricCoupling.py", "Reference_HeatDriveECC_LocalBoundaries.py",
                  "Run_HeatDriveECC_ConservativeTransport.py", "Audit_HeatDriveECC_SegmentedEvidence.py")},
              "input_dependencies": [{"path": str(p), "sha256": sha256(p)} for p in
                  (root/"caloric_cycle_execution.json", root/r["raw"]["file"], q01_pdf)],
              "physical_case_separation": cases, "C1_direct_port_crosscheck": cross,
              "complete_cycle_budgets": rows, "ten_cycle_windows": windows,
              "performance_contract": {
                  "Eq9": "Actual HHEX/CHEX outlet temperatures, common 10 complete cycles; not cold-load or bus temperatures",
                  "Eq9_computed": False, "Eq9_missing": "Exact outlet-temperature time integrals not exported; sparse samples not interpolated",
                  "Eq10_literal_computed": False,
                  "stream_quantity": "integral mdot*(h_out-h_in)dt, enthalpy form; not silently identified with a chosen cp*DeltaT",
                  "SE_active_mass_kg": model.c["solid_mass_kg"]["SE"],
                  "SCP_mass_basis": "SE active solid only, not SMA plus SE or device mass",
                  "SCP_or_COP_reported": False, "pump_work_not_evaluated_is_not_zero": True,
                  "transient_storage_cannot_be_claimed_as_steady_load": True,
                  "periodic_mechanism_or_paired_Table4_qualification": False},
              "C200_SCP_deviation_causal_attribution": False, "production_recovery_allowed": False,
              "new_scientific_gate": False, "simulation_started": False, "checkpoint_saved": False,
              "claim_boundary": "Exact retained inventory/ledger arithmetic plus analytic leak interval within the declared reduced thermal graph; not native SLX or material validation"}
    output.mkdir(parents=True, exist_ok=False)
    write_json(output/"cold_sink_storage.json", record)
    figure(rows, windows[-1], output)
    return {"output": str(output), "sha256": sha256(output/"cold_sink_storage.json"),
            "C1_direct_integral_residual_J": cross["decomposition_minus_direct_max_J"],
            "last_ten_cycle_budget": windows[-1], "formal_performance_reported": False}


def figure(rows, final, output):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    plt.rcParams.update({"font.size": 9, "axes.spines.top": False, "axes.spines.right": False})
    fig, axes = plt.subplots(1, 2, figsize=(10.5, 4), layout="constrained")
    cycles = np.arange(1, 21)
    axes[0].plot(cycles, [r["stream_enthalpy_gain_without_leak_J"] for r in rows], "o-", color="#126b59", markersize=3, label="Stream enthalpy gain")
    axes[0].plot(cycles, [r["sensor_to_CHEX_bus_J"] for r in rows], "s--", color="#a52a68", markersize=3, label="Sensor-to-bus transfer")
    axes[0].set(xlabel="Cycle", ylabel="Energy per complete cycle (J)", title="Actual stream and internal sensor transfer", xticks=[1, 5, 10, 15, 20])
    axes[0].legend(frameon=False)
    labels = ["Imposed\nload", "Load-node\ncooldown", "CHEX bus\ncooldown", "CHEX fluid\ncooldown", "Stream\ngain"]
    values = [final["imposed_external_load_J"], -final["load_sensor_storage_change_J"],
              -final["CHEX_bus_storage_change_J"], -final["CHEX_fluid_enthalpy_storage_change_J"],
              final["stream_enthalpy_gain_without_leak_J"]]
    axes[1].bar(np.arange(5), values, color=["#666666", "#8a4d85", "#4775a5", "#6e9caa", "#126b59"], width=.64)
    axes[1].scatter([0], [values[0]], color="#444444", s=12, zorder=3)
    axes[1].set(xticks=np.arange(5), xticklabels=labels, ylabel="Energy over cycles 11-20 (J)", title="Cold-side inventory contribution")
    axes[1].axhline(0., color="#777777", linewidth=.6)
    for x, y in enumerate(values):
        axes[1].annotate("%.1f" % y, (x, y), xytext=(0, 4), textcoords="offset points", ha="center", fontsize=8)
    axes[1].margins(y=.13)
    fig.suptitle("Cold-start reduced model: transient storage, not steady cooling performance", fontsize=11)
    for suffix in ("png", "svg"):
        fig.savefig(output/("cold_sink_storage_budget."+suffix), dpi=180)
    plt.close(fig)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--local-root", type=Path, required=True)
    parser.add_argument("--q01-pdf", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    a = parser.parse_args()
    print(json.dumps(analyze(a.root.resolve(), a.local_root.resolve(), a.q01_pdf.resolve(), a.output.resolve()), allow_nan=False))
