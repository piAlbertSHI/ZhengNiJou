"""Plot measured own-state heat-law responses separately from grid observations."""
import argparse
import json
from pathlib import Path

import h5py
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

from Analyze_HeatDriveECC_SinglePipeHeatStep import read_traces
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def plot(review_path, output):
    if output.exists():
        raise FileExistsError("Never overwrite reference figures")
    review = json.loads(review_path.read_text(encoding="utf-8"))
    if not review["reference_states_independently_integrated"] or len(review["cases"]) != 24:
        raise ValueError("Require the actual own-state reference study")
    output.mkdir(parents=True)
    plt.rcParams.update({"font.family": "Arial", "font.size": 9, "axes.titlesize": 10,
        "axes.spines.top": False, "axes.spines.right": False, "svg.fonttype": "none"})
    styles = {"native": ("#0072B2", "-", "Native heat law", "native_traces"),
              "reference_saved_Nu": ("#333333", "--", "Reference, saved Nu", "reference_saved_Nu_traces"),
              "reference_Q01": ("#009E73", "-.", "Reference, Nu=3.66", "reference_q01_traces")}
    files, checks, inputs = [], [], {str(review_path): sha256(review_path)}

    def save(fig, stem, scope):
        fig.canvas.draw(); renderer = fig.canvas.get_renderer()
        labels = [*fig.texts, *[t for legend in fig.legends for t in legend.get_texts()]]
        for ax in fig.axes:
            labels += [ax.title, ax.xaxis.label, ax.yaxis.label, *ax.texts]
            for axis in (ax.xaxis, ax.yaxis):
                lo, hi = sorted(axis.get_view_interval())
                labels += [tick.label1 for tick in axis.get_major_ticks() if lo <= tick.get_loc() <= hi]
        for label in labels:
            box = label.get_window_extent(renderer)
            if label.get_visible() and label.get_text() and (box.x0 < -1 or box.y0 < -1
                    or box.x1 > fig.bbox.width+1 or box.y1 > fig.bbox.height+1):
                raise ValueError("Clipped figure label: " + label.get_text())
        for suffix in ("png", "svg"):
            path = output / (stem+"."+suffix)
            fig.savefig(path, dpi=260, facecolor="white")
            files.append({"path": str(path), "bytes": path.stat().st_size, "sha256": sha256(path)})
        checks.append({"figure": stem, "text_within_canvas": True, "scope": scope})
        plt.close(fig)

    fig, axes = plt.subplots(2, 2, figsize=(7.6, 5.5), sharex=True, layout="constrained")
    for column, material in enumerate(("SMA", "SE")):
        for line, delta in enumerate((5, -5)):
            row = next(c for c in review["cases"] if c["material"] == material and c["flow_kgps"] > 0
                       and c["wall_step_K"] == delta and c["fixed_step_s"] == .00025)
            path = Path(review["raw_root"]) / row["file"]
            if sha256(path) != row["sha256"]:
                raise ValueError("Raw own-state trajectory changed")
            inputs[str(path)] = row["sha256"]
            ax = axes[line, column]
            with h5py.File(path, "r") as f:
                for branch, (color, style, label, field) in styles.items():
                    if material == "SE" and branch == "reference_saved_Nu":
                        continue  # Equal-law SE branches are exactly coincident; plot one.
                    t, values = read_traces(f, field, step=.00025)
                    ax.plot(t*1000, values["T_I"]-303.15, color=color, ls=style, label=label, lw=1.3)
            ax.axvline(20, color="#AAAAAA", ls=":", lw=.7)
            ax.set(title=f"({chr(97+line*2+column)}) {material}, wall step {delta:+d} K",
                   xlim=(0, 100), ylabel="Fluid temperature change (K)")
            if line == 1:
                ax.set_xlabel("Time (ms)")
            ax.grid(axis="y", color="#DDDDDD", lw=.5)
    handles, names = axes[0, 0].get_legend_handles_labels()
    fig.legend(handles, names, loc="outside lower center", ncols=3, frameon=False, fontsize=8)
    fig.suptitle("Independently integrated heat laws | 0.25 ms, positive flow\nSE reference laws coincide; isolated cells, not system performance", fontsize=10)
    save(fig, "Fig01_own_temperature_trajectories", "Each heat law evolves its own native TL states; all 401 points retained.")

    fig, axes = plt.subplots(1, 2, figsize=(7.6, 3.7), layout="constrained")
    for ax, material in zip(axes, ("SMA", "SE")):
        for branch, (color, style, label, _) in styles.items():
            if material == "SE" and branch == "reference_saved_Nu":
                continue
            row = next(r for r in review["three_grid_observations"] if r["material"] == material
                       and r["flow_kgps"] > 0 and r["wall_step_K"] == 5 and r["branch"] == branch)
            ax.loglog([1., .5], row["metrics"]["T_I"]["successive_max_differences"],
                      marker="o", color=color, ls=style, label=label, lw=1.2, ms=4)
        ax.set(title=material, xlabel="Coarser step dt (ms)",
               ylabel="Max |T(dt) - T(dt/2)| (K)", xticks=[.5, 1.], xticklabels=["0.5", "1.0"])
        ax.minorticks_off(); ax.grid(axis="both", color="#DDDDDD", lw=.5)
    handles, names = axes[0].get_legend_handles_labels()
    fig.legend(handles, names, loc="outside lower center", ncols=3, frameon=False, fontsize=8)
    fig.suptitle("Three-grid observations | positive flow, +5 K wall step\nExact common samples; no interpolation or spatial-convergence claim", fontsize=10)
    save(fig, "Fig02_time_step_refinement", "Measured max differences, 1 vs 0.5ms and 0.5 vs 0.25ms, including step onset.")
    result = {"schema": "heatdrive_ecc_own_state_reference_figures_v1", "input_sha256": inputs,
              "files": files, "checks": checks, "full_reference_or_system_validation": False}
    (output/"figure_manifest.json").write_text(json.dumps(result, indent=2)+"\n", encoding="utf-8")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--review", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    record = plot(args.review, args.output)
    print(json.dumps({"figures": len(record["checks"]), "text_within_canvas": True}))
