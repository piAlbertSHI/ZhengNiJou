"""Independent scalar-sum readback of compact, passive local CV integrals."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess

import numpy as np

from Analyze_HeatDriveECC_CaloricCycle import read_packet, reconstruct
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Reference_HeatDriveECC_LocalBoundaries import LocalBoundaries
from Run_HeatDriveECC_ConservativeTransport import write_json


def readback(root):
    execution = root/"local_boundary_execution.json"
    record = json.loads(execution.read_text(encoding="utf-8"))
    if (record.get("collection_complete") is not True
            or record.get("observer_coordinates_excluded_from_step_selection_and_error_norm") is not True
            or record.get("production_state_loaded") is not False
            or record.get("checkpoint_saved") is not False
            or record.get("production_recovery_allowed") is not False):
        raise ValueError("Not a complete isolated-observer protocol")
    repo = Path(__file__).resolve().parents[2]
    for name, expected in record["source_sha256"].items():
        file = Path(__file__).with_name(name)
        blob = subprocess.check_output(["git", "show", record["execution_commit"]+":"+file.relative_to(repo).as_posix()], cwd=repo)
        if hashlib.sha256(blob).hexdigest().upper() != expected:
            raise ValueError("Historical producer mismatch: "+name)
        if name in ("Reference_HeatDriveECC_CaloricCoupling.py", "Reference_HeatDriveECC_LocalBoundaries.py") and sha256(file) != expected:
            raise ValueError("Current readback helper changed: "+name)
    control_root = Path(record["parameter_and_comparison_root"])
    if sha256(control_root/"caloric_cycle_execution.json") != record["parameter_execution_sha256"]:
        raise ValueError("Changed control execution")
    prior, _, clocks, control, _ = read_packet(control_root)
    model = reconstruct(record["network_contract"])
    if prior["network_contract"] != record["network_contract"]:
        raise ValueError("Changed physical contract")
    ledger = LocalBoundaries(model)
    if ledger.contract() != record["control_volume_contract"]:
        raise ValueError("Changed edge/control-volume convention")
    raw = root/record["raw"]["file"]
    if raw.resolve().parent != root.resolve() or sha256(raw) != record["raw"]["sha256"]:
        raise ValueError("Wrong raw packet path/hash")
    with np.load(raw, allow_pickle=False) as data:
        t, states, stages, energy, mass = (data[k].copy() for k in (
            "time_s", "diagnostic_coordinates_NOT_OP", "completed_stage", "boundary_integral_J", "boundary_mass_integral_kg"))
    if (not np.array_equal(t, clocks) or states.shape != control.shape
            or energy.shape != mass.shape or energy.shape != (len(t), len(ledger.edges))
            or not np.isfinite(np.r_[states.ravel(), energy.ravel(), mass.ravel()]).all()
            or not np.array_equal(states[0], model.initial_state()) or np.any(energy[0]) or np.any(mass[0])):
        raise ValueError("Invalid clocks, dimensions, finite values or cold initial coordinates")
    for stage, end in enumerate((3.5, 5., 8.5, 10.), 1):
        hits = np.flatnonzero(t == end)
        if len(hits) != 1 or stages[hits[0]] != stage:
            raise ValueError("Missing exact stage endpoint")
    inventories = []
    for state in states:
        row = {name: math.fsum(state[model.slices[name]]) for name in model.components}
        for name, material, solid, phase in (("SMA_total", "SMA", "solid_a", "phase_a"),
                ("SE_total", "SE", "solid_r", "phase_r")):
            factor = model.c["solid_mass_kg"][material]*model.c["materials"][material]["Delta_h_J_per_kg"]/model.n
            row[name] = math.fsum([*state[model.slices[solid]], *(-factor*state[model.slices[phase]])])
        row.update(zip(("water_return", "hot_chamber", "cold_chamber"), state[model.slices["buffer_H"]]))
        row.update(zip(("bus_source", "bus_hot", "bus_cold", "load_sensor"), state[model.slices["bus_E"]]))
        inventories.append(row)
    rows = []
    for name in ledger.names:
        weights = [(j, (1 if target == name else 0)-(1 if source == name else 0))
                   for j, (_, source, target) in enumerate(ledger.edges) if source == name or target == name]
        de = np.array([inventory[name]-inventories[0][name] for inventory in inventories])
        q = np.array([math.fsum(sign*value[j] for j, sign in weights) for value in energy])
        dm = np.zeros(len(t))
        if name in ("hot_chamber", "cold_chamber"):
            j = 0 if name == "hot_chamber" else 1
            dm = states[:, model.slices["buffer_mass_change"].start+j]-states[0, model.slices["buffer_mass_change"].start+j]
        transferred = np.array([math.fsum(sign*value[j] for j, sign in weights) for value in mass])
        rows.append({"CV": name, "maximum_energy_residual_J": float(abs(de-q).max()),
            "maximum_mass_residual_kg": float(abs(dm-transferred).max()),
            "final_inventory_change_J": float(de[-1]), "final_net_boundary_J": float(q[-1])})
    maximum_e = max(row["maximum_energy_residual_J"] for row in rows)
    maximum_m = max(row["maximum_mass_residual_kg"] for row in rows)
    if maximum_e > 1e-8 or maximum_m > 1e-15:
        raise ValueError("Independent scalar-sum local numerical budget failed")
    return {"schema": "heatdrive_ecc_local_boundary_readback_v1", "reader_sha256": sha256(Path(__file__)),
        "execution": str(execution), "execution_sha256": sha256(execution), "raw_sha256": sha256(raw),
        "observations": len(t), "control_volumes": rows, "edge_count": len(ledger.edges),
        "independent_scalar_sum_energy_max_J": maximum_e, "independent_scalar_sum_mass_max_kg": maximum_m,
        "all_saved_base_coordinates_bitwise_equal_to_control": bool(np.array_equal(states, control)),
        "accepted_step_count_matches_control": record["accepted_steps"] == prior["accepted_steps"],
        "observer_isolation_numerical_control": True, "whole_component_identity_only": True,
        "all_step_or_independent_physics_validation": False,
        "material_or_periodic_qualified": False, "production_recovery_allowed": False,
        "strict_Table4_reproduced": False}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError(args.output)
    result = readback(args.root.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    write_json(args.output, result)
    print(json.dumps({key: result[key] for key in ("observations", "edge_count",
        "independent_scalar_sum_energy_max_J", "independent_scalar_sum_mass_max_kg",
        "all_saved_base_coordinates_bitwise_equal_to_control", "accepted_step_count_matches_control")}))
