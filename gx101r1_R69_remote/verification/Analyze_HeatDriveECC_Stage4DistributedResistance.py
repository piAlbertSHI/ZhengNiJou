"""Compare observed bed resistance with endpoint feedforward, not causal tuning.

Target-flow pressure inferred from native loss is a frozen-coefficient local
diagnostic, not an open-loop intervention or an authorized controller command.
"""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Analyze_HeatDriveECC_Stage4FeedforwardCandidates import controller_mu, TABLE_T_K, TABLE_RHO
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def distributed_pressure(temperature, density, flow, lengths, area, diameter):
    temperature, density, flow, lengths = map(np.asarray, (temperature, density, flow, lengths))
    if (temperature.ndim != 2 or temperature.shape != density.shape
            or temperature.shape != flow.shape or lengths.shape != (temperature.shape[0],)
            or not all(np.isfinite(x).all() for x in (temperature, density, flow, lengths))
            or np.any(density <= 0) or np.any(lengths <= 0) or area <= 0 or diameter <= 0):
        raise ValueError("Invalid distributed hydraulic coordinates")
    # Same f=64/Re laminar reference used by EighthRound_Defaults.
    return np.sum(32 * lengths[:, None] * controller_mu(temperature) * flow
                  / (density * area * diameter ** 2), axis=0) / 1e6


def decode(dataset):
    return "".join(chr(int(x)) for x in dataset[:].reshape(-1))


def series(group, name, time):
    row = group[name]
    grid = row["time_s"][:].reshape(-1)
    values = row["values"][:].reshape(-1)
    if grid.size != values.size or not np.isfinite(values).all() or np.any(np.diff(grid) < 0):
        raise ValueError(f"Invalid diagnostic signal: {name}")
    if time[0] < grid[0] or time[-1] > grid[-1]:
        raise ValueError("Do not extrapolate diagnostic signals")
    return np.interp(time, grid, values)


