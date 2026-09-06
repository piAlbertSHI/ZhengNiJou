"""Separate discrete residuals and native tank inventory, using retained C181 data."""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_NativeResidualLocalization import component_terms
from Audit_HeatDriveECC_NativeWindowLedger import NativeWindowLedger
from Audit_HeatDriveECC_NativeWindowPackets import load_packet
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    if args.output_dir.exists():
        raise FileExistsError("Do not overwrite diagnostic figures")
    audit = args.repo / "outputs_storage_audit"
    source = audit / "native_residual_localization_20260906/localization_v2_BE.json"
    record = json.loads(source.read_text(encoding="utf-8-sig"))
    paths = {"topology": audit / "tl_domain_energy_tables_20260906/tl_domain_metadata.json",
             "probe": audit / "native_inventory_port_comparison_20260906/native_inventory_probe.json",
             "metadata": audit / "native_inventory_model_metadata_20260906/storage_model_metadata.json",
             "packet": args.repo / "outputs/qian_native_inventory_pilot_from_c180_20260906/cycle_181/native_window.mat"}
    if (record["production_recovery_allowed"] or not record["original_ledger_recalculation_pass"]
            or any(sha256(path) != record["input_sha256"][name] for name, path in paths.items())):
        raise ValueError("Figure inputs changed or diagnostic authority overstated")
    ledger = NativeWindowLedger(*(json.loads(paths[n].read_text(encoding="utf-8-sig")) for n in ("topology", "probe", "metadata")))
    _, streams = load_packet(paths["packet"])
    native = streams["native"]
    time = next(iter(native.values()))["time"]
    phase = time - time[0]
    root = "heatdrive_ecc_coupled_se21/"
    plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 9, "axes.titlesize": 10,
                         "axes.labelsize": 9, "legend.fontsize": 8, "pdf.fonttype": 42, "path.simplify": False})
    figures = []

    def decorate(ax, title, ylabel):
        ax.set(title=title, xlabel="Time within C181 (s)", ylabel=ylabel, xlim=(0, 10), xticks=[0, 3.5, 5, 8.5, 10])
        for x in (3.5, 5, 8.5):
            ax.axvline(x, color="0.75", lw=.65, ls=":")
        ax.grid(axis="y", color="0.90", lw=.5)
        ax.spines[["top", "right"]].set_visible(False)

    def save(fig, name):
        for suffix in ("png", "pdf"):
            path = args.output_dir / (name + "." + suffix)
            fig.savefig(path, dpi=300)
            figures.append(dict(path=str(path.resolve()), bytes=path.stat().st_size, sha256=sha256(path)))
        plt.close(fig)

    args.output_dir.mkdir(parents=True)
    fig, axes = plt.subplots(2, 2, figsize=(7.4, 5.4), layout="constrained")
    for ax, name, title in zip(axes.flat,
            ("SMA_PumpInletConnectingPipeVolume", "SMA_PumpOutletConnectingPipeVolume", "SHEXFluidBuffer", "SMAHotFluidBuffer"),
            ("(a) Pump inlet chamber", "(b) Pump outlet chamber", "(c) SHEX water tank", "(d) SMA hot-side water tank")):
        path = root + name
        template = ledger.templates[path]
        block = {k: v for k, v in template.items() if k != "leaf_variables"}
        block["leaf_variables"] = [dict(name=leaf["name"], unit=leaf["unit"], time_s=time,
             values=native[path + "::" + leaf["name"]]["values"][:, 0]) for leaf in template["leaf_variables"]]
        _, terms, _ = component_terms(block, ledger.tables[ledger.basis[path]["settings_path"]])
        for field, color, style, label in (("energy_residual_J", "#D55E00", "-", "Trapezoid path"),
                ("BE_energy_residual_J", "#0072B2", "--", "Local BE equation")):
            ax.plot(phase, np.r_[0., np.cumsum(terms[field])], color=color, ls=style, lw=1.1, label=label)
        decorate(ax, title, "Cumulative energy residual (J)")
        ax.legend(frameon=False, loc="best")
    fig.suptitle("C181 diagnostic: two balance definitions, unchanged samples", fontsize=11)
    save(fig, "Fig09_native_balance_definitions")
    fig, axes = plt.subplots(2, 2, figsize=(7.4, 5.4), layout="constrained")
    for column, (names, labels) in enumerate(((('SHEXFluidBuffer', 'SMAHotFluidBuffer'), ('SHEX', 'SMA hot side')),
                                             (('ColdFluidBuffer', 'HotFluidBuffer'), ('SE cold side', 'SE hot side')))):
        for name, label, color, style in zip(names, labels, ("#0072B2", "#D55E00"), ("-", "--")):
            for row, leaf_name, unit, scale in ((0, "mass", "kg", 1000), (1, "T_I", "K", 1)):
                leaf = native[root + name + "::" + leaf_name]
                values = convert(leaf["values"][:, 0], leaf["unit"], unit)
                axes[row, column].plot(phase, (values - values[0]) * scale, color=color, ls=style, lw=1.1, label=label)
        for row in range(2):
            axes[row, column].legend(frameon=False, loc="best")
    for ax, title, ylabel in zip(axes.flat,
            ("(a) Water-loop tank masses", "(b) SE-loop tank masses", "(c) Water-loop internal temperatures", "(d) SE-loop internal temperatures"),
            ("Mass change from cycle start (g)", "Mass change from cycle start (g)",
             "Internal temperature change (K)", "Internal temperature change (K)")):
        decorate(ax, title, ylabel)
    fig.suptitle("C181 native tank states: within-cycle motion is not periodicity", fontsize=11)
    save(fig, "Fig10_native_tank_inventory")
    result = dict(schema="heatdrive_ecc_native_diagnostic_figure_manifest_v1", figures=figures,
                  source_localization_sha256=sha256(source), source_packet_sha256=record["input_sha256"]["packet"],
                  complete_cycle_samples=10001, production_figure_release=False, scientific_gate_relaxed=False)
    (args.output_dir / "figure_manifest.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
