"""Independent compact-profile EOS and inventory checks, not cycle qualification."""
import argparse
from pathlib import Path
import json

import numpy as np

from Analyze_HeatDriveECC_ConservativeTransport import require_source_provenance, assert_rendered_text_bounds
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Reference_HeatDriveECC_ConservativeTransport import Bed
from Reference_HeatDriveECC_EnthalpyTransport import EnthalpyBed, TabulatedEOS
from Run_HeatDriveECC_ConservativeTransport import write_json
from Run_HeatDriveECC_ConstrainedEnthalpy import require_sampled_clock
from Run_HeatDriveECC_EnthalpyTransport import MASS_TOL_KG, ENERGY_TOL_J


def make_bed(contract):
    eos = TabulatedEOS(contract["EOS_temperature_K"], contract["EOS_pressure_Pa"], contract["density_kg_m3"],
        contract["specific_internal_energy_J_kg"], contract["conductivity_W_mK"])
    c = contract["geometry_and_constant_control"]
    geometry = Bed(**dict(c["bed"], slope_limiter="MC"))
    return EnthalpyBed(geometry, eos, 3.66, c["Dh_m"], c["surface_area_m2"])


def profile_inventory_checks(state, temperature, pressure, bed):
    n = bed.nodes
    if (state.ndim != 2 or state.shape[1] != 3*n+2 or temperature.shape != (len(state), 2*n)
            or pressure.shape != (len(state), n) or not np.isfinite(state).all()
            or not np.isfinite(temperature).all() or not np.isfinite(pressure).all()):
        raise ValueError("Missing/misaligned finite conservative EOS profiles")
    if not np.allclose(state[0], bed.initial_state(), rtol=0, atol=1e-16):
        raise ValueError("Non-cold state cannot enter this independent trial")
    props = bed.eos.properties(temperature[:, :n], pressure)
    alias_mass = props["rho"]*bed.volume
    alias_energy = state[:, :n]*(props["u"]-bed.eos.uref)
    alias_solid = bed.geometry.solid_capacity*(temperature[:, n:]-bed.eos.Tref)
    mass_error = float(np.max(abs(state[:, :n].sum(axis=1)-state[0, :n].sum()-state[:, -2])))
    energy_error = float(np.max(abs(state[:, n:3*n].sum(axis=1)-state[:, -1])))
    mass_alias_error = float(np.max(abs(alias_mass-state[:, :n])))
    energy_alias_error = float(np.max(abs(alias_energy-state[:, n:2*n])))
    solid_alias_error = float(np.max(abs(alias_solid-state[:, 2*n:3*n])))
    return {"saved_mass_residual_kg": mass_error, "saved_energy_residual_J": energy_error,
        "EOS_mass_alias_error_kg": mass_alias_error, "EOS_energy_alias_error_J": energy_alias_error,
        "solid_energy_alias_error_J": solid_alias_error,
        "saved_pressure_deviation_Pa": float(np.max(abs(pressure-bed.eos.pref))),
        "saved_inventory_and_EOS_checks_pass": mass_error <= MASS_TOL_KG and energy_error <= ENERGY_TOL_J
            and mass_alias_error <= MASS_TOL_KG and max(energy_alias_error, solid_alias_error) <= ENERGY_TOL_J,
        "independently_reconstructed_every_internal_step": False}


