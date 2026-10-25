"""Read sealed C20 traces; distinguish observed kinetics from frozen-input bounds.

No time integration, state restoration, parameter fit or scientific gate changes.
"""
import argparse
import json
import subprocess
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_PhaseBeforeBlow import before_flow
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Analyze_HeatDriveECC_PhaseDriveBudget import reverse_coordinate


PRODUCER = "de1abba6d5f159348fefe650ec4459d3ba624f3c"
KERNEL = "gx101r1_R69_remote/verification/HeatDriveECC_StableKernelCandidate.m"
WRAPPER = "gx101r1_R69_remote/verification/HeatDriveECC_ConstitutiveStateVectorStep21_KernelCandidate.m"


def scalar(cfg, key):
    value = float(np.asarray(cfg["options/" + key]).item())
    if not np.isfinite(value):
        raise ValueError("Nonfinite required parameter: " + key)
    return value


def parameters(cfg):
    materials = {
        name: {k: scalar(cfg, "material/" + name + "/" + k) for k in
               ("T_As_K", "T_Ms_K", "C_A_Pa_per_K", "C_M_Pa_per_K", "epsilon_T", "E_m_Pa")}
        for name in ("SMA", "SE")}
    geometry = {k: scalar(cfg, "geometry/" + k) for k in ("L_a_m", "L_r_m", "S_a_m2", "S_r_m2")}
    kinetics = {k: scalar(cfg, "constitutive/" + k) for k in (
        "drive_width_a_Pa", "drive_width_r_Pa", "rate_a_to_A_1_per_s", "rate_a_to_M_1_per_s",
        "rate_r_load_1_per_s", "rate_r_stage3_unload_1_per_s", "max_rate_1_per_s")}
    if any(v <= 0 for v in [*geometry.values(), *kinetics.values()]):
        raise ValueError("Require positive geometry and kinetic scales")
    for m in materials.values():
        if not m["T_As_K"] > m["T_Ms_K"] > 0 or any(
                m[k] <= 0 for k in ("C_A_Pa_per_K", "C_M_Pa_per_K", "epsilon_T", "E_m_Pa")):
            raise ValueError("Unsupported phase surface or elastic parameters")
    return materials["SMA"], materials["SE"], geometry, kinetics


def common_stress(xa, xr, a, r, g):
    ratio = g["S_r_m2"] / g["S_a_m2"]
    denominator = g["L_a_m"] * ratio / a["E_m_Pa"] + g["L_r_m"] / r["E_m_Pa"]
    sr = (g["L_a_m"] * np.mean(a["epsilon_T"] * (1 - xa), axis=0)
          - g["L_r_m"] * np.mean(r["epsilon_T"] * xr, axis=0)) / denominator
    return ratio * sr, sr


def phase_rate(temperature, phase, stress, material, width, rate, increasing, maximum):
    surface = material["T_As_K"] + (material["T_Ms_K"] - material["T_As_K"]) * phase
    if increasing:
        drive = stress - material["C_M_Pa_per_K"] * (temperature - surface)
    else:
        drive = material["C_A_Pa_per_K"] * (temperature - surface) - stress
    gate = 1 - np.exp(-np.maximum(drive, 0) / width)
    velocity = rate * gate * (1 - phase) if increasing else -rate * gate * phase
    return drive, gate, np.clip(velocity, -maximum, maximum)


