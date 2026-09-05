"""Preserve closed-window results while diagnosing the terminal reset boundary."""
import argparse
import hashlib
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_ObservedStateDrift import comparison_grid, matlab_text


def audit(contract_path):
    repo = Path(__file__).resolve().parent.parent
    contract = json.loads(contract_path.read_text(encoding="utf-8-sig"))
    raw = repo / contract["result_relative_path"]
    observation = repo / contract["observation_relative_path"]
    for path, key in ((raw, "result_sha256"), (observation, "observation_sha256")):
        with path.open("rb") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest().upper() != contract[key]:
                raise ValueError("Terminal comparison source hash mismatch")
    with h5py.File(observation, "r") as file:
        row = next(file[ref] for ref in file["observation/states"][()].ravel()
                   if matlab_text(file[ref]["block_path"]).endswith("/SMAPressurePI_Integrator"))
        t = row["time_s"][()].ravel()
        y = row["values"][0, :]
        tau = float(file["observation/cycle_period_s"][0, 0])
        current, prior = comparison_grid(t, tau)
        delta = y[current] - y[prior]
        boundary = np.flatnonzero(np.isclose(np.mod(t, tau), 0, atol=1e-7))
        pi = {"unit": "MPa, from controller Ki and saturation-limit definitions",
              "cycle_boundary_time_s": t[boundary].tolist(),
              "cycle_boundary_value": y[boundary].tolist(),
              "terminal_time_s": t[-3:].tolist(), "terminal_values": y[-3:].tolist(),
              "closed_max_abs": float(np.max(np.abs(delta))),
              "closed_rms": float(np.sqrt(np.mean(delta**2))),
              "excluding_only_terminal_sample_max_abs": float(np.max(np.abs(delta[:-1]))),
              "excluding_only_terminal_sample_rms": float(np.sqrt(np.mean(delta[:-1]**2)))}
    with h5py.File(raw, "r") as file:
        p = file["physical"]
        t = p["time_s"][0, :]
        end = contract["completed_cycles"]
        start = int(np.searchsorted(t, (end - 10) * tau - 1e-8))
        time = t[start:]
        fields = {name: p[name][:, start:] for name in ("xM_SMA_21", "xM_SE_21")}
        phases = np.linspace(0, tau, 401)
        closed, half_open = [], []
        for cycle in range(end - 8, end + 1):
            for values in fields.values():
                a = np.vstack([np.interp((cycle - 2) * tau + phases, time, x) for x in values])
                b = np.vstack([np.interp((cycle - 1) * tau + phases, time, x) for x in values])
                difference = b - a
                closed.extend(difference.ravel())
                half_open.extend(difference[:, :-1].ravel())
        original_rms = float(file["summary/performance/last_cycle_same_phase_phase_rms_drift"][0, 0])
        rms = float(np.sqrt(np.mean(np.square(closed))))
        if not np.isclose(rms, original_rms, rtol=1e-8, atol=1e-12):
            raise ValueError("Independent closed-phase RMS disagrees with the original summary")
        limit = float(file["summary/performance/periodic_same_phase_phase_rms_limit"][0, 0])
        half_rms = float(np.sqrt(np.mean(np.square(half_open))))
    result = {"schema": "heatdrive_ecc_terminal_state_diagnostic_v1",
              "source_result_sha256": contract["result_sha256"],
              "source_observation_sha256": contract["observation_sha256"],
              "SMA_PI": pi,
              "phase_fraction_original_closed_grid_rms": rms,
              "phase_fraction_half_open_grid_rms_diagnostic_only": half_rms,
              "original_phase_rms_limit_unchanged": limit,
              "phase_rms_fails_both_grids": rms > limit and half_rms > limit,
              "production_gate_changed": False,
              "recovery_authorized": False,
              "interpretation": "The SMA PI terminal point is kept, not discarded. "
              "Internal commutation resets differ from the final stop command in "
              "disable_sma_feedback_during_commutation. Removing the repeated cycle "
              "endpoint diagnostically does not explain away the phase RMS failure."}
    output = raw.parent / "terminal_state_comparison.json"
    output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract", type=Path, default=Path(__file__).with_name("runtime_observation_c200_diagnostic_contract.json"))
    audit(parser.parse_args().contract)
