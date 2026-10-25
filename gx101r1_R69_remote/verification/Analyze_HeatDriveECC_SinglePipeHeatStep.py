"""Audit completed single-pipe heat steps, not full-system/reference validation."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_TLDomainInventory import density_table, DENSITY_ATOL_KG_M3


UNITS = {"T_I": "K", "p_I": "Pa", "u_I": "J/kg", "rho_I": "kg/m^3",
         "Phi_A": "W", "Phi_B": "W", "Q_H": "W", "mdot_A": "kg/s", "mdot_B": "kg/s",
         "Q_conv": "W", "Q_cond": "W", "probe_wall_T": "K", "probe_A_T": "K", "probe_B_T": "K",
         "Pr_I": "1", "Re_avg": "1"}
UNITS["observer_energy"] = "J"
DIRECT_UNITS = {"cp_I": "m^2/(K*s^2)", "mu_I": "kg/(m*s)", "k_I": "W/(K*m)"}


def text(dataset):
    return "".join(chr(int(v)) for v in dataset[...].reshape(-1))


def read_traces(file, field, step=.001, stop=.1):
    if not np.isfinite([step, stop]).all() or min(step, stop) <= 0:
        raise ValueError("Require a finite positive declared time grid")
    rows, clock = {}, None
    for ref in file[field][...].reshape(-1):
        group = file[ref]; name = text(group["name"])
        if name in rows:
            raise ValueError("Duplicate trace: " + name)
        time = np.asarray(group["time_s"]).reshape(-1)
        values = np.asarray(group["values"]).reshape(-1)
        unit = text(group["unit"])
        if name in DIRECT_UNITS:
            if unit != DIRECT_UNITS[name] or not np.isfinite(values).all():
                raise ValueError("Unknown transport property unit or nonfinite values")
        else:
            values = convert(values, unit, UNITS[name])
        if clock is None:
            clock = time
        if not np.array_equal(clock, time) or values.shape != clock.shape:
            raise ValueError("Mismatched raw scalar clocks")
        rows[name] = values
    count = int(round(stop/step)) + 1
    if (abs((count-1)*step-stop) > 1e-12 or clock is None or clock.shape != (count,)
            or not np.allclose(clock, np.arange(count)*step, rtol=0, atol=1e-12)):
        raise ValueError("Require the complete declared fixed-step fixture")
    return clock, rows


def pipe_balance(time, rows, nominal_mass):
    time = np.asarray(time)
    if not np.isfinite(nominal_mass) or nominal_mass <= 0 or np.any(np.diff(time) <= 0):
        raise ValueError("Invalid fixed-mass inventory or clock")
    for name in ("Phi_A", "Phi_B", "Q_H", "u_I", "mdot_A", "mdot_B"):
        if np.shape(rows[name]) != time.shape or not np.isfinite(rows[name]).all():
            raise ValueError("Missing native ledger trace")
    net = rows["Phi_A"] + rows["Phi_B"] + rows["Q_H"]
    steps = net[1:]*np.diff(time) - nominal_mass*np.diff(rows["u_I"])
    return {"basis": "original quasisteady pipe: M=rho(T_nominal,p_nominal)*V; U=M*u_I",
            "nominal_mass_kg": float(nominal_mass),
            "max_abs_step_residual_J": float(np.max(abs(steps))),
            "endpoint_residual_J": float(np.sum(steps)),
            "max_abs_cumulative_residual_J": float(np.max(abs(np.cumsum(steps)))),
            "max_abs_boundary_mass_sum_kgps": float(np.max(abs(rows["mdot_A"]+rows["mdot_B"]))),
            "quadrature": "native local backward Euler, actual measured intervals",
            "full_device_energy_or_pump_validation": False}


def reference_flux(row, values, nu):
    if not np.isfinite(nu) or nu <= 0 or min(row["surface_area_m2"], row["Dh_m"]) <= 0:
        raise ValueError("Invalid nominal heat-transfer geometry")
    return nu * values["k_I"] * row["surface_area_m2"] / row["Dh_m"] * (
        values["probe_wall_T"] - values["T_I"])


def analyze(root, source_root):
    path = root / "single_pipe_execution.json"
    execution = json.loads(path.read_text(encoding="utf-8-sig"))
    if (execution["collection_pass"] is not True or execution["passive_probe_equivalence_pass"] is not True
            or execution["production_model_loaded"] is not False or execution["production_state_loaded"] is not False
            or execution["checkpoint_saved"] is not False or len(execution["cases"]) != 12):
        raise ValueError("Require a completed independent fixture, not a partial/failed run")
    cfgpath = source_root / "conservative/configuration.mat"
    metapath = source_root / "conservative/inventory_metadata.json"
    if sha256(cfgpath) != execution["configuration_sha256"] or sha256(metapath) != execution["inventory_metadata_sha256"]:
        raise ValueError("Source configuration/metadata changed")
    with h5py.File(cfgpath, "r") as cfg:
        pressure = float(cfg["options/branch/network_absolute_pressure_MPa"][0, 0])*1e6
        targets = {name: float(cfg["options/branch/m_dot_" + name.lower() + "_the_kg_per_s"][0, 0])
                   for name in ("SMA", "SE")}
    combinations = set()
    results, raw = [], {}
    for row in execution["cases"]:
        name, flow, delta = row["material"], row["mass_flow_command_kgps"], row["wall_step_K"]
        key = (name, float(flow), delta)
        if name not in targets or flow not in (-targets[name], 0, targets[name]) or delta not in (-5, 5) or key in combinations:
            raise ValueError("Missing/duplicate/unknown experiment matrix member")
        combinations.add(key)
        file = root / row["file"]
        if file.parent.resolve() != root.resolve() or sha256(file) != row["sha256"]:
            raise ValueError("Changed or external raw case")
        with h5py.File(file, "r") as f:
            sealed = json.loads(text(f["record_json"]))
            if any(row[k] != value for k, value in sealed.items()):
                raise ValueError("Execution and sealed case metadata differ")
            t, n = read_traces(f, "native_traces")
            tp, v = read_traces(f, "probe_traces")
        if not np.array_equal(t, tp):
            raise ValueError("Native/probe clocks differ")
        differences = {}
        for field in n:
            error = float(np.max(abs(n[field]-v[field])))
            allowance = 1e-10*max(1., float(np.max(abs(n[field]))))
            if error > allowance:
                raise ValueError("Probe changed native output: " + field)
            differences[field] = error
        before, after = t <= .019, t >= .021
        if (np.max(abs(v["probe_wall_T"][before]-303.15)) > 1e-9
                or np.max(abs(v["probe_wall_T"][after]-(303.15+delta))) > 1e-9):
            raise ValueError("Actual wall does not witness the signed heat step")
        split = float(np.max(abs(v["Q_H"]-v["Q_conv"]-v["Q_cond"])))
        allowance = 1024*np.finfo(float).eps*max(1., float(np.max(abs(v["Q_H"]))))
        if split > allowance:
            raise ValueError("Measured heat-flow split does not close")
        props = row["fluid_settings"]["saved_inventory_parameters"]
        lookup = density_table(props)
        predicted_rho = lookup(np.column_stack((n["T_I"], n["p_I"])))
        rho_error = float(np.max(abs(predicted_rho-n["rho_I"])))
        if rho_error > DENSITY_ATOL_KG_M3:
            raise ValueError("Fluid property reconstruction changed")
        # These nominal coordinates are explicit constants/expressions in the bound fixture producer.
        nominal = float(lookup([[293.15, pressure]])[0]) * row["area_m2"] * row["length_m"]
        balance = pipe_balance(t, n, nominal)
        saved = reference_flux(row, v, row["saved_Nu"])
        q01 = reference_flux(row, v, 3.66)
        if np.any(abs(saved[after]) < 1e-9):
            raise ValueError("Cannot form a heat ratio at negligible reference flux")
        ratio = n["Q_H"][after]/saved[after]
        results.append({"file": row["file"], "sha256": row["sha256"], "material": name,
            "mass_flow_kgps": flow, "wall_step_K": delta,
            "volume_m3": row["area_m2"]*row["length_m"], "saved_Nu": row["saved_Nu"],
            "native_probe_max_differences_SI": differences, "wall_temperature_witness_pass": True,
            "Qsplit_max_abs_error_W": split, "native_density_lookup_max_abs_error_kg_m3": rho_error,
            "local_energy_ledger": balance,
            "final_sample_at_0p1s": {"wall_temperature_K": float(v["probe_wall_T"][-1]),
                "fluid_internal_temperature_K": float(n["T_I"][-1]),
                "port_A_temperature_K": float(v["probe_A_T"][-1]),
                "port_B_temperature_K": float(v["probe_B_T"][-1]),
                "Re_avg": float(v["Re_avg"][-1]), "native_total_W": float(n["Q_H"][-1]),
                "convection_W": float(v["Q_conv"][-1]), "conduction_W": float(v["Q_cond"][-1]),
                "reference_saved_Nu_on_native_T_W": float(saved[-1]),
                "reference_Q01_Nu3p66_on_native_T_W": float(q01[-1]),
                "native_over_reference_saved_Nu": float(ratio[-1])},
            "native_over_reference_saved_Nu_range_after_21ms": [float(ratio.min()), float(ratio.max())],
            "forced_reference_law_applicable_as_physical_zero_flow_gate": False if flow == 0 else None,
            "reference_sampled_on_native_trajectory_not_separately_integrated": True})
        raw[row["file"]] = (row, t, n, v, saved, q01)
    result = {"schema": "heatdrive_ecc_single_pipe_runtime_review_v1",
        "analysis_source_sha256": sha256(Path(__file__)), "execution_commit": execution["execution_commit"],
        "execution_path": str(path), "execution_sha256": sha256(path),
        "configuration_sha256": execution["configuration_sha256"],
        "inventory_metadata_sha256": execution["inventory_metadata_sha256"],
        "source_root": str(source_root), "cases": results,
        "nominal_inventory_coordinates_basis": "producer literal T_nominal=293.15K and saved configuration pressure; not a native parameter-log measurement",
        "scope": "12 isolated native/probe single-cell cases, 0-0.1s; step at 0.02s; no coupled system run",
        "passive_probe_comparison_verified": True,
        "reference_operator_equivalence": False,
        "reference_temperature_trajectory_simulated": False,
        "time_step_convergence_verified": False, "spatial_transport_verified": False,
        "coupled_performance_gap_attributed": False, "full_device_first_law_verified": False,
        "production_recovery_allowed": False, "outer_solve_allowed": False, "table4_reproduction_claim": False}
    return result, raw


def plot(raw, output):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    plt.rcParams.update({"font.family": "Arial", "font.size": 9, "axes.titlesize": 10,
                         "axes.spines.top": False, "axes.spines.right": False, "svg.fonttype": "none"})
    fig, axes = plt.subplots(2, 2, figsize=(7.6, 5.5), sharex=True, layout="constrained")
    for column, name in enumerate(("SMA", "SE")):
        for line, delta in enumerate((5, -5)):
            row, t, n, v, reference, _ = next(data for data in raw.values()
                if data[0]["material"] == name and data[0]["mass_flow_command_kgps"] > 0 and data[0]["wall_step_K"] == delta)
            ax = axes[line, column]
            for y, label, color, style in ((n["Q_H"], "Native total", "#0072B2", "-"),
                (v["Q_conv"], "Convection", "#009E73", "--"),
                (v["Q_cond"], "Conduction", "#CC3311", ":"),
                (reference, "Reference on native T", "#333333", "-.")):
                ax.plot(t*1000, y, label=label, color=color, ls=style, lw=1.2)
            ax.axvline(20, color="#AAAAAA", ls=":", lw=.7)
            ax.set(title=f"({chr(97+line*2+column)}) {name}, wall step {delta:+d} K",
                   ylabel="Heat into fluid (W)", xlim=(0, 100))
            ax.grid(axis="y", color="#DDDDDD", lw=.5)
            if line == 1:
                ax.set_xlabel("Time (ms)")
    handles, labels = axes[0, 0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="outside lower center", ncols=4, frameon=False, fontsize=8)
    fig.suptitle("Single-cell heat steps | SMA 50.8 g/s, SE 3.2 g/s\nIsolated components, not coupled performance", fontsize=11)
    fig.canvas.draw(); renderer = fig.canvas.get_renderer()
    labels_to_check = [*fig.texts, *[t for legend in fig.legends for t in legend.get_texts()]]
    for ax in axes.flat:
        labels_to_check += [ax.title, ax.xaxis.label, ax.yaxis.label]
        for axis in (ax.xaxis, ax.yaxis):
            low, high = sorted(axis.get_view_interval())
            labels_to_check += [tick.label1 for tick in axis.get_major_ticks() if low <= tick.get_loc() <= high]
    for label in labels_to_check:
        box = label.get_window_extent(renderer)
        if label.get_visible() and label.get_text() and (box.x0 < -1 or box.y0 < -1
                or box.x1 > fig.bbox.width+1 or box.y1 > fig.bbox.height+1):
            raise ValueError("Clipped figure label: " + label.get_text())
    files = []
    for extension in ("png", "svg"):
        path = output / ("Fig01_single_pipe_heat_steps." + extension)
        fig.savefig(path, dpi=260, facecolor="white")
        files.append({"path": str(path), "bytes": path.stat().st_size, "sha256": sha256(path)})
    plt.close(fig)
    return {"files": files, "text_within_canvas": True, "sample_count_per_curve": 101,
            "selection": "positive prescribed flow, both materials, both heat signs; all 12 cases retained in audit"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Never overwrite component evidence")
    result, raw = analyze(args.root.resolve(), args.source_root.resolve())
    args.output.mkdir(parents=True)
    result["figure"] = plot(raw, args.output)
    output = args.output / "single_pipe_runtime_review.json"
    output.write_text(json.dumps(result, indent=2, allow_nan=False)+"\n", encoding="utf-8")
    print(json.dumps({"output": str(output), "sha256": sha256(output), "completed_cases": len(result["cases"]),
                      "max_local_step_residual_J": max(c["local_energy_ledger"]["max_abs_step_residual_J"] for c in result["cases"]),
                      "coupled_performance_claim": False}))