def frozen_endpoint(ta_phase, tr, a, r, g, loading):
    """Necessary drive condition under frozen T and observed driver phase, not a new state."""
    target = np.ones_like(tr) if loading else np.zeros_like(tr)
    _, stress = common_stress(ta_phase, target, a, r, g)
    slope = r["C_M_Pa_per_K"] if loading else r["C_A_Pa_per_K"]
    intercept = r["T_Ms_K"] if loading else r["T_As_K"]
    required = slope * (tr - intercept)
    node = int(np.argmax(required) if loading else np.argmin(required))
    margin = stress - required[node] if loading else required[node] - stress
    return {"scope": "frozen_delayed_SE_temperature_and_observed_SMA_phase_algebra_only",
            "target_SE_xM": float(loading), "limiting_node_1based": node + 1,
            "target_common_SE_stress_Pa": float(stress),
            "limiting_phase_boundary_stress_Pa": float(required[node]),
            "necessary_drive_margin_Pa": float(margin),
            "necessary_drive_nonnegative": bool(margin >= 0),
            "limiting_temperature_K": float(tr[node]),
            "target_phase_temperature_boundary_K": float(intercept + stress / slope),
            "predicts_modified_coupled_trajectory": False}


def numerical_match(actual, expected, name):
    if actual.shape != expected.shape or not np.isfinite(actual).all() or not np.isfinite(expected).all():
        raise ValueError("Missing/nonfinite reconstruction: " + name)
    error = float(np.max(np.abs(actual - expected)))
    scale = max(1., float(np.max(np.abs(actual))), float(np.max(np.abs(expected))))
    allowance = 1024 * np.finfo(float).eps * scale
    if error > allowance:
        raise ValueError(f"{name}: equation mismatch {error} > numerical allowance {allowance}")
    return {"max_abs_difference": error, "floating_point_allowance": allowance,
            "elements_compared": int(actual.size)}


def source_binding(repo):
    rows = []
    import hashlib
    for relative in (KERNEL, WRAPPER):
        producer = subprocess.check_output(["git", "show", PRODUCER + ":" + relative], cwd=repo)
        # Git stores source with LF; only normalize working-copy line endings for this source check.
        working = (repo / relative).read_bytes().replace(b"\r\n", b"\n")
        if producer != working:
            raise ValueError("Source differs from declared producer: " + relative)
        rows.append({"path": relative, "producer_git_blob_sha256": hashlib.sha256(producer).hexdigest().upper()})
    return {"producer_commit": PRODUCER, "source_equivalence": rows,
            "runtime_backend_snapshot_available": False,
            "scope": "producer source plus measured equation reconstruction; not runtime path attestation"}