def read_packet(root, filename, expected_cases):
    execution_path = root/filename
    record = json.loads(execution_path.read_text(encoding="utf-8"))
    require_source_provenance(record)
    if (record.get("collection_complete") is not True or len(record["cases"]) != expected_cases
            or record["production_state_loaded"] or record["checkpoint_saved"]):
        raise ValueError("Require a completed independent cold diagnostic packet")
    stop = .1 if record["study"] == "smoke" else 10.
    expected_times = np.array([0., .01, .02, .025, .05, .06, .075, .1] if stop == .1 else
        [0., .01, .05, .1, .25, .5, 1., 3.5, 5., 5.1, 6., 8.5, 9., 10.])
    raw, checked, keys = {}, [], []
    for row in record["cases"]:
        method_coordinate = row.get("dt_s", row.get("rtol"))
        key = row["material"], method_coordinate
        if key in keys or row["nodes"] != 21:
            raise ValueError("Duplicate or unexpected grid member")
        keys.append(key)
        path = root/row["file"]
        if (path.resolve().parent != root.resolve() or path.stat().st_size != row["bytes"]
                or sha256(path) != row["sha256"]):
            raise ValueError("Unsealed or external raw profile")
        with np.load(path, allow_pickle=False) as file:
            require_sampled_clock(file["time_s"], expected_times)
            raw[key] = {name: file[name].copy() for name in file.files}
        bed = make_bed(record["physical_contracts"][row["material"]])
        values = raw[key]
        check = profile_inventory_checks(values["conserved_diagnostic_profiles"], values["fluid_and_solid_temperature_K"], values["pressure_Pa"], bed)
        checked.append({"material": row["material"], "coordinate": method_coordinate, "file": row["file"],
            "sha256": row["sha256"], "bytes": row["bytes"], "checks": check})
    levels = ([1e-10, 1e-11] if "rtol_levels" in record else ([.001, .0005, .00025] if stop == .1 else [.001, .0005]))
    if set(keys) != {(m, level) for m in ("SMA", "SE") for level in levels}:
        raise ValueError("Incomplete diagnostic matrix")
    return record, raw, {"execution_path": str(execution_path), "execution_sha256": sha256(execution_path),
                         "saved_profile_checks": checked,
                         "all_saved_inventory_EOS_checks_pass": all(c["checks"]["saved_inventory_and_EOS_checks_pass"] for c in checked)}


def compare_profiles(first, second):
    require_sampled_clock(first["time_s"], second["time_s"])
    a, b = first["conserved_diagnostic_profiles"], second["conserved_diagnostic_profiles"]
    n = (a.shape[1]-2)//3
    if a.shape != b.shape or a.shape[1] != 3*n+2:
        raise ValueError("Different conservative coordinates")
    return {"mass_coordinates_kg": float(np.max(abs(a[:, :n]-b[:, :n]))),
        "fluid_energy_coordinates_J": float(np.max(abs(a[:, n:2*n]-b[:, n:2*n]))),
        "solid_energy_coordinates_J": float(np.max(abs(a[:, 2*n:3*n]-b[:, 2*n:3*n]))),
        "boundary_mass_integral_kg": float(np.max(abs(a[:, -2]-b[:, -2]))),
        "boundary_energy_integral_J": float(np.max(abs(a[:, -1]-b[:, -1]))),
        "fluid_and_solid_temperature_K": float(np.max(abs(first["fluid_and_solid_temperature_K"]-second["fluid_and_solid_temperature_K"]))),
        "pressure_Pa": float(np.max(abs(first["pressure_Pa"]-second["pressure_Pa"])))}


