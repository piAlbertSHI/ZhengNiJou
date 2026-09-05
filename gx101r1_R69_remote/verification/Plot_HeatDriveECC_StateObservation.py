"""Plot PI states and tank PORT drift; preserve the superseded v1 figures."""
import argparse
import hashlib
import json
from pathlib import Path

import h5py
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from Audit_HeatDriveECC_ObservedStateDrift import matlab_text


def plot(contract_path, coverage_path):
    repo = Path(__file__).resolve().parent.parent
    contract = json.loads(contract_path.read_text(encoding="utf-8-sig"))
    result_path = repo / contract["result_relative_path"]
    observation_path = repo / contract["observation_relative_path"]
    for path, expected in ((result_path, contract["result_sha256"]),
                           (observation_path, contract["observation_sha256"])):
        with path.open("rb") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest().upper() != expected:
                raise ValueError("Plot source hash mismatch")
    root = result_path.parent
    coverage = json.loads(coverage_path.read_text(encoding="utf-8"))
    if coverage.get("schema") != "heatdrive_ecc_internal_state_coverage_v3":
        raise ValueError("Recompute v3 coverage with explicit port/internal semantics")
    if coverage["source_sha256"] != contract["result_sha256"]:
        raise ValueError("Buffer audit is not bound to the plot source")
    plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 9,
                         "axes.titlesize": 10, "axes.labelsize": 9,
                         "axes.spines.top": False, "axes.spines.right": False,
                         "pdf.fonttype": 42, "savefig.facecolor": "white"})
    fig, axes = plt.subplots(2, 2, figsize=(7.4, 6.1), layout="constrained")
    colors = ["#0072B2", "#009E73", "#D55E00"]
    styles = ["-", "--", ":"]
    total = contract["completed_cycles"]
    cycles = list(range(total - 2, total + 1))
    names = ["SMAPressurePI_Integrator", "SEStage2PressurePI_Integrator",
             "SEStage4PressurePI_Integrator"]
    titles = ["(a) SMA integral pressure correction", "(b) SE stage 2 route memory",
              "(c) SE stage 4 route memory"]
    with h5py.File(observation_path, "r") as file:
        groups = {matlab_text(file[ref]["block_path"]).rsplit("/", 1)[-1]: file[ref]
                  for ref in file["observation/states"][()].ravel()}
        tau = float(file["observation/cycle_period_s"][0, 0])
        for ax, name, title in zip(axes.flat, names, titles):
            row = groups[name]
            t = row["time_s"][()].ravel()
            y = row["values"][0, :]
            for cycle, color, style in zip(cycles, colors, styles):
                a, b = (cycle - 1) * tau, cycle * tau
                selected = (t >= a - 1e-8) & (t <= b + 1e-8)
                ax.plot(t[selected] - a, y[selected], color=color, ls=style,
                        lw=1.1, label=f"Cycle {cycle}")
            ax.set(title=title, xlabel="Cycle time (s)", ylabel="Integral correction (MPa)")
            ax.set_xlim(0, tau + .3)
            ax.ticklabel_format(style="plain", useOffset=False, axis="y")
            ax.grid(axis="y", alpha=.18)
            if name == names[0]:
                ax.plot(tau, y[-1], "o", color=colors[-1], ms=4)
                ax.annotate("Stop endpoint:\nreset not commanded", xy=(tau, y[-1]),
                            xytext=(3.7, .023), fontsize=8,
                            arrowprops={"arrowstyle": "->", "color": "#555555"})
                ax.set_ylim(-.041, .043)
    axes[0, 1].legend(loc="upper left", fontsize=8, frameon=False)
    ax = axes[1, 1]
    fields = ["SHEX_buffer_T_K", "HHEX_buffer_T_K", "SMA_HHEX_buffer_T_K", "CHEX_buffer_T_K"]
    values = [coverage["buffer_port_same_phase_drift"][name]["rms_K"] for name in fields]
    ax.bar(np.arange(4), values, width=.58, color=["#0072B2", "#777777", "#D55E00", "#009E73"])
    ax.set_yscale("log")
    ax.set_xticks(np.arange(4), ["SHEX", "SE-HHEX", "SMA-HHEX", "CHEX"], fontsize=8)
    ax.set(title="(d) Buffer PORT temperature drift", ylabel="One-cycle lag RMS (K)")
    ax.axhline(.01, color="#222222", ls="--", lw=1)
    ax.text(.02, .96, "Port A, not tank internal temperature\n0.01 K: solid-T reference, not a port gate",
            transform=ax.transAxes, va="top", fontsize=7.5)
    for i, value in enumerate(values):
        ax.text(i, value * 1.25, f"{value:.2g}", ha="center", fontsize=8)
    ax.set_ylim(1e-5, .35)
    ax.grid(axis="y", alpha=.15)
    fig.suptitle("PI states and port diagnostics: C200, not periodic", fontsize=12)
    out = root / "figures_state_audit_v2"
    out.mkdir(exist_ok=True)
    stem = out / "Fig08_internal_state_observation"
    for extension in ("png", "pdf"):
        fig.savefig(stem.with_suffix("." + extension), dpi=600)
    plt.close(fig)
    metadata = {"schema": "heatdrive_ecc_state_figure_v2",
                "source_result_sha256": contract["result_sha256"],
                "source_observation_sha256": contract["observation_sha256"],
                "cycles_shown": cycles, "PI_unit_basis": "Integrator inputs Ki have MPa/(kg/s)/s; output saturation limits are MPa.",
                "buffer_port_comparison_window_s": coverage["window_s"],
                "buffer_temperature_semantics": coverage["buffer_temperature_semantics"],
                "source_coverage_sha256": hashlib.sha256(coverage_path.read_bytes()).hexdigest().upper(),
                "supersedes": "figures_state_audit v1 panel (d) semantics only; all values unchanged",
                "sma_terminal_point_retained": True, "requires_separate_visual_review": True,
                "full_internal_steady_claim": False, "table4_reproduction_claim": False}
    (out / "figure_source.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(stem.with_suffix(".png"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract", type=Path, default=Path(__file__).with_name("runtime_observation_c200_diagnostic_contract.json"))
    parser.add_argument("--coverage", type=Path, required=True)
    args = parser.parse_args()
    plot(args.contract, args.coverage)
