"""Observe phase ordering before scheduled/actual blow; do not change production gates."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256


def phase_row(time, fraction, index):
    x = fraction[:, index]
    return {"time_s": float(time[index]), "minimum_xM": float(x.min()),
            "maximum_xM": float(x.max()), "mean_xM": float(x.mean())}


def before_flow(time, fraction, flow, start, stop, target, level):
    time, fraction, flow = np.asarray(time), np.asarray(fraction), np.asarray(flow)
    if (fraction.ndim != 2 or fraction.shape[1] != len(time) or len(flow) != len(time)
            or not np.isfinite(fraction).all() or not np.isfinite(flow).all()
            or not np.all(np.diff(time) > 0) or target <= 0 or not 0 < level < 1):
        raise ValueError("Require finite ordered phase/flow observations")
    indices = np.flatnonzero((time >= start) & (time < stop) & (np.abs(flow) >= target * level))
    if not len(indices) or indices[0] == 0:
        raise ValueError("No witnessed blow onset with a preceding measured sample")
    i = int(indices[0])
    return {"flow_fraction_for_onset": level, "onset_time_s": float(time[i]),
            "onset_flow_kgps": float(flow[i]), "prior_measured_phase": phase_row(time, fraction, i - 1)}


def audit(root):
    execution = json.loads((root / "cold_chamber_execution.json").read_text(encoding="utf-8-sig"))
    if not execution["collection_pass"] or execution["cycle_count"] != 20 or execution["checkpoint_saved"]:
        raise ValueError("Require completed diagnostic C20")
    arms = []
    for arm in ("native", "conservative"):
        path = root / arm / "observations.mat"
        completion = json.loads((root / arm / "arm_completion.json").read_text(encoding="utf-8-sig"))
        digest = sha256(path)
        if digest != completion["observation_sha256"]:
            raise ValueError("Observation hash changed")
        with h5py.File(path, "r") as f, h5py.File(root / arm / "configuration.mat", "r") as cfg:
            s = f["signals"];window = slice(190000, 200001)
            time = s["SE_Tx21_internal/time_s"][:].reshape(-1)[window]
            if not np.allclose(time, 190 + np.arange(10001) * .001, rtol=0, atol=1e-12):
                raise ValueError("Require the measured final 1 ms cycle")
            fraction = s["ECC_constitutive21_output/values"][63:84, window]
            target = float(cfg["options/branch/m_dot_se_chex_kg_per_s"][0, 0])
            rows = []
            for name, start, stop, signal in (("loading_before_hot_blow", 193.5, 195, "mass_flow_v1_cold_inlet_kgps"),
                                              ("unloading_before_cold_blow", 198.5, 200, "mass_flow_v4_hot_inlet_kgps")):
                i = int(round((start - 190) / .001))
                flow = s[signal + "/values"][0, window]
                rows.append({"transition": name, "scheduled_start_phase": phase_row(time, fraction, i),
                             "scheduled_prior_sample": phase_row(time, fraction, i - 1),
                             "actual_onset_checks": [before_flow(time, fraction, flow, start, stop, target, level)
                                                     for level in (.01, .1)]})
        arms.append({"arm": arm, "observation_sha256": digest, "observations": rows})
    return {"schema": "heatdrive_ecc_before_blow_phase_review_v1", "arms": arms,
            "source_execution_sha256": sha256(root / "cold_chamber_execution.json"),
            "window_s": [190, 200], "scientific_gates_modified": False, "simulation_executed": False,
            "existing_half_cycle_completion_gate_is_not_a_before_blow_gate": True,
            "phase_completion_cause_identified": False, "production_recovery_allowed": False,
            "table4_reproduction_claim": False}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Never overwrite phase-order evidence")
    result = audit(args.root)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
