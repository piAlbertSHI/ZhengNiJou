"""Compare zero-volume and finite shared-SE cold diagnostics at event level.

This is a read-only diagnostic. It does not relax a seed gate, grant recovery
authority, or declare a finite-junction model physically valid. It records the
state and controller differences that must be explained before a new cold seed
or 20-cycle continuation is attempted.
"""
import argparse
import hashlib
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_SegmentedEvidence import text_field


EVENT_WINDOWS_S = {
    "stage2": (3.8, 4.85),
    "stage4": (8.8, 9.85),
}
CONTROLLER_SIGNALS = (
    "stage4_pressure_command",
    "stage4_integrator_state",
    "stage4_integrator_output_gate",
    "stage4_dynamic_feedforward",
    "stage4_route_integral",
    "stage4_flow_error",
    "stage4_filtered_error",
    "stage4_p_output",
)
PRESSURE_SIGNALS = (
    "pump_pressure_se_stage2_port_a_MPa",
    "pump_pressure_se_stage2_port_b_MPa",
    "pump_pressure_se_stage4_port_a_MPa",
    "pump_pressure_se_stage4_port_b_MPa",
)
FINITE_CHAMBER_SUFFIXES = (
    "SharedSEHotLegChamber_Conn2",
    "SharedSEHotLegChamber_Conn3",
    "SharedSEColdLegChamber_Conn1",
    "SharedSEColdLegChamber_Conn4",
)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def scalar_signal(file, group_name, signal_name):
    group = file[group_name]
    if signal_name not in group:
        return None
    signal = group[signal_name]
    time = np.asarray(signal["time_s"][:], dtype=float).reshape(-1)
    values = np.asarray(signal["values"][:], dtype=float)
    if values.ndim != 2 or values.shape[0] != 1 or values.shape[1] != time.size:
        raise ValueError(f"Expected scalar signal: {group_name}/{signal_name}")
    if not np.isfinite(time).all() or not np.isfinite(values).all():
        raise ValueError(f"Nonfinite signal: {group_name}/{signal_name}")
    return time, values[0]


def assert_same_grid(left, right):
    if left[0].shape != right[0].shape or not np.array_equal(left[0], right[0]):
        raise ValueError("Reference and candidate grids differ")
    if left[0].size != 10001 or abs(left[0][0]) > 1e-12 or abs(left[0][-1] - 10.0) > 1e-12:
        raise ValueError("Require the declared 10 s, 1 ms cold diagnostic grid")


def summary(left, right, time):
    delta = right - left
    result = dict(
        samples=int(delta.size),
        reference_rms=float(np.sqrt(np.mean(left * left))),
        candidate_rms=float(np.sqrt(np.mean(right * right))),
        delta_rms=float(np.sqrt(np.mean(delta * delta))),
        delta_max_abs=float(np.max(np.abs(delta))),
    )
    for name, (start, stop) in EVENT_WINDOWS_S.items():
        mask = (time >= start) & (time <= stop)
        if not mask.any():
            raise ValueError(f"Empty event window: {name}")
        window_delta = delta[mask]
        result[name] = dict(
            samples=int(mask.sum()),
            reference_mean=float(np.mean(left[mask])),
            candidate_mean=float(np.mean(right[mask])),
            delta_mean=float(np.mean(window_delta)),
            delta_rms=float(np.sqrt(np.mean(window_delta * window_delta))),
            delta_max_abs=float(np.max(np.abs(window_delta))),
        )
    return result