def read_arm(root, arm, execution):
    path = root / arm / "observations.mat"
    cfgpath = root / arm / "configuration.mat"
    completion_path = root / arm / "arm_completion.json"
    completion = json.loads(completion_path.read_text(encoding="utf-8-sig"))
    digest = sha256(path)
    case = next(row for row in execution["cases"] if row["arm"] == arm)
    if (completion["execution_commit"] != PRODUCER or completion["arm"] != arm
            or completion["cycle_count"] != 20 or completion["stop_time_s"] != 200
            or completion["observation_sha256"] != digest or case["observation_sha256"] != digest):
        raise ValueError("Completed source identity mismatch")
    window = slice(190000, 200001)
    delayed = slice(189999, 200000)
    with h5py.File(path, "r") as f, h5py.File(cfgpath, "r") as cfg:
        a, r, g, c = parameters(cfg)
        tau = scalar(cfg, "schedule/tau_cycle_s")
        ends = np.asarray(cfg["options/schedule/stage_end_s"]).reshape(-1)
        if tau != 10 or not np.array_equal(ends, [3.5, 5., 8.5, 10.]):
            raise ValueError("Unsupported measured schedule")
        if scalar(cfg, "constitutive/simulink_sample_time_s") != .001:
            raise ValueError("Unsupported delay interval")
        if scalar(cfg, "constitutive/phase_front_smoothing_1_per_s") != 0:
            raise ValueError("Require the producer's unsmoothed phase law")
        s = f["signals"]
        time = 190 + np.arange(10001) * .001
        for name in ("SMA_Tx21_internal", "SE_Tx21_internal", "ECC_constitutive21_output",
                     "mass_flow_v1_cold_inlet_kgps", "mass_flow_v4_hot_inlet_kgps"):
            measured = np.asarray(s[name + "/time_s"]).reshape(-1)[window]
            if measured.shape != time.shape or not np.allclose(measured, time, rtol=0, atol=1e-12):
                raise ValueError("Mismatched final-cycle clocks: " + name)
        td = np.asarray(s["SE_Tx21_internal/time_s"]).reshape(-1)[delayed]
        if not np.allclose(time - td, .001, rtol=0, atol=1e-12):
            raise ValueError("Missing preceding temperature sample")
        ta = s["SMA_Tx21_internal/values"][:, delayed]
        tr = s["SE_Tx21_internal/values"][:, delayed]
        tr_now = s["SE_Tx21_internal/values"][:, window]
        y = s["ECC_constitutive21_output/values"][:, window]
        if y.shape != (252, 10001) or not all(np.isfinite(v).all() for v in (ta, tr, tr_now, y)):
            raise ValueError("Incomplete final-cycle observations")
        xa, xr = y[42:63], y[63:84]
        if np.min([xa.min(), xr.min()]) < 0 or np.max([xa.max(), xr.max()]) > 1:
            raise ValueError("Measured phases outside [0,1]")
        sa, sr = common_stress(xa, xr, a, r, g)
        proof = {"SMA_stress_Pa": numerical_match(y[84:105], np.broadcast_to(sa, (21, 10001)), "SMA stress"),
                 "SE_stress_Pa": numerical_match(y[105:126], np.broadcast_to(sr, (21, 10001)), "SE stress")}
        hot = np.mod(time, tau) < 5
        outputs = {}
        for name, temperature, phase, stress, material, width, rate_hot, rate_cold, hot_increases, pidx, vidx in (
            ("SMA", ta, xa, y[84:105], a, c["drive_width_a_Pa"], c["rate_a_to_A_1_per_s"],
             c["rate_a_to_M_1_per_s"], False, 168, 210),
            ("SE", tr, xr, y[105:126], r, c["drive_width_r_Pa"], c["rate_r_load_1_per_s"],
             c["rate_r_stage3_unload_1_per_s"], True, 189, 231)):
            drive = np.empty_like(phase); gate = np.empty_like(phase); velocity = np.empty_like(phase)
            for mask, increasing, rate in ((hot, hot_increases, rate_hot), (~hot, not hot_increases, rate_cold)):
                drive[:, mask], gate[:, mask], velocity[:, mask] = phase_rate(
                    temperature[:, mask], phase[:, mask], stress[:, mask], material, width,
                    rate, increasing, c["max_rate_1_per_s"])
            proof[name + "_overdrive_Pa"] = numerical_match(y[pidx:pidx+21], drive, name + " overdrive")
            proof[name + "_rate_1_per_s"] = numerical_match(y[vidx:vidx+21], velocity, name + " rate")
            outputs[name] = (drive, gate, velocity)
        rows = []
        target = scalar(cfg, "branch/m_dot_se_chex_kg_per_s")
        for name, start, stop, flow_name, loading in (
            ("before_hot_blow", 193.5, 195., "mass_flow_v1_cold_inlet_kgps", True),
            ("before_cold_blow", 198.5, 200., "mass_flow_v4_hot_inlet_kgps", False)):
            flow = s[flow_name + "/values"][0, window]
            onsets = [before_flow(time, xr, flow, start, stop, target, level) for level in (.01, .1)]
            samples = [("planned_prior", int(round((start - 190) / .001)) - 1)]
            samples += [("actual_prior_" + str(check["flow_fraction_for_onset"]),
                         int(round((check["onset_time_s"] - 190) / .001)) - 1) for check in onsets]
            sample_rows = []
            for label, i in samples:
                j = int(np.argmin(xr[:, i]) if loading else np.argmax(xr[:, i]))
                sample_rows.append({"label": label, "time_s": float(time[i]),
                    "SE_min_xM": float(xr[:, i].min()), "SE_max_xM": float(xr[:, i].max()),
                    "SE_mean_xM": float(xr[:, i].mean()), "SMA_mean_xM": float(xa[:, i].mean()),
                    "common_SE_stress_Pa": float(y[105, i]),
                    "least_complete_node_1based": j + 1,
                    "node_temperature_now_K": float(tr_now[j, i]),
                    "node_delayed_temperature_used_K": float(tr[j, i]),
                    "node_overdrive_Pa": float(outputs["SE"][0][j, i]),
                    "node_gate_fraction": float(outputs["SE"][1][j, i]),
                    "node_rate_1_per_s": float(outputs["SE"][2][j, i]),
                    "frozen_endpoint": frozen_endpoint(xa[:, i], tr[:, i], a, r, g, loading)})
                if not loading:
                    prior = reverse_coordinate(xr[:, i], y[189:210, i] / 1e6, y[105:126, i] / 1e6,
                                               y[231:252, i], r, dict(c, phase_front_smoothing_1_per_s=0.))
                    inferred = np.array([node["inferred_constitutive_input_temperature_K"] for node in prior["nodes"]])
                    sample_rows[-1]["existing_reverse_coordinate_cross_check"] = {
                        "temperature_K": numerical_match(tr[:, i], inferred, "existing reverse input temperature"),
                        "mean_frozen_zero_drive_coordinate": prior["mean_frozen_zero_drive_coordinate"],
                        "scope": "old fixed-stress coordinate; distinct from new compatible target-phase bound"}
            rows.append({"transition": name, "onset_evidence": onsets, "samples": sample_rows})
    negative = y[105] < 0
    return {"arm": arm, "source_path": str(path), "observation_sha256": digest,
            "configuration_sha256": sha256(cfgpath), "completion_sha256": sha256(completion_path),
            "parameters": {"SMA": a, "SE": r, "geometry": g, "kinetics": c},
            "equation_reconstruction": proof, "before_blow": rows,
            "signed_stress_observation": {"minimum_SE_stress_Pa": float(y[105].min()),
                "maximum_SE_stress_Pa": float(y[105].max()), "negative_sample_count": int(negative.sum()),
                "sample_count": int(len(time)),
                "first_negative_sample_s": float(time[negative][0]) if negative.any() else None,
                "compression_or_slack_law_validated": False}}


