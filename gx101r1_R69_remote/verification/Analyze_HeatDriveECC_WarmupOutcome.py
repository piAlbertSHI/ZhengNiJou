"""Summarize two logged warmup cycles without authorizing recovery or claims."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Cycle import metrics
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from HeatDriveECC_DiagnosticAnalysisScope import diagnostic_arms


def paired_drift(values):
    values = np.asarray(values, dtype=float)
    if values.ndim != 2 or values.shape[1] != 20001 or not np.isfinite(values).all():
        raise ValueError("Require finite aligned two-cycle traces at 1 ms")
    delta = values[:, 10000:] - values[:, :10001]
    return {
        "endpoint_max": float(np.max(np.abs(delta[:, -1]))),
        "same_phase_max": float(np.max(np.abs(delta))),
        "same_phase_p99": float(np.percentile(np.abs(delta), 99)),
        "same_phase_rms": float(np.sqrt(np.mean(delta ** 2))),
    }


def flow_window(time, flow, target, start, stop, maximum, rms):
    time, flow = np.asarray(time), np.asarray(flow)
    if (time.ndim != 1 or time.shape != flow.shape or not np.isfinite(time).all()
            or not np.isfinite(flow).all() or not np.isfinite([target, start, stop, maximum, rms]).all()
            or np.any(np.diff(time) <= 0) or maximum < 0 or rms < 0):
        raise ValueError("Invalid flow coordinates or limits")
    mask = (time >= start) & (time <= stop)
    if mask.sum() < 2 or target <= 0:
        raise ValueError("Invalid flow window")
    error = np.abs(flow[mask]) / target - 1
    return {
        "start_s": float(time[mask][0]), "stop_s": float(time[mask][-1]),
        "samples": int(mask.sum()), "mean_signed_kg_s": float(flow[mask].mean()),
        "rms_relative_error": float(np.sqrt(np.mean(error ** 2))),
        "max_abs_relative_error": float(np.max(np.abs(error))),
        "reverse_fraction": float(np.mean(flow[mask] < 0)),
        "tracking_pass": bool(np.all(flow[mask] >= 0) and np.max(np.abs(error)) <= maximum
                              and np.sqrt(np.mean(error ** 2)) <= rms),
    }


def analyze(root):
    execution = json.loads((root / "cold_chamber_execution.json").read_text(encoding="utf-8-sig"))
    count = execution["cycle_count"]
    arms_requested=diagnostic_arms(root,execution)
    if (not execution["collection_pass"] and len(arms_requested)!=1) or count < 2 or execution.get('c200_state_imported', False):
        raise ValueError("Require a completed non-recovery warmup")
    captured = diagnostic_capture_hashes(root, execution)
    stop = float(execution["stop_time_s"])
    start = stop - 20
    arms = []
    for arm in arms_requested:
        with h5py.File(root / arm / "observations.mat", "r") as f, \
                h5py.File(root / arm / "configuration.mat", "r") as config:
            signals = {}
            for name, row in f["signals"].items():
                time = row["time_s"][:].reshape(-1)
                indices = np.flatnonzero((time >= start - 1e-9) & (time <= stop + 1e-9))
                if indices.size != 20001 or not np.allclose(
                        time[indices], start + np.arange(20001) * .001, atol=1e-9, rtol=0):
                    raise ValueError(f"Unaligned final two-cycle signal: {name}")
                signals[name] = row["values"][:, indices[0]:indices[-1] + 1]
            time = start + np.arange(20001) * .001
            options = config["options"]
            scalar = lambda path: float(options[path][0, 0])
            cycles = []
            for index in (0, 1):
                cut = slice(index * 10000, index * 10000 + 10001)
                performance, solids, flows = metrics(
                    {name: values[:, cut] for name, values in signals.items()},
                    options, time[cut], origin=start + 10 * index)
                cycles.append({"cycle": count - 1 + index, "performance": performance,
                               "solids": solids, "controller_window_flows": flows})
            target = (scalar("branch/m_dot_se_the_kg_per_s")
                      + scalar("branch/m_dot_se_chex_kg_per_s")) / 2
            guard = scalar("validation/se_settled_guard_s")
            ramp = scalar("branch/stage_command_ramp_s")
            final_start = stop - 10
            production_flows = []
            for stage, offset, name in ((2, 3.5, "mass_flow_v1_cold_inlet_kgps"),
                                        (4, 8.5, "mass_flow_v4_hot_inlet_kgps")):
                result = flow_window(time, signals[name][0], target,
                                     final_start + offset + max(ramp, guard + .001),
                                     final_start + offset + 1.5 - ramp,
                                     scalar("validation/max_se_settled_flow_relative_error"),
                                     scalar("validation/max_se_settled_flow_rms_relative_error"))
                production_flows.append({"stage": stage, **result})
            temperatures = np.vstack([signals["SMA_Tx21_internal"], signals["SE_Tx21_internal"]])
            phase = signals["ECC_constitutive21_output"][42:84]
            probes = f["stage4_controller_probe_signals"]
            probe_summary = {}
            window_start = final_start + 8.801
            window_stop = stop - .15
            for name in ("stage4_target_flow_command", "stage4_pressure_bias_command",
                         "stage4_integrator_state", "stage4_integrator_input",
                         "stage4_dynamic_feedforward", "stage4_pressure_command"):
                row = probes[name]
                t = row["time_s"][:].reshape(-1)
                values = row["values"][:].reshape(-1)
                mask = (t >= window_start) & (t <= window_stop)
                if not mask.any() or not np.isfinite(values[mask]).all():
                    raise ValueError(f"Invalid final-cycle probe: {name}")
                probe_summary[name] = {"min": float(values[mask].min()),
                                       "max": float(values[mask].max()),
                                       "mean": float(values[mask].mean())}
            arms.append({"arm": arm, "cycles": cycles,
                         "production_window_flows": production_flows,
                         "solid_temperature_drift_K": paired_drift(temperatures),
                         "solid_phase_fraction_drift": paired_drift(phase),
                         "final_cycle_probes": probe_summary})
    return {
        "schema": "heatdrive_ecc_warmup_outcome_v1", "diagnostic_only": True,
        "cycles_run": count, "comparison_cycles": [count - 1, count],
        "arms": arms, "solid_only_drift_not_full_state_steady_audit": True,
        "ten_cycle_qian_window_verified": False, "periodic_full_state_verified": False,
        "production_recovery_allowed": False, "seed_eligible": False,
        "outer_solve_eligible": False, "paired_table4_eligible": False,
        "table4_reproduction_claim": False,
        "diagnostic_complete_OP_saved_not_recovery_authority": bool(captured),
        "input_sha256": {**captured, **{str(path.relative_to(root)): sha256(path) for path in (
            root / "cold_chamber_execution.json",
            *(root/arm/file for arm in arms_requested for file in ('observations.mat','configuration.mat')))}},
    }


def diagnostic_capture_hashes(root, execution):
    if not execution['checkpoint_saved']:
        return {}
    if (execution.get('diagnostic_state_options', {}).get('mode') not in ('capture','diagnostic_resume','restore_preflight')
            or execution.get('production_recovery_allowed') is not False):
        raise ValueError('Unknown checkpoint authority; never treat it as cold evidence')
    if execution.get('diagnostic_state_options', {}).get('mode') == 'restore_preflight':
        if diagnostic_arms(root,execution) != ('native',):
            raise ValueError('Only a complete independently qualified native cold candidate is supported')
    hashes = {}
    for arm in diagnostic_arms(root,execution):
        folder = root/arm
        receipt = folder/'diagnostic_state_capture.json'
        capture = json.loads(receipt.read_text(encoding='utf-8-sig'))
        if (capture.get('schema') != 'heatdrive_ecc_diagnostic_state_capture_v1'
                or capture.get('snapshot_time_s') != execution['stop_time_s']
                or any(capture.get(key) is not False for key in
                       ('production_recovery_allowed', 'diagnostic_continuation_allowed',
                        'source_op_edited', 'state_reconstruction_used'))):
            raise ValueError('Diagnostic state capture scope or timestamp changed')
        for filename, key in (('diagnostic_complete_operating_point.mat', 'operating_point_sha256'),
                              ('diagnostic_state_observation.mat', 'history_sha256')):
            actual = sha256(folder/filename)
            if actual != capture[key]:
                raise ValueError('Diagnostic state file hash changed')
            hashes[str((folder/filename).relative_to(root))] = actual
        hashes[str(receipt.relative_to(root))] = sha256(receipt)
    return hashes


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--experiment-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Never overwrite an outcome")
    result = analyze(args.experiment_root.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps(result["arms"], indent=2))
