"""Read back compact coupled trials without promoting them into production.

Numerical invariants, material mechanism, periodicity and pressure/pump evidence
are distinct. Global telescoping is not an independent physical validation.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Reference_HeatDriveECC_CaloricCoupling import CaloricFluid, CaloricCycle
from Run_HeatDriveECC_ConservativeTransport import write_json


def reconstruct(contract):
    fluids = {name: CaloricFluid(row["temperature_K"], row["cp_J_kgK"], row["conductivity_W_mK"],
                                row["fixed_density_kg_m3"], row["reference_temperature_K"])
              for name, row in contract["fluid_caloric_contracts"].items()}
    return CaloricCycle(contract, fluids)


def read_packet(root):
    execution = root/"caloric_cycle_execution.json"
    r = json.loads(execution.read_text(encoding="utf-8"))
    if (r.get("collection_complete") is not True or r.get("production_state_loaded") is not False
            or r.get("checkpoint_saved") is not False or r.get("production_recovery_allowed") is not False
            or r.get("outer_solve_allowed") is not False or r.get("Table4_reproduction_claim") is not False):
        raise ValueError("Wrong diagnostic authority")
    repo = Path(__file__).resolve().parents[2]
    for name, expected in r["source_sha256"].items():
        path = Path(__file__).with_name(name)
        blob = subprocess.check_output(["git", "show", r["execution_commit"]+":"+path.relative_to(repo).as_posix()], cwd=repo)
        if hashlib.sha256(blob).hexdigest().upper() != expected:
            raise ValueError("Historical producer source mismatch: "+name)
        # The runner/integrator may legitimately differ between numerical
        # controls. Only the actual readback helpers must match this reader;
        # every historical producer still has to match its own Git blob.
        if name in {"Reference_HeatDriveECC_CaloricCoupling.py", "Reference_HeatDriveECC_ConservativeTransport.py"} and sha256(path) != expected:
            raise ValueError("Reader helper differs from execution source: "+name)
    for dependency in r["network_contract"]["input_dependencies"]:
        if sha256(Path(dependency["path"])) != dependency["sha256"]:
            raise ValueError("Input dependency changed: "+dependency["path"])
    raw = root/r["raw"]["file"]
    if raw.resolve().parent != root.resolve() or sha256(raw) != r["raw"]["sha256"]:
        raise ValueError("Raw profile path or hash mismatch")
    with np.load(raw, allow_pickle=False) as data:
        t, y, stages = (data[k].copy() for k in ("time_s", "diagnostic_coordinates_NOT_OP", "completed_stage"))
    m = reconstruct(r["network_contract"])
    if (t.ndim != 1 or y.shape != (len(t), m.size) or stages.shape != t.shape
            or not np.isfinite(y).all() or not np.isfinite(t).all() or np.any(np.diff(t) <= 0)
            or t[0] != 0 or t[-1] != 10*r["cycles"] or not np.array_equal(y[0], m.initial_state())
            or not set(stages) <= {1, 2, 3, 4}
            or r["coordinate_slices"] != {k: [v.start, v.stop] for k, v in m.slices.items()}):
        raise ValueError("Clock, dimensions, slices or cold coordinates mismatch")
    for cycle in range(r["cycles"]):
        for stage, offset in enumerate((3.5, 5., 8.5, 10.), 1):
            hits = np.flatnonzero(t == cycle*10+offset)
            if len(hits) != 1 or stages[hits[0]] != stage:
                raise ValueError("Missing exact completed-stage observation")
    p = [m.unpack(v) for v in y]
    return r, m, t, y, p


def independent_energies(model, states):
    s, c = model.slices, model.c
    rows = []
    for y in states:
        pieces = [float(v) for name in (*model.components, "solid_a", "solid_r", "buffer_H", "bus_E") for v in y[s[name]]]
        pieces += [-c["solid_mass_kg"][material]*c["materials"][material]["Delta_h_J_per_kg"]*
                   float(v)/model.n for material, phase in (("SMA", "phase_a"), ("SE", "phase_r")) for v in y[s[phase]]]
        rows.append(math.fsum(pieces))
    return np.asarray(rows)


def compare_packets(first, second):
    a, _, ta, ya, pa = read_packet(first)
    b, _, tb, yb, pb = read_packet(second)
    if (not np.array_equal(ta, tb) or a["cycles"] != b["cycles"]
            or a["network_contract"] != b["network_contract"]):
        raise ValueError("Comparison requires same physical contract and exact observation clocks")
    result = {"first": str(first), "second": str(second), "observations": len(ta),
              "clock_bitwise_equal": True, "physical_contract_equal": True}
    for name, unit in (("Ta", "K"), ("Tr", "K"), ("buffer_T", "K"), ("bus_T", "K"), ("xa", "fraction"), ("xr", "fraction")):
        result["maximum_selected_"+name+"_difference_"+unit] = max(float(np.max(abs(x[name]-y[name]))) for x, y in zip(pa, pb))
    result["maximum_selected_fluid_temperature_difference_K"] = max(
        float(np.max(abs(x["T"][key]-y["T"][key]))) for x, y in zip(pa, pb) for key in x["T"])
    result["scope"] = "selected times, not full adaptive-step or independent material validation"
    return result


def summarize(r, m, t, y, p):
    if len(t) != len(y) or len(t) != len(p) or t[0] != 0 or t[-1] != 10*r["cycles"]:
        raise ValueError("Incomplete requested cycle scope")
    energy = independent_energies(m, y)
    external = np.array([math.fsum(v[:3]) for v in y[:, m.slices["ledgers"]]])
    residual = energy-energy[0]-external
    phase = np.concatenate([y[:, m.slices[name]].ravel() for name in ("phase_a", "phase_r")])
    if np.max(abs(residual)) > 1e-8 or phase.min() < -1e-10 or phase.max() > 1+1e-10:
        raise ValueError("Saved-state numerical energy or phase-domain budget failed")
    before, loading_margins = [], []
    for cycle in range(1, r["cycles"]+1):
        hot, cold = (p[int(np.flatnonzero(t == (cycle-1)*10+offset)[0])] for offset in (3.5, 8.5))
        before.append({"cycle": cycle, "before_hot_blow_SE_xM_min": float(hot["xr"].min()),
                       "before_hot_blow_SE_xM_max": float(hot["xr"].max()),
                       "before_cold_blow_SE_xM_min": float(cold["xr"].min()),
                       "before_cold_blow_SE_xM_max": float(cold["xr"].max())})
        if cycle in {1, r["cycles"]}:
            # Coordinate envelope only: do not overwrite any observed state.
            # At full SMA A/full SE M, Eq7/8 fix the available SE stress.
            from Reference_HeatDriveECC_CaloricCoupling import compatibility, reduced_phase_rates
            observed = compatibility(hot["xa"], hot["xr"], m.c["geometry"], m.c["materials"])
            full = compatibility(np.zeros(m.n), np.ones(m.n), m.c["geometry"], m.c["materials"])
            se = m.c["materials"]["SE"]
            full_required = se["C_M_Pa_per_K"]*(hot["Tr"]-se["T_Ms_K"])
            surface = se["T_As_K"]+(se["T_Ms_K"]-se["T_As_K"])*hot["xr"]
            drives = observed["sigma_r_Pa"]-se["C_M_Pa_per_K"]*(hot["Tr"]-surface)
            rate = reduced_phase_rates(hot["Ta"], hot["Tr"], hot["xa"], hot["xr"], observed,
                                       m.c["materials"], m.c["kinetics"], 1)[1]
            j = int(np.argmin(hot["xr"]))
            loading_margins.append({"cycle": cycle, "weak_cell_zero_based": j,
                "observed_xM": float(hot["xr"][j]), "observed_Tsolid_K": float(hot["Tr"][j]),
                "observed_Tfluid_K": float(hot["T"]["bed_r"][j]),
                "observed_SE_stress_MPa": float(observed["sigma_r_Pa"])/1e6,
                "observed_reduced_phase_drive_Pa": float(drives[j]), "observed_phase_rate_per_s": float(rate[j]),
                "full_coordinate_available_SE_stress_MPa": float(full["sigma_r_Pa"])/1e6,
                "full_coordinate_required_stress_at_observed_T_MPa": float(full_required[j])/1e6,
                "full_coordinate_margin_at_observed_T_MPa": float(full["sigma_r_Pa"]-full_required[j])/1e6,
                "full_coordinate_loading_temperature_limit_K": float(se["T_Ms_K"]+full["sigma_r_Pa"]/se["C_M_Pa_per_K"]),
                "scope": "conditional reduced-law, fixed observed temperature coordinate envelope; not a global operating floor or causal isolation",
                "counterfactual_state_used_for_continuation": False})
    drift = {"qualification": "two-cycle observational comparison only; no periodic gate promotion"}
    if r["cycles"] >= 2:
        end = t[-1]
        ia, ib = np.flatnonzero((t >= end-20) & (t <= end-10)), np.flatnonzero(t >= end-10)
        if len(ia) != len(ib) or not np.allclose(t[ia]+10, t[ib], rtol=0, atol=1e-10):
            raise ValueError("Missing matched last-two-cycle observations; no interpolation allowed")
        drift["maximum_pair_clock_offset_s"] = float(np.max(abs(t[ia]+10-t[ib])))
        for name in ("Ta", "Tr", "bus_T", "buffer_T", "xa", "xr"):
            d = np.array([p[b][name]-p[a][name] for a, b in zip(ia, ib)])
            drift[name] = {"same_phase_max": float(np.max(abs(d))), "same_phase_RMS": float(np.sqrt(np.mean(d*d))),
                           "endpoint_max": float(np.max(abs(d[-1]))), "unit": "fraction" if name in ("xa", "xr") else "K"}
        for key in m.components:
            d = np.array([p[b]["T"][key]-p[a]["T"][key] for a, b in zip(ia, ib)])
            drift["fluid_"+key] = {"same_phase_max": float(np.max(abs(d))), "same_phase_RMS": float(np.sqrt(np.mean(d*d))),
                                   "endpoint_max": float(np.max(abs(d[-1]))), "unit": "K"}
    return {"observed_cycles": r["cycles"], "observed_time_s": [float(t[0]), float(t[-1])], "selected_rows": len(t),
            "independent_selected_energy_residual_max_J": float(np.max(abs(residual))),
            "independent_selected_SE_mass_residual_max_kg": float(np.max(abs(y[:, m.slices["buffer_mass_change"]].sum(axis=1)))),
            "phase_bounds_selected": [float(phase.min()), float(phase.max())],
            "before_blow_phase_observations": before, "last_two_cycle_drift": drift,
            "conditional_loading_margins": loading_margins,
            "final_bus_temperature_K": p[-1]["bus_T"].tolist(), "final_buffer_temperature_K": p[-1]["buffer_T"].tolist(),
            "last_stage_end_temperature_ranges_K": {k: [float(p[-1][k].min()), float(p[-1][k].max())] for k in ("Ta", "Tr")},
            "all_mechanism_gates_pass_claim": False, "physical_first_law_validation_claim": False,
            "production_recovery_allowed": False, "outer_solve_allowed": False, "paired_Table4_allowed": False,
            "phase_metric_applicability": "before-blow ranges are observations; no invented production completion threshold",
            "numerical_budget_scope": "1e-8 J coordinate invariant, not paper validation or full-SLX heat balance",
            "remaining_contracts": m.c["limitations"],
            "Eq9_Eq10": {"required_window_cycles": 10, "required_window_s": [float(t[-1]-100), float(t[-1])],
                "SE_active_mass_kg": m.c["solid_mass_kg"]["SE"],
                "SCP_mass_basis": "active SE solid only; not total device or fluid",
                "formal_metric_computed": False,
                "reason": "reduced prescribed-flow reference, unresolved material and pump boundaries; original outlet/sensor window not exported",
                "CHEX_bus_is_not_Eq10_stream_power": True}}


def control_volumes(m):
    rows = [{"volume": name, "stored_coordinate": name, "fluid": item["fluid"],
             "mass_basis": "fixed rho_ref * actual saved area * length", "mass_ports": "equal signed flow at both faces; zero at isolated dwell",
             "energy_ports": "shared mdot*h faces, insulated axial ends, equal-and-opposite solid/bus exchange",
             "reference_not_native_SLX_equivalence": True} for name, item in m.components.items()]
    rows.extend([
        {"volume": "SMA/SE solids", "mass_ports": "none", "energy_ports": "axial conduction, conjugate heat, +m*L*dxM and opposite common-force mechanical powers",
         "stored_coordinate": "sensible E and declared chemical -m*L*xM", "qualification": "reduced material law only"},
        {"volume": "water return / hot and cold glycol chambers", "mass_ports": "water closed; glycol +/- imposed piston flow",
         "energy_ports": "shared mdot*h fluxes", "stored_coordinate": "H and two persistent mass changes", "qualification": "pressure/volume relation unresolved"},
        {"volume": "SHEX/HHEX/CHEX thermal buses and cold load", "mass_ports": "none", "energy_ports": "source, ambient, channels and CHEX-load exchange",
         "stored_coordinate": "four finite E=C*(T-303.15)", "qualification": "saved engineering capacities"},
        {"volume": "CHEX boundary sensor", "mass_ports": "none", "energy_ports": "ledger chex = integral UA*(Tload-Tchex)",
         "stored_coordinate": "none", "qualification": "not automatically equal to Eq10 glycol stream power in transient storage"},
        {"volume": "connecting pipe walls/manifolds", "qualification": "allocation unresolved; not silently omitted from whole-device claim"},
        {"volume": "SMA and SE pump work", "qualification": "not evaluated, NOT zero", "mass_ports": "prescribed flow is not hydraulic feasibility", "energy_ports": "no injected pump work in this reference"}])
    return rows


def figures(output, m, t, y, p, summary):
    plt.rcParams.update({"font.size": 9, "font.family": "DejaVu Sans", "axes.spines.top": False,
                         "axes.spines.right": False, "savefig.dpi": 180})
    manifest = []
    def save(fig, stem, scope):
        fig.canvas.draw()
        files = []
        for extension in ("png", "svg"):
            path = output/(stem+"."+extension)
            fig.savefig(path)
            files.append({"file": path.name, "sha256": sha256(path), "bytes": path.stat().st_size})
        plt.close(fig)
        manifest.append({"figure": stem, "scope": scope, "files": files})
    selected = np.flatnonzero(t >= t[-1]-10)
    clock = t[selected]-(t[-1]-10)
    z = (np.arange(m.n)+.5)/m.n
    fig, axes = plt.subplots(2, 2, figsize=(9.2, 6.5), layout="constrained")
    for col, (material, field, phase) in enumerate((("SMA", "Ta", "xa"), ("SE", "Tr", "xr"))):
        for row, key in enumerate((field, phase)):
            values = np.array([p[i][key] for i in selected]).T
            kwargs = {} if row == 0 else {"vmin": 0., "vmax": 1.}
            image = axes[row, col].pcolormesh(clock, z, values, shading="nearest", cmap="viridis" if row == 0 else "cividis", rasterized=True, **kwargs)
            fig.colorbar(image, ax=axes[row, col], label="Temperature (K)" if row == 0 else "Martensite fraction")
            axes[row, col].set(xlabel="Cycle time (s)", ylabel="Fixed axial coordinate x/L",
                               title=material+(" solid temperature" if row == 0 else " phase"), xlim=(0, 10), ylim=(0, 1))
            for event in (3.5, 5., 8.5):
                axes[row, col].axvline(event, color="white", linewidth=.65, linestyle="--")
    fig.suptitle("Cycle %d: reduced-law thermal diagnostic, prescribed flows" % summary["observed_cycles"], fontsize=11)
    save(fig, "final_cycle_temperature_phase", "not material validation or Table4 endpoints")
    before = summary["before_blow_phase_observations"]
    cycles = np.array([r["cycle"] for r in before])
    endpoints = [p[int(np.flatnonzero(t == cycle*10)[0])] for cycle in cycles]
    fig, axes = plt.subplots(2, 2, figsize=(9.2, 6.2), layout="constrained")
    for index, key in ((0, "before_hot_blow_SE_xM"), (1, "before_cold_blow_SE_xM")):
        ax = axes[0, index]
        lo, hi = np.array([r[key+"_min"] for r in before]), np.array([r[key+"_max"] for r in before])
        ax.fill_between(cycles, lo, hi, color="#397b99", alpha=.2)
        ax.plot(cycles, lo, "o-", markersize=3, color="#17627b", label="Axial minimum")
        ax.plot(cycles, hi, "s--", markersize=3, color="#a94442", label="Axial maximum")
        ax.set(xlabel="Completed cycle", ylabel="SE martensite fraction",
               title="Before hot blow (3.5 s)" if index == 0 else "Before cold blow (8.5 s)")
        if index == 0:
            ax.set_ylim(-.03, 1.03)
        else:
            upper = float(hi.max())*1.15
            ax.set_ylim(-.03*upper, upper)
            ax.ticklabel_format(axis="y", style="sci", scilimits=(0, 0))
        ax.legend(frameon=False, fontsize=8)
    axes[1, 0].plot(cycles, [r["bus_T"][2] for r in endpoints], "o-", label="CHEX bus", markersize=3)
    axes[1, 0].plot(cycles, [r["bus_T"][3] for r in endpoints], "s-", label="Cold load", markersize=3)
    axes[1, 0].set(xlabel="Completed cycle", ylabel="Endpoint temperature (K)", title="Finite cold inventories")
    axes[1, 0].legend(frameon=False)
    energy = independent_energies(m, y)
    residual = energy-energy[0]-y[:, m.slices["ledgers"]][:, :3].sum(axis=1)
    stage_times = np.concatenate([10*i+np.array([3.5, 5., 8.5, 10.]) for i in range(summary["observed_cycles"])])
    stage_rows = np.array([int(np.flatnonzero(t == v)[0]) for v in stage_times])
    axes[1, 1].plot(t[stage_rows], residual[stage_rows], "o-", markersize=2, linewidth=.8, color="#555555")
    axes[1, 1].set(xlabel="Elapsed time (s)", ylabel="Energy coordinate residual (J)", title="Stage-end numerical invariant")
    axes[1, 1].ticklabel_format(axis="y", style="sci", scilimits=(0, 0))
    save(fig, "cycle_phase_and_inventory", "before-blow observations and inventory trend, no new production gate")
    return manifest


def run(packet, output, comparisons):
    output.mkdir(parents=True, exist_ok=False)
    r, m, t, y, p = read_packet(packet)
    result = summarize(r, m, t, y, p)
    result.update(schema="heatdrive_ecc_caloric_cycle_readback_v1", execution_path=str(packet/"caloric_cycle_execution.json"),
                  execution_sha256=sha256(packet/"caloric_cycle_execution.json"), analysis_source_sha256=sha256(Path(__file__)),
                  producer_commit=r["execution_commit"], control_volumes=control_volumes(m))
    result["comparisons"] = [compare_packets(Path(a), Path(b)) for a, b in comparisons]
    result["figures"] = figures(output, m, t, y, p, result)
    write_json(output/"caloric_cycle_review.json", result)
    print(json.dumps({"output": str(output), "review_sha256": sha256(output/"caloric_cycle_review.json"),
                      "cycles": result["observed_cycles"], "energy_residual_J": result["independent_selected_energy_residual_max_J"],
                      "last_before_blow": result["before_blow_phase_observations"][-1],
                      "outer_solve_allowed": False}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packet", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--compare", nargs=2, action="append", default=[])
    args = parser.parse_args()
    run(args.packet.resolve(), args.output.resolve(), args.compare)
