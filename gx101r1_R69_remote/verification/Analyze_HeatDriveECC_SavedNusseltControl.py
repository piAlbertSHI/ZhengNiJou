"""Saved one-factor Nu control readback; never grants a production seed."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

import h5py
import numpy as np

from Analyze_HeatDriveECC_CaloricCycle import read_packet, independent_energies
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Run_HeatDriveECC_SavedNusseltControl import SavedNusseltCycle
from Run_HeatDriveECC_ConservativeTransport import write_json


def review(root, output):
    execution = root/"saved_Nu_execution.json"
    r = json.loads(execution.read_text(encoding="utf-8"))
    if (r.get("collection_complete") is not True or r.get("production_state_loaded") is not False
            or r.get("production_recovery_allowed") is not False or r.get("checkpoint_saved") is not False
            or r.get("cycles") != 1):
        raise ValueError("Not a complete one-cycle cold Nu diagnostic")
    for name, expected in r["source_sha256"].items():
        source = subprocess.check_output(["git", "show", r["execution_commit"]+":gx101r1_R69_remote/verification/"+name])
        if hashlib.sha256(source).hexdigest().upper() != expected:
            raise ValueError("Historical source changed: "+name)
        if name in {"Run_HeatDriveECC_SavedNusseltControl.py", "Reference_HeatDriveECC_CaloricCoupling.py"} and sha256(Path(__file__).with_name(name)) != expected:
            raise ValueError("Current readback operator differs from the saved Nu producer: "+name)
    control_root = Path(r["control_root"])
    if sha256(control_root/"caloric_cycle_execution.json") != r["control_execution_sha256"]:
        raise ValueError("Changed baseline packet")
    baseline, old, t, control, _ = read_packet(control_root)
    if baseline["raw"]["sha256"] != r["control_raw_sha256"]:
        raise ValueError("Changed baseline raw data")
    c = dict(r["network_contract"])
    saved_nu = c.pop("saved_forced_Nu")
    if c != old.c or saved_nu != r["saved_Nu"]:
        raise ValueError("More than one physical contract item changed")
    if sha256(Path(r["saved_configuration"])) != r["saved_configuration_sha256"]:
        raise ValueError("Changed Nu configuration")
    with h5py.File(r["saved_configuration"], "r") as f:
        nu = {m: float(np.asarray(f["options/branch/"+key]).item()) for m, key in
              (("SMA", "sma_pipe_Nu"), ("SE", "se_pipe_Nu"))}
    if nu != saved_nu:
        raise ValueError("Nu does not match saved values")
    raw = root/r["raw"]["file"]
    if raw.resolve().parent != root.resolve() or sha256(raw) != r["raw"]["sha256"]:
        raise ValueError("Wrong Nu raw packet")
    with np.load(raw, allow_pickle=False) as z:
        clocks, states = z["time_s"].copy(), z["diagnostic_coordinates_NOT_OP"].copy()
    model = SavedNusseltCycle(r["network_contract"], old.fluids)
    if not np.array_equal(clocks, t) or not np.array_equal(states[0], model.initial_state()) or states.shape != control.shape:
        raise ValueError("Changed clock, cold state or coordinate layout")
    energy = independent_energies(model, states)
    external = states[:, model.slices["ledgers"]][:, :3].sum(axis=1)
    maximum = float(np.max(abs(energy-energy[0]-external)))
    if maximum > 1e-8:
        raise ValueError("Saved numerical inventory balance failed")
    a, b = [model.unpack(y) for y in states], [old.unpack(y) for y in control]
    differences = {k: max(float(np.max(abs(x[k]-y[k]))) for x, y in zip(a, b)) for k in ("Ta", "Tr", "xa", "xr")}
    before = int(np.flatnonzero(t == 3.5)[0])
    result = {"schema": "heatdrive_ecc_saved_Nu_control_review_v1", "reader_sha256": sha256(Path(__file__)),
              "execution": str(execution), "execution_sha256": sha256(execution), "raw_sha256": sha256(raw),
              "selected_times": len(t), "all_other_physical_contract_items_equal": True,
              "configuration_Nu_verified": nu, "relative_SMA_Nu_increase": nu["SMA"]/3.66-1,
              "independent_selected_energy_residual_J": maximum, "maximum_selected_field_differences": differences,
              "before_hot_blow_SE_min_xM": {"legacy": float(b[before]["xr"].min()), "saved_Nu": float(a[before]["xr"].min())},
              "not_a_complete_material_fix": True, "periodic_qualified": False,
              "all_production_mechanism_gates_evaluated": False, "production_recovery_allowed": False,
              "C200_SCP_deviation_attributed": False, "twenty_cycle_seed_allowed": False,
              "historical_legacy_Nu_controls_remain_valid_as_declared_controls": True}
    output.mkdir(parents=True, exist_ok=False)
    write_json(output/"saved_Nu_review.json", result)
    plot(t, a, b, nu["SMA"], output)
    return result


def plot(t, actual, control, nu, output):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(1, 3, figsize=(11.4, 3.6), layout="constrained")
    for data, color, style, label in ((control, "#666666", "--", "Legacy Nu=3.66"),
                                      (actual, "#126b59", "-", "Saved Nu=%.3f" % nu)):
        axes[0].plot(t, [p["Ta"].mean() for p in data], linestyle=style, color=color, label=label)
        axes[1].plot(t, [p["xr"].min() for p in data], linestyle=style, color=color)
        i = int(np.flatnonzero(t == 3.5)[0])
        axes[2].plot((np.arange(len(data[i]["xr"]))+.5)/len(data[i]["xr"]), data[i]["xr"], linestyle=style, color=color)
    axes[0].set(xlabel="Time (s)", ylabel="Axial mean SMA solid temperature (K)", title="SMA thermal response")
    axes[0].legend(frameon=False, fontsize=8)
    axes[1].set(xlabel="Time (s)", ylabel="Minimum SE martensite fraction", title="SE phase completion", ylim=(-.02, 1.02))
    axes[2].set(xlabel="Fixed axial coordinate x/L", ylabel="SE martensite fraction", title="Before hot blow, t=3.5 s", ylim=(.88, 1.01))
    for ax in axes[:2]:
        ax.axvline(3.5, linewidth=.6, color="#888888", linestyle=":")
    for ax in axes:
        ax.spines[["top", "right"]].set_visible(False)
    fig.suptitle("Single cold cycle: saved-Nu fidelity control, unchanged reduced material law", fontsize=11)
    fig.savefig(output/"saved_Nu_cold_comparison.png", dpi=180)
    plt.close(fig)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    a = parser.parse_args()
    r = review(a.root.resolve(), a.output.resolve())
    print(json.dumps({k: r[k] for k in ("selected_times", "independent_selected_energy_residual_J", "maximum_selected_field_differences", "before_hot_blow_SE_min_xM", "production_recovery_allowed")}, allow_nan=False))