def analyze_arm(root, arm, start, stop):
    folder = root / arm
    metadata = json.loads((folder / "inventory_metadata.json").read_text(encoding="utf-8-sig"))
    blocks = sorted((b for b in metadata["storage_blocks"] if "/SE/HoldPipe_" in b["block_path"]),
                    key=lambda b: b["block_path"])
    if len(blocks) != 21 or any(not b["block_path"].endswith(f"HoldPipe_{i:03d}")
                               for i, b in enumerate(blocks, 1)):
        raise ValueError("Require all 21 native SE bed segments")
    lengths = np.array([b["mask_parameters"]["length"]["value"] for b in blocks])
    areas = np.array([b["mask_parameters"]["area"]["value"] for b in blocks])
    if (not np.allclose(areas, areas[0], rtol=0, atol=1e-15)
            or any(b["model_modes"]["inertia"] != "false" for b in blocks)
            or any(b["mask_parameters"]["length"]["unit"] != "m"
                   or b["mask_parameters"]["area"]["unit"] != "m^2" for b in blocks)):
        raise ValueError("Require common-area, non-inertial SI bed geometry")
    with h5py.File(folder / "observations.mat", "r") as f, \
            h5py.File(folder / "configuration.mat", "r") as config:
        scalar = lambda name: float(config["options/branch/" + name][0, 0])
        target = scalar("m_dot_se_chex_kg_per_s")
        diameter = scalar("se_pipe_hydraulic_diameter_m")
        reference_temperature = 303.15
        runtime_reference_drop = float(distributed_pressure(
            np.full((21, 1), reference_temperature),
            np.full((21, 1), np.interp(reference_temperature, TABLE_T_K, TABLE_RHO)),
            np.full((21, 1), target), lengths, areas[0], diameter)[0])
        legacy_reference_drop = scalar("se_bed_dp_MPa")
        lookup = {}
        for ref in f["native"][:].reshape(-1):
            row = f[ref]
            path = decode(row["block_path"])
            if path in {b["block_path"] for b in blocks}:
                key = (path, decode(row["state_name"]))
                if key in lookup:
                    raise ValueError("Duplicate native bed coordinate")
                lookup[key] = row
        template = lookup[(blocks[0]["block_path"], "T_I")]["time_s"][:].reshape(-1)
        mask = (template >= start) & (template <= stop)
        time = template[mask]
        if time.size < 20 or np.any(np.diff(time) <= 0):
            raise ValueError("Require resolved native hydraulic window")
        def stack(name, unit):
            result = []
            for block in blocks:
                row = lookup[(block["block_path"], name)]
                if decode(row["unit"]) != unit or not np.array_equal(row["time_s"][:].reshape(-1), template):
                    raise ValueError(f"Incompatible native coordinate: {name}")
                result.append(row["values"][:].reshape(-1)[mask])
            data = np.asarray(result)
            if not np.isfinite(data).all():
                raise ValueError("Nonfinite native bed coordinate")
            return data
        temperature, density, flow = stack("T_I", "K"), stack("rho_I", "kg/m^3"), stack("mdot_A", "kg/s")
        native_drop = np.sum(stack("pressure_loss_A", "MPa") - stack("pressure_loss_B", "MPa"), axis=0)
        if np.any(flow <= 0) or np.any(native_drop <= 0):
            raise ValueError("Stage4 must have positive oriented flow/loss in this diagnostic")
        predicted = distributed_pressure(temperature, density, flow, lengths, areas[0], diameter)
        frozen_target_drop = np.sum((stack("pressure_loss_A", "MPa")
                                     - stack("pressure_loss_B", "MPa")) * target / flow, axis=0)
        probes = f["stage4_controller_probe_signals"]
        ff = np.abs(series(probes, "stage4_dynamic_feedforward", time))
        command = np.abs(series(probes, "stage4_pressure_command", time))
        measured = series(f["signals"], "mass_flow_v4_hot_inlet_kgps", time)
        mu_end = series(probes, "stage4_blended_viscosity", time)
        mu_distributed = np.average(controller_mu(temperature), axis=0, weights=lengths)
        mismatch = ff / frozen_target_drop - 1
        activity = series(probes, "stage4_feedforward_activity", time)
        ratio = series(probes, "stage4_feedforward_ratio_sum", time)
        bias = series(probes, "stage4_pressure_bias_command", time)
        result = {
            "arm": arm, "window_s": [float(time[0]), float(time[-1])], "native_samples": int(time.size),
            "segment_count": 21, "bed_length_m": float(lengths.sum()), "target_kg_s": target,
            "reference_temperature_K": reference_temperature,
            "legacy_reference_viscosity_Pa_s": float(config["options/fluid/SE/mu_Pa_s"][0, 0]),
            "runtime_controller_reference_viscosity_Pa_s": scalar("se_pressure_feedforward_reference_mu_Pa_s"),
            "legacy_reference_bed_loss_MPa": legacy_reference_drop,
            "runtime_table_reference_bed_loss_MPa": runtime_reference_drop,
            "legacy_vs_runtime_reference_loss_relative_error": legacy_reference_drop/runtime_reference_drop-1,
            "feedforward_activity_range": [float(activity.min()), float(activity.max())],
            "feedforward_bias_times_ratio_max_abs_residual_MPa": float(np.max(np.abs(ff-np.abs(bias*ratio)))),
            "native_loss_range_MPa": [float(native_drop.min()), float(native_drop.max())],
            "distributed_laminar_vs_native_rms_relative_error": float(np.sqrt(np.mean((predicted/native_drop-1)**2))),
            "endpoint_vs_distributed_viscosity_mean_relative_error": float(np.mean(mu_end/mu_distributed-1)),
            "feedforward_vs_frozen_target_bed_loss_mean_relative_error": float(mismatch.mean()),
            "feedforward_vs_frozen_target_bed_loss_range_relative_error": [float(mismatch.min()), float(mismatch.max())],
            "axial_temperature_span_range_K": [float(np.ptp(temperature, axis=0).min()), float(np.ptp(temperature, axis=0).max())],
            "bed_flow_vs_route_flow_max_abs_kg_s": float(np.max(np.abs(flow-measured))),
            "scope": "Bed only; accessories, valve loss and route-source mapping not removed. Closed-loop trajectories do not identify an intervention.",
        }
        traces = dict(time=time, flow=measured, target=target, ff=ff, command=command,
                      native_target=frozen_target_drop, temperature=temperature)
    return result, traces