def analyze(fixed_root, adaptive_root, smoke_root, full_root, uncached_root):
    definitions = {"fixed_BS3": (fixed_root, "enthalpy_execution.json", 6),
        "adaptive_DOP853": (adaptive_root, "enthalpy_reference_execution.json", 4),
        "constrained_smoke": (smoke_root, "constrained_execution.json", 6),
        "constrained_10s": (full_root, "constrained_execution.json", 4),
        "uncached_control": (uncached_root, "constrained_execution.json", 6)}
    records, data, checks = {}, {}, {}
    for name, args in definitions.items():
        records[name], data[name], checks[name] = read_packet(*args)
    baseline = records["fixed_BS3"]["physical_contracts"]
    if any(record["physical_contracts"] != baseline for record in records.values()):
        raise ValueError("Methods changed the physical comparison contract")
    temporal, full, optimization = [], [], []
    for material in ("SMA", "SE"):
        coarse_reference = data["adaptive_DOP853"][(material, 1e-10)]
        fine_reference = data["adaptive_DOP853"][(material, 1e-11)]
        differences = [compare_profiles(data["constrained_smoke"][(material, dt)], fine_reference) for dt in (.001, .0005, .00025)]
        temporal.append({"material": material, "steps_s": [.001, .0005, .00025],
            "differences_to_finer_DOP853": differences,
            "DOP853_reference_refinement_differences": compare_profiles(coarse_reference, fine_reference),
            "DOP853_SMA_pressure_target_not_passed": material == "SMA",
            "reference_scope": "independent numerical comparison only, never a recovery/performance input",
            "blanket_second_order_claim": False})
        a, b = data["constrained_10s"][(material, .001)], data["constrained_10s"][(material, .0005)]
        difference = abs(a["fluid_and_solid_temperature_K"]-b["fluid_and_solid_temperature_K"])
        full.append({"material": material, "steps_s": [.001, .0005],
            "saved_time_max_fluid_difference_K": float(difference[:, :21].max()),
            "saved_time_max_solid_difference_K": float(difference[:, 21:].max()),
            "last_time_max_difference_K": float(difference[-1].max()),
            "whole_unsaved_trajectory_difference_verified": False,
            "full_cycle_or_spatial_convergence_claim": False})
        for dt in (.001, .0005, .00025):
            comparison = compare_profiles(data["uncached_control"][(material, dt)], data["constrained_smoke"][(material, dt)])
            old = next(r for r in records["uncached_control"]["cases"] if (r["material"], r["dt_s"]) == (material, dt))
            new = next(r for r in records["constrained_smoke"]["cases"] if (r["material"], r["dt_s"]) == (material, dt))
            optimization.append({"material": material, "dt_s": dt, "maximum_differences": comparison,
                "uncached_raw_sha256": old["sha256"], "cached_raw_sha256": new["sha256"],
                "uncached_raw_path": str(uncached_root/old["file"]), "uncached_raw_bytes": old["bytes"],
                "files_are_byte_identical_duplicates": False,
                "retention_assessment": "regenerable optimization-only intermediate; retain comparison certificate, producer and execution metadata if retiring raw"})
    result = {"schema": "heatdrive_ecc_enthalpy_direction_review_v1", "analysis_source_sha256": sha256(Path(__file__)),
        "packets": checks, "temporal_comparison": temporal, "active_10s_comparison": full,
        "optimization_comparison_certificate": optimization,
        "all_26_saved_profile_inventory_EOS_checks_pass": all(p["all_saved_inventory_EOS_checks_pass"] for p in checks.values()),
        "fixed_BS3_pressure_contract_qualified": False, "adaptive_SMA_1Pa_numerical_target_pass": False,
        "active_constrained_component_numerical_checks_pass": records["constrained_10s"]["all_numerical_invariants_pass"],
        "main_conclusion": "use simultaneous conservative EOS constraints, not integrate-then-project or blanket fixed-BS3 pressure invariance claims",
        "unresolved": ["closed-valve dwell and pressure/compliance/hydraulic closure", "SMA-SE mechanical coupling and phase power",
            "Q01 completion surfaces and probability coefficients", "90K active thermal trial is frozen-phase, not actuator validation",
            "full distributed periodicity and sensor/accessory/buffer/pump budgets", "current-model C200 strict restoration",
            "outer solve, orthogonal sensitivities, paired endpoints and independent validation"],
        "production_recovery_allowed": False, "full_coupled_qualification": False, "outer_solve_allowed": False,
        "Table4_reproduction_claim": False, "scientific_gates_modified": False,
        "no_all_major_step_replay_claim": True}
    return result, records, data


