"""One fresh cold cycle with passive, independently reconstructed CV ledgers.

Sealed prior packet is read for parameters and comparison, never initial state.
No OP, checkpoint, native-equivalence or material/periodic qualification.
"""
import argparse
import json
from pathlib import Path
import platform
import subprocess
import time
import traceback

import numpy as np
import scipy

from Analyze_HeatDriveECC_CaloricCycle import read_packet
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Reference_HeatDriveECC_LocalBoundaries import ObservedCycle
from Reference_HeatDriveECC_TwoWayPhase import TwoWaySharedSurfaceCycle
from Run_HeatDriveECC_CaloricCycle import simulate
from Run_HeatDriveECC_ConservativeTransport import write_json


def identify_operator(record):
    operator = record.get("phase_operator")
    contract_operator = record["network_contract"].get("phase_operator")
    if operator == "stage_free_shared_surface" and contract_operator == operator:
        return operator, "explicit execution and network contract"
    if operator == "scheduled_reduced" and contract_operator in (None, operator):
        return operator, "explicit execution; legacy scheduled network contract"
    if (operator is None and contract_operator is None
            and record["execution_commit"] == "cb8c0b3d5f6383cdd5ce400333a66a7d2e152e10"):
        # read_packet already verifies the historical complete source blobs and
        # equality of the actually executed CaloricCycle/transport reader helpers.
        return "scheduled_reduced", "exact legacy producer cb8c0b3; source hashes checked by read_packet"
    raise ValueError("Unidentified or contradictory phase-operator contract")


def run(output, parameter_root):
    output.mkdir(parents=True, exist_ok=False)
    begin = time.perf_counter()
    record = {"schema": "heatdrive_ecc_local_boundary_protocol_v1", "collection_complete": False,
        "execution_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], encoding="utf-8").strip(),
        "parameter_and_comparison_root": str(parameter_root),
        "parameter_execution_sha256": sha256(parameter_root/"caloric_cycle_execution.json"),
        "prior_state_used_to_initialize": False, "production_state_loaded": False,
        "checkpoint_saved": False, "production_recovery_allowed": False,
        "material_or_periodic_qualified": False, "native_SLX_equivalent": False,
        "outer_solve_or_Table4_input": False, "scientific_gate_thresholds_changed": False,
        "runtime": {"python": platform.python_version(), "numpy": np.__version__, "scipy": scipy.__version__},
        "local_numerical_budgets": {"energy_J": 1e-8, "mass_kg": 1e-15},
        "passive_observer_numerical_comparison": {"temperature_K": 1e-9, "phase_fraction": 1e-11},
        "budget_scope": "discrete local inventory identity, not physical validation or all-step gate"}
    write_json(output/"preflight.json", record)
    try:
        prior, base, clocks, states, _ = read_packet(parameter_root)
        if prior["cycles"] != 1 or prior["completed_time_s"] != 10.:
            raise ValueError("Require an existing complete C1 control, not a restart packet")
        operator, evidence = identify_operator(prior)
        record["phase_operator"] = operator
        record["phase_operator_evidence"] = evidence
        if operator == "stage_free_shared_surface":
            base = TwoWaySharedSurfaceCycle(base.c, base.fluids)
        names = set(prior["source_sha256"]) | {
            Path(__file__).name, "Reference_HeatDriveECC_LocalBoundaries.py", "Analyze_HeatDriveECC_CaloricCycle.py"}
        record["source_sha256"] = {name: sha256(Path(__file__).with_name(name)) for name in sorted(names)}
        record["network_contract"] = base.c
        observer = ObservedCycle(base)
        record["control_volume_contract"] = observer.boundaries.contract()
        record["initial_base_coordinates_bitwise_equal_to_cold_control"] = bool(np.array_equal(base.initial_state(), states[0]))
        with (output/"completed_stage_observations.jsonl").open("x", encoding="utf-8") as progress:
            def stage_sink(row):
                progress.write(json.dumps(row, allow_nan=False)+"\n")
                progress.flush()
            profiles, result = simulate(observer, 1, .005, 1e-6, stage_sink)
        y = profiles.pop("diagnostic_coordinates_NOT_OP")
        physical, energy, mass = y[:, :base.size], y[:, observer.slices["boundary_energy"]], y[:, observer.slices["boundary_mass"]]
        er, mr = observer.boundaries.residual(physical, energy, mass)
        local = [{"CV": name, "maximum_observed_energy_residual_J": float(abs(er[:, j]).max()),
                  "maximum_observed_mass_residual_kg": float(abs(mr[:, j]).max()),
                  "final_inventory_change_J": float((physical[-1]-physical[0])@observer.boundaries.energy_weights[j]),
                  "final_net_boundary_integral_J": float(energy[-1]@observer.boundaries.incidence[j])}
                 for j, name in enumerate(observer.boundaries.names)]
        if abs(er).max() > 1e-8 or abs(mr).max() > 1e-15:
            raise ValueError("Local numerical inventory budget failed; not a material failure")
        if not np.array_equal(profiles["time_s"], clocks):
            raise ValueError("Cannot compare different observation clocks")
        comparison = {}
        for name in ("Ta", "Tr", "buffer_T", "bus_T", "xa", "xr"):
            comparison[name] = max(float(np.max(abs(base.unpack(a)[name]-base.unpack(b)[name])))
                                   for a, b in zip(physical, states))
            limit = 1e-11 if name in ("xa", "xr") else 1e-9
            if comparison[name] > limit:
                raise ValueError("Passive observer perturbed the numerical physical trajectory beyond roundoff allowance")
        raw = output/"selected_local_boundaries.npz"
        np.savez_compressed(raw, **profiles, diagnostic_coordinates_NOT_OP=physical,
                            boundary_integral_J=energy, boundary_mass_integral_kg=mass)
        record.update(result, collection_complete=True, wall_seconds=time.perf_counter()-begin,
            raw={"file": raw.name, "sha256": sha256(raw), "bytes": raw.stat().st_size},
            control_volumes=local, local_energy_max_J=float(abs(er).max()), local_mass_max_kg=float(abs(mr).max()),
            observer_comparison_max_selected_difference=comparison,
            observer_extra_coordinates_do_not_enter_physical_RHS=True,
            observer_coordinates_excluded_from_step_selection_and_error_norm=True,
            physical_accepted_step_count_matches_control=(result["accepted_steps"] == prior["accepted_steps"]),
            exact_stage_stops=True, local_identity_pass=True,
            independence="boundary ports and common force/velocity rebuilt without summing cell RHS; same numerical time integrator, not independent physics",
            limitation="whole-component balance, not per-cell accuracy; prescribed flows, unresolved material/walls/pressure/pump remain")
        write_json(output/"local_boundary_execution.json", record)
        print(json.dumps({"output": str(output), "collection_complete": True, "CVs": len(local),
            "edges": observer.edge_count, "completed_time_s": result["completed_time_s"],
            "local_energy_max_J": record["local_energy_max_J"], "local_mass_max_kg": record["local_mass_max_kg"],
            "wall_seconds": record["wall_seconds"], "raw_bytes": raw.stat().st_size,
            "execution_sha256": sha256(output/"local_boundary_execution.json")}))
    except Exception:
        record.update(error_traceback=traceback.format_exc(), wall_seconds=time.perf_counter()-begin)
        write_json(output/"FAILED_NOT_A_RECOVERY_SOURCE.json", record)
        raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--parameter-root", type=Path, required=True)
    args = parser.parse_args()
    run(args.output.resolve(), args.parameter_root.resolve())