def analyze(root, repo):
    path = root / "cold_chamber_execution.json"
    execution = json.loads(path.read_text(encoding="utf-8-sig"))
    if (execution["execution_commit"] != PRODUCER or not execution["collection_pass"]
            or execution["cycle_count"] != 20 or execution["checkpoint_saved"] or execution["c200_state_imported"]
            or execution["start_time_s"] != 0 or execution["stop_time_s"] != 200):
        raise ValueError("Require exact completed cold C20 producer, without imported/restored state")
    return {"schema": "heatdrive_ecc_observed_phase_drive_review_v1",
            "analysis_source_sha256": sha256(Path(__file__)),
            "window_s": [190, 200], "temperature_input_delay_s": .001,
            "source_execution_sha256": sha256(path), "source_binding": source_binding(repo),
            "arms": [read_arm(root, arm, execution) for arm in ("native", "conservative")],
            "scope": "exact logged algebra/rates and conditional frozen-input endpoint bounds only",
            "coupled_counterfactual_simulated": False, "unique_performance_gap_cause_proven": False,
            "rate_tuning_ruled_out_for_all_coupled_trajectories": False,
            "simulation_executed": False, "scientific_gates_modified": False,
            "production_recovery_allowed": False, "outer_solve_allowed": False,
            "table4_reproduction_claim": False}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = analyze(args.root.resolve(), args.repo.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as stream:
        json.dump(result, stream, indent=2, allow_nan=False)
        stream.write("\n")
    print(json.dumps({"output": str(args.output), "sha256": sha256(args.output),
                      "arms_reconstructed": [row["arm"] for row in result["arms"]],
                      "simulation_executed": False, "production_recovery_allowed": False}))