def plot(output, result, records, data):
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
    for i, material in enumerate(("SMA", "SE")):
        raw = data["constrained_10s"][(material, .0005)]
        for j, field in enumerate(("fluid", "solid")):
            ax = axes[i, j]
            for elapsed, color, style in ((1., "#3c6eab", "--"), (5., "#b23a48", ":"), (10., "#007f73", "-")):
                index = int(np.argmin(abs(raw["time_s"]-elapsed)))
                ax.plot((np.arange(21)+.5)/21, raw["fluid_and_solid_temperature_K"][index, j*21:(j+1)*21],
                        color=color, linestyle=style, label=f"{elapsed:g} s", linewidth=1.4)
            ax.set(title=f"({chr(97+2*i+j)}) {material} {field}", xlabel="Physical position x/L", ylabel="Temperature (K)")
            ax.grid(alpha=.2)
    axes[0, 0].legend(fontsize=8)
    fig.suptitle("Variable-property active sensible beds: phase change is frozen")
    save(fig, "Fig01_active_enthalpy_profiles")
    fig, axes = plt.subplots(1, 2, figsize=(8.2, 3.7), layout="constrained")
    for offset, material, color in ((-.16, "SMA", "#3c6eab"), (.16, "SE", "#007f73")):
        values = []
        for method, coordinate, field in (("fixed_BS3", .001, "max_pressure_invariant_drift_Pa_all_major_steps"),
            ("adaptive_DOP853", 1e-11, "max_pressure_drift_Pa"),
            ("constrained_smoke", .001, "max_online_pressure_constraint_residual_Pa")):
            row = next(r for r in records[method]["cases"] if r["material"] == material and r.get("dt_s", r.get("rtol")) == coordinate)
            values.append(row[field])
        axes[0].bar(np.arange(3)+offset, values, width=.3, label=material, color=color)
    axes[0].set_yscale("log")
    axes[0].set_xticks([0, 1, 2], ["BS3\n1 ms", "DOP853\nrtol 1e-11", "Constrained\n1 ms"])
    axes[0].axhline(1., color="#777777", linestyle="--", linewidth=1, label="1 Pa numerical target")
    axes[0].set(title="(a) Same 0.1 s pressure invariant", ylabel="Maximum observed pressure deviation (Pa)")
    axes[0].legend(fontsize=7, loc="upper right")
    for row, color in zip(result["temporal_comparison"], ("#3c6eab", "#007f73")):
        errors = [d["fluid_and_solid_temperature_K"] for d in row["differences_to_finer_DOP853"]]
        axes[1].loglog(np.array(row["steps_s"])*1000, errors, marker="o", color=color, label=row["material"])
    from matplotlib.ticker import NullFormatter
    axes[1].set_xticks([1., .5, .25], ["1", "0.5", "0.25"])
    axes[1].xaxis.set_minor_formatter(NullFormatter())
    axes[1].invert_xaxis()
    axes[1].set(title="(b) Constrained-step refinement, 0.1 s", xlabel="Fixed time step (ms)", ylabel="Difference to fine DOP853 (K)")
    axes[1].legend(fontsize=8)
    axes[1].grid(alpha=.2)
    fig.suptitle("Numerical component tests, not whole-cycle qualification")
    save(fig, "Fig02_enthalpy_numerical_constraints")
    write_json(output/"figure_manifest.json", {"files": files, "text_bounds_pass": True,
        "pressure_target_is_a_paper_mechanism_gate": False, "figures_are_diagnostic_not_main_performance_results": True})


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("fixed-root", "adaptive-root", "constrained-smoke-root", "constrained-full-root", "uncached-smoke-root", "output"):
        parser.add_argument("--"+name, required=True, type=Path)
    args = parser.parse_args()
    result, records, data = analyze(args.fixed_root.resolve(), args.adaptive_root.resolve(), args.constrained_smoke_root.resolve(),
        args.constrained_full_root.resolve(), args.uncached_smoke_root.resolve())
    args.output.mkdir(parents=True, exist_ok=False)
    write_json(args.output/"enthalpy_direction_review.json", result)
    plot(args.output/"figures", result, records, data)
    print(json.dumps({"output": str(args.output), "all_saved_inventory_EOS_checks_pass": result["all_26_saved_profile_inventory_EOS_checks_pass"],
        "review_sha256": sha256(args.output/"enthalpy_direction_review.json"), "production_recovery_allowed": False}))