def chamber_state(root):
    observations = root / "native" / "observations.mat"
    metadata = json.loads((root / "native" / "inventory_metadata.json").read_text(encoding="utf-8"))
    volumes = {
        row["block_path"]: float(row["mask_parameters"]["volume"]["value"])
        for row in metadata["storage_blocks"]
        if row["mask_type"] == "Constant Volume Chamber (TL)"
        and any(row["block_path"].endswith(suffix) for suffix in FINITE_CHAMBER_SUFFIXES)
    }
    result = []
    with h5py.File(observations, "r") as file:
        rows = named_rows(file, file["native"])
        paths = sorted({path for path, _ in rows if any(path.endswith(suffix) for suffix in FINITE_CHAMBER_SUFFIXES)})
        for path in paths:
            required = {"T_I", "p_I", "rho_I", "u_I", "h_I", "mdot_A", "mdot_B", "Phi_A", "Phi_B", "Q_H"}
            if {name for block, name in rows if block == path} != required:
                raise ValueError(f"Incomplete finite chamber state: {path}")
            time = rows[path, "T_I"]["time_s"][:].reshape(-1)
            values = {name: rows[path, name]["values"][:].reshape(-1) for name in required}
            volume = volumes[path]
            mass = values["rho_I"] * volume
            energy = mass * values["u_I"]
            net_mass = values["mdot_A"] + values["mdot_B"]
            net_energy = values["Phi_A"] + values["Phi_B"] + values["Q_H"]
            result.append(dict(
                block_path=path,
                volume_m3=volume,
                initial_temperature_K=float(values["T_I"][0]),
                final_temperature_K=float(values["T_I"][-1]),
                temperature_range_K=float(np.ptp(values["T_I"])),
                initial_pressure_MPa=float(values["p_I"][0] / 1e6),
                final_pressure_MPa=float(values["p_I"][-1] / 1e6),
                initial_mass_kg=float(mass[0]),
                final_mass_kg=float(mass[-1]),
                mass_change_kg=float(mass[-1] - mass[0]),
                net_mass_flow_integral_kg=float(np.trapezoid(net_mass, time)),
                internal_energy_change_J=float(energy[-1] - energy[0]),
                net_energy_flow_integral_J=float(np.trapezoid(net_energy, time)),
                trapezoid_energy_balance_gap_J=float(np.trapezoid(net_energy, time) - (energy[-1] - energy[0])),
            ))
    if len(result) != 4:
        raise ValueError("Expected exactly four finite shared-SE diagnostic chambers")
    return result


def audit(reference_root, candidate_root, output):
    reference_file = Path(reference_root) / "native" / "observations.mat"
    candidate_file = Path(candidate_root) / "native" / "observations.mat"
    common = []
    with h5py.File(reference_file, "r") as reference, h5py.File(candidate_file, "r") as candidate:
        for group_name, signal_names in (("stage4_controller_probe_signals", CONTROLLER_SIGNALS),
                                         ("pressure_probe_signals", PRESSURE_SIGNALS)):
            for signal_name in signal_names:
                left = scalar_signal(reference, group_name, signal_name)
                right = scalar_signal(candidate, group_name, signal_name)
                if left is None or right is None:
                    raise ValueError(f"Missing common contract signal: {group_name}/{signal_name}")
                assert_same_grid(left, right)
                common.append(dict(group=group_name, signal=signal_name,
                                   comparison=summary(left[1], right[1], left[0])))
    candidate_metadata = json.loads(
        (Path(candidate_root) / "native" / "inventory_metadata.json").read_text(encoding="utf-8"))
    storage_mode = candidate_metadata.get("se_shared_junction_storage_mode", "")
    result = dict(
        schema="heatdrive_ecc_shared_se_state_contract_v1",
        reference_observations_sha256=sha256(reference_file),
        candidate_observations_sha256=sha256(candidate_file),
        reference_root=str(Path(reference_root).resolve()),
        candidate_root=str(Path(candidate_root).resolve()),
        declared_event_windows_s=EVENT_WINDOWS_S,
        candidate_storage_mode=storage_mode,
        common_controller_and_pressure_signals=common,
        finite_shared_chamber_state=chamber_state(Path(candidate_root)),
        contract_completeness_pass=True,
        production_recovery_allowed=False,
        seed_or_periodic_authority_granted=False,
        interpretation=("The artifact compares state and controller trajectories only. "
                        "It cannot convert a finite-junction candidate into a seed or recovery source."),
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference-root", type=Path, required=True)
    parser.add_argument("--candidate-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = audit(args.reference_root, args.candidate_root, args.output)
    print(json.dumps({
        "contract_completeness_pass": result["contract_completeness_pass"],
        "seed_or_periodic_authority_granted": result["seed_or_periodic_authority_granted"],
        "chambers": len(result["finite_shared_chamber_state"]),
        "signals": len(result["common_controller_and_pressure_signals"]),
    }, indent=2))