def plot(traces, directory):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 9, "pdf.fonttype": 42})
    t = traces["time"] - 190
    fig, axes = plt.subplots(3, 1, figsize=(7.1, 7.8), constrained_layout=True)
    axes[0].axhspan(.95*traces["target"]*1000, 1.05*traces["target"]*1000, color="#eeeeee", label="5% reference band (not RMS test)")
    axes[0].plot(t, traces["flow"]*1000, color="#0072B2", label="Measured inlet flow")
    axes[0].axhline(traces["target"]*1000, color="black", ls="--", label="Target")
    axes[0].set_ylabel("Mass flow (g/s)")
    axes[1].plot(t, traces["ff"], color="#0072B2", label="Endpoint feedforward magnitude")
    axes[1].plot(t, traces["native_target"], color="#009E73", label="Frozen-target bed loss (diagnostic)")
    axes[1].plot(t, traces["command"], color="#CC79A7", ls="--", label="Total pressure command magnitude")
    axes[1].set_ylabel("Pressure (MPa)")
    for i, ax in enumerate(axes[:2]):
        ax.legend(frameon=False, fontsize=8, loc="best")
        ax.text(.01, .97, f"({chr(97+i)})", transform=ax.transAxes, va="top")
        ax.grid(alpha=.15)
        ax.set_xlim(t[0], t[-1])
    im = axes[2].pcolormesh(t, np.arange(1,22), traces["temperature"], shading="auto", cmap="viridis")
    axes[2].set_ylabel("SE fluid segment")
    axes[2].set_xlabel("Phase time in cycle 20 (s)")
    axes[2].text(.01, .97, "(c)", transform=axes[2].transAxes, va="top", color="white")
    fig.colorbar(im, ax=axes[2], label="Fluid temperature (K)")
    directory.mkdir(parents=True, exist_ok=True)
    for suffix in ("png", "pdf"):
        fig.savefig(directory / ("stage4_distributed_resistance."+suffix), dpi=300)
    plt.close(fig)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--experiment-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--figure-root", type=Path)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Never overwrite diagnostic evidence")
    root = args.experiment_root.resolve()
    execution = json.loads((root / "cold_chamber_execution.json").read_text(encoding="utf-8-sig"))
    if not execution["collection_pass"] or execution["cycle_count"] != 20:
        raise ValueError("This analysis requires the completed 20-cycle diagnostic")
    if execution["start_time_s"] != 0 or execution["stop_time_s"] != 200:
        raise ValueError("Require the independent 0--200 s cold window")
    arms = [analyze_arm(root, arm, 198.801, 199.85) for arm in ("native", "conservative")]
    result = {"schema": "heatdrive_ecc_stage4_distributed_resistance_v1", "diagnostic_only": True,
              "arms": [row for row, _ in arms], "causal_direction_identified": False,
              "production_recovery_allowed": False, "table4_reproduction_claim": False,
              "input_sha256": {str(p.relative_to(root)): sha256(p) for p in
                  [root/"cold_chamber_execution.json"] + [root/arm/name for arm in ("native","conservative")
                    for name in ("observations.mat", "configuration.mat", "inventory_metadata.json")]}}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False)+"\n", encoding="utf-8")
    if args.figure_root:
        plot(arms[0][1], args.figure_root)
    print(json.dumps(result["arms"], indent=2))
