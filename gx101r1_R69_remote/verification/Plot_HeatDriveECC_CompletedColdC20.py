"""Separate measured trajectories, periodicity and inventory ledgers; no final reproduction claim."""
import argparse
import json
from pathlib import Path

import h5py
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256


def plot(root, mechanism_root, ledger_path, output):
    if output.exists():
        raise FileExistsError("Never overwrite figure evidence")
    records = {arm: json.loads((mechanism_root / arm / "saved_cold_mechanism_audit.json").read_text(encoding="utf-8-sig"))
               for arm in ("native", "conservative")}
    ledger = json.loads(ledger_path.read_text(encoding="utf-8-sig"))
    for arm, record in records.items():
        if (record["source_observation_sha256"] != sha256(root / arm / "observations.mat")
                or record["scope"]["absolute_start_s"] != 100 or record["scope"]["absolute_stop_s"] != 200
                or not record["operating_window_mechanism_pass"]):
            raise ValueError("Require the same completed, audited C20 arm")
    if not ledger["evidence_audit_pass"] or ledger["production_recovery_allowed"]:
        raise ValueError("Wrong ledger authority")
    output.mkdir(parents=True)
    plt.rcParams.update({"font.family": "Arial", "font.size": 9, "axes.titlesize": 10,
                         "axes.labelsize": 9, "axes.linewidth": .7, "svg.fonttype": "none",
                         "axes.spines.top": False, "axes.spines.right": False})
    files, checks = [], []

    def save(fig, name, meaning):
        fig.canvas.draw()
        renderer = fig.canvas.get_renderer()
        labels = [*fig.texts]
        for ax in fig.axes:
            labels += [ax.title, ax.xaxis.label, ax.yaxis.label, *ax.texts]
            for axis in (ax.xaxis, ax.yaxis):
                lo, hi = sorted(axis.get_view_interval())
                for tick in axis.get_major_ticks():
                    if lo <= tick.get_loc() <= hi:
                        labels += [tick.label1, tick.label2]
            if ax.get_legend():
                labels += ax.get_legend().get_texts()
        for legend in fig.legends:
            labels += legend.get_texts()
        for label in labels:
            if label.get_visible() and label.get_text():
                box = label.get_window_extent(renderer)
                if box.x0 < -1 or box.y0 < -1 or box.x1 > fig.bbox.width + 1 or box.y1 > fig.bbox.height + 1:
                    raise ValueError("Clipped figure text: " + label.get_text())
        for extension in ("png", "svg"):
            path = output / (name + "." + extension)
            fig.savefig(path, dpi=300, facecolor="white")
            files.append({"path": str(path), "bytes": path.stat().st_size, "sha256": sha256(path)})
        checks.append({"figure": name, "text_within_canvas": True, "meaning": meaning})
        plt.close(fig)

    with h5py.File(root / "conservative" / "observations.mat", "r") as raw:
        t = raw["signals/SE_Tx21_internal/time_s"][:].reshape(-1)
        indices = np.flatnonzero((t >= 190) & (t <= 200))
        if len(indices) != 10001 or t[indices[0]] != 190 or t[indices[-1]] != 200:
            raise ValueError("Incomplete last cycle")
        window = slice(indices[0], indices[-1] + 1)
        phase = t[window] - 190
        colors = ["#0072B2", "#009E73", "#CC79A7"]
        fig, axes = plt.subplots(2, 2, figsize=(7.1, 5.2), sharex=True, layout="constrained")
        for col, (component, offset) in enumerate((("SMA", 42), ("SE", 63))):
            temperature = raw[f"signals/{component}_Tx21_internal/values"][:, window]
            fraction = raw["signals/ECC_constitutive21_output/values"][offset:offset + 21, window]
            for ax, values in ((axes[0, col], temperature), (axes[1, col], fraction)):
                ax.fill_between(phase, values.min(axis=0), values.max(axis=0), color="#BFC4C7", alpha=.28,
                                linewidth=0, label="21-node envelope")
                for node, color in zip((0, 10, 20), colors):
                    ax.plot(phase, values[node], color=color, lw=1.0, label=f"Node {node + 1}")
                for a, b in ((0, 3.5), (5, 8.5)):
                    ax.axvspan(a, b, color="#EEEEEE", alpha=.35, zorder=-2)
                ax.set_xlim(0, 10)
                ax.grid(axis="y", color="#DDDDDD", lw=.45)
            axes[0, col].set_title(f"({'ab'[col]}) {component} temperature")
            axes[1, col].set_title(f"({'cd'[col]}) {component} phase")
            axes[1, col].set(xlabel="Time within cycle 20 (s)", ylim=(-.04, 1.04), yticks=[0, .5, 1])
        axes[0, 0].set_ylabel("Temperature (K)")
        axes[0, 1].set_ylabel("Temperature (K)")
        for ax in axes[1]:
            ax.set_ylabel("Martensite fraction")
        handles, names = axes[0, 0].get_legend_handles_labels()
        fig.legend(handles, names, loc="outside lower center", ncols=4, frameon=False, fontsize=8)
        fig.suptitle("Conservative-inventory arm | transient C20, not periodic", fontsize=11)
        save(fig, "Fig01_material_trajectories",
             "Actual 190-200 s; all 10001 points retained, three named nodes and the full 21-node range. Gray bands are stages I and III.")

    predicates = [
        ("Endpoint temperature", "last_cycle_endpoint_drift_K", "periodic_endpoint_limit_K"),
        ("Same-phase T P99", "last_cycle_same_phase_temperature_p99_drift_K", "periodic_same_phase_temperature_p99_limit_K"),
        ("Same-phase T RMS", "last_cycle_same_phase_temperature_rms_drift_K", "periodic_same_phase_temperature_rms_limit_K"),
        ("Phase extrema", "last_cycle_phase_drift", "periodic_phase_limit"),
        ("Same-phase xM P99", "last_cycle_same_phase_phase_p99_drift", "periodic_same_phase_phase_p99_limit"),
        ("Same-phase xM RMS", "last_cycle_same_phase_phase_rms_drift", "periodic_same_phase_phase_rms_limit"),
    ]
    fig, axes = plt.subplots(1, 2, figsize=(9.2, 3.65), layout="constrained")
    for ax, (arm, record) in zip(axes, records.items()):
        p = record["performance"]
        ratios = [p[value] / p[limit] for _, value, limit in predicates]
        ax.barh(range(6), ratios, height=.58, color=["#B54464" if r > 1 else "#007F86" for r in ratios])
        ax.axvline(1, color="#333333", lw=.8, ls="--")
        ax.set(yticks=range(6), yticklabels=[r[0] for r in predicates], xlim=(0, 1.62),
               xlabel="Measured value / unchanged limit", title=arm.capitalize())
        ax.invert_yaxis()
        for y, ratio in enumerate(ratios):
            ax.text(ratio + .025, y, f"{ratio:.3f}", va="center", fontsize=8)
    fig.suptitle("Public periodicity over 100-200 s | temperature RMS remains above limit", fontsize=11)
    save(fig, "Fig02_periodicity", "Original six public predicates; a ratio above one is not a pass. Not a hidden-state periodicity certificate.")

    fig, ax = plt.subplots(figsize=(7.1, 3.5), layout="constrained")
    labels = ["Declared 119-store boundary", "Two connecting chambers", "Four buffers"]
    for index, arm in enumerate(ledger["arms"]):
        groups = arm["component_groups"]
        buffer_key = "Tank (TL)" if arm["arm"] == "native" else "Conservative Buffer (TL)"
        values = [arm["source_minus_actual_endpoint_storage_J"],
                  groups["Constant Volume Chamber (TL)"]["endpoint_energy_residual_J"],
                  groups[buffer_key]["endpoint_energy_residual_J"]]
        bars = ax.barh(np.arange(3) + (index - .5) * .3, values, height=.27,
                       color=["#70777D", "#007F86"][index], label=arm["arm"].capitalize())
        for bar, value in zip(bars, values):
            ax.text(value - .05 if value < -.1 else .045, bar.get_y() + bar.get_height() / 2,
                    f"{value:.4f}" if abs(value) > 1e-6 else f"{value:.2e}",
                    ha="right" if value < -.1 else "left", va="center", fontsize=8)
    ax.set(yticks=range(3), yticklabels=labels, xlim=(-4.1, .65),
           xlabel="Net input minus own endpoint inventory (J)",
           title="Endpoint-inventory discrepancy | 180-200 s, not a full-device certificate")
    ax.axvline(0, lw=.6, color="#333333")
    ax.invert_yaxis()
    ax.legend(frameon=False, loc="lower left")
    save(fig, "Fig03_endpoint_inventory", "Native endpoint discrepancy is retained; conservative residual is not rounded to zero or treated as full-device validation.")

    inputs = {str(ledger_path): sha256(ledger_path)}
    for arm in records:
        p = mechanism_root / arm / "saved_cold_mechanism_audit.json"
        inputs[str(p)] = sha256(p)
        inputs[str(root / arm / "observations.mat")] = records[arm]["source_observation_sha256"]
    manifest = {"schema": "heatdrive_ecc_completed_c20_figures_v1", "input_sha256": inputs,
                "files": files, "checks": checks, "periodic_steady_state_claim": False,
                "table4_reproduction_claim": False, "simulation_executed": False}
    (output / "figure_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"figures": len(checks), "no_text_clipped": True, "table4_claim": False}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for argument in ("root", "mechanism-root", "ledger-path", "output"):
        parser.add_argument("--" + argument, type=Path, required=True)
    plot(**vars(parser.parse_args()))
