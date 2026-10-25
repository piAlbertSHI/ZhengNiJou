"""Fresh paired two-cycle SMA cooling-direction controls with saved Nu.

One process, two independent cold arms. Neither arm is restored from C1/C200.
Local boundary observers match each Nu/flow policy and isolate physical RK norms.
No candidate is a production seed, periodic point or Table4 result.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import time
import traceback

import numpy as np

from Audit_HeatDriveECC_SMAFlowCoordinates import audit
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Analyze_HeatDriveECC_CaloricCycle import reconstruct
from Reference_HeatDriveECC_ConservativeTransport import advective_faces
from Reference_HeatDriveECC_LocalBoundaries import LocalBoundaries, ObservedCycle
from Run_HeatDriveECC_SavedNusseltControl import SavedNusseltCycle
from Run_HeatDriveECC_CaloricCycle import simulate
from Run_HeatDriveECC_ConservativeTransport import write_json


class CoDirectedSMACycle(SavedNusseltCycle):
    def evaluate(self, y, stage):
        d, p, mechanical = super().evaluate(y, stage)
        if stage in (1, 2):
            return d, p, mechanical
        ma = self.c["mass_flow_kg_s"]["SMA"]
        hx_faces = advective_faces(p["h"]["hhex_a"], ma, p["buffer_h"][0], p["buffer_h"][0], order=2, limiter="MC")
        inlet_h = hx_faces[-1]/ma
        old = advective_faces(p["h"]["bed_a"], -ma, inlet_h, inlet_h, order=2, limiter="MC")
        new = advective_faces(p["h"]["bed_a"], ma, inlet_h, inlet_h, order=2, limiter="MC")
        d[self.slices["bed_a"]] += (new[:-1]-new[1:])-(old[:-1]-old[1:])
        d[self.slices["buffer_H"]][0] += new[-1]+old[0]
        return d, p, mechanical


class DirectionalBoundaries(LocalBoundaries):
    def __init__(self, model, co_directed):
        super().__init__(model)
        self.co_directed = co_directed

    def boundary_rates(self, y, stage):
        energy, mass = super().boundary_rates(y, stage)
        p = self.model.unpack(y)
        for suffix, material, solid in (("a", "SMA", "Ta"), ("r", "SE", "Tr")):
            if material == "SE" and stage not in (2, 4):
                continue
            item = self.model.components["bed_"+suffix]
            fluid = p["T"]["bed_"+suffix]
            k = self.model.fluids[material].conductivity(fluid)
            ua = self.model.c["saved_forced_Nu"][material]*k*item["surface_m2"]/item["Dh_m"]
            energy[self.edge_index[material+"_to_fluid"]] = float(np.dot(ua, p[solid]-fluid)/self.model.n)
        if self.co_directed and stage in (3, 4):
            energy[self.edge_index["SMA_to_water"]] = self.model.c["mass_flow_kg_s"]["SMA"]*self.outlet(p["h"]["bed_a"], 1)
        return energy, mass

    def contract(self):
        result = super().contract()
        result["forced_Nu"] = self.model.c["saved_forced_Nu"]
        result["SMA_cooling_direction"] = "co_directed" if self.co_directed else "counter_directed"
        return result


class DirectionObservedCycle(ObservedCycle):
    def __init__(self, base, co_directed):
        super().__init__(base)
        self.boundaries = DirectionalBoundaries(base, co_directed)


def load_control(root):
    execution = root/"saved_Nu_execution.json"
    if sha256(execution) != "EB7769F3582033AA9FD6AC8987319DE2AC2FD2532E79E5C5CC3B29EFC6C9BD61":
        raise ValueError("Expected exact saved-Nu C1 reference")
    r = json.loads(execution.read_text(encoding="utf-8"))
    for name, expected in r["source_sha256"].items():
        data = subprocess.check_output(["git", "show", r["execution_commit"]+":gx101r1_R69_remote/verification/"+name])
        if hashlib.sha256(data).hexdigest().upper() != expected:
            raise ValueError("Wrong historical saved-Nu source")
        if name in {"Run_HeatDriveECC_SavedNusseltControl.py", "Reference_HeatDriveECC_CaloricCoupling.py", "Run_HeatDriveECC_CaloricCycle.py", "Reference_HeatDriveECC_CompensatedBS3.py", "Reference_HeatDriveECC_ConservativeTransport.py"} and sha256(Path(__file__).with_name(name)) != expected:
            raise ValueError("Changed physical/integration helper since saved-Nu reference")
    for dependency in r["network_contract"]["input_dependencies"]:
        if sha256(Path(dependency["path"])) != dependency["sha256"]:
            raise ValueError("Changed physical input")
    raw = root/r["raw"]["file"]
    if raw.resolve().parent != root.resolve() or sha256(raw) != r["raw"]["sha256"]:
        raise ValueError("Changed C1 comparison observations")
    with np.load(raw, allow_pickle=False) as z:
        comparison = {k: z[k].copy() for k in z.files}
    return r, comparison


def run(control_root, native_root, output):
    output.mkdir(parents=True, exist_ok=False)
    names = (Path(__file__).name, "Audit_HeatDriveECC_SMAFlowCoordinates.py", "Run_HeatDriveECC_SavedNusseltControl.py",
             "Reference_HeatDriveECC_CaloricCoupling.py", "Reference_HeatDriveECC_LocalBoundaries.py", "Run_HeatDriveECC_CaloricCycle.py",
             "Reference_HeatDriveECC_CompensatedBS3.py", "Reference_HeatDriveECC_ConservativeTransport.py",
             "Audit_HeatDriveECC_ThermalConnectivity.py", "Audit_HeatDriveECC_TLDomainInventory.py",
             "Analyze_HeatDriveECC_CaloricCycle.py", "Run_HeatDriveECC_ConservativeTransport.py", "Audit_HeatDriveECC_SegmentedEvidence.py")
    record = {"schema": "heatdrive_ecc_SMA_direction_paired_cold_v1", "collection_complete": False,
              "execution_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], encoding="utf-8").strip(),
              "source_sha256": {n: sha256(Path(__file__).with_name(n)) for n in names},
              "independent_cold_arms": True, "production_state_loaded": False, "checkpoint_saved": False,
              "production_recovery_allowed": False, "twenty_cycle_seed_allowed": False, "Table4_input_allowed": False,
              "observer_physical_prefix_isolated": True,
              "sole_physical_difference": "SMA cooling-bed flow direction, counter versus co-directed",
              "material_Nu_geometry_flow_magnitudes_and_initial_coordinates_unchanged": True,
              "paper_topology_hypothesis_not_confirmed_native_fix": True, "cases": []}
    write_json(output/"preflight.json", record)
    begin = time.perf_counter()
    try:
        native = audit(native_root)
        write_json(output/"native_SMA_flow_coordinates.json", native)
        original, control = load_control(control_root)
        record["control_execution"] = str(control_root/"saved_Nu_execution.json")
        record["control_execution_sha256"] = sha256(control_root/"saved_Nu_execution.json")
        record["network_contract"] = original["network_contract"]
        fluids = reconstruct(original["network_contract"]).fluids
        arrays = {}
        with (output/"completed_stage_observations.jsonl").open("x", encoding="utf-8") as stream:
            for name, co in (("counter", False), ("co", True)):
                c = copy.deepcopy(original["network_contract"])
                base = (CoDirectedSMACycle if co else SavedNusseltCycle)(c, fluids)
                model = DirectionObservedCycle(base, co)
                def sink(row):
                    stream.write(json.dumps({"arm": name, **row}, allow_nan=False)+"\n")
                    stream.flush()
                profiles, result = simulate(model, 2, original["max_accepted_step_s"], original["rtol"], sink)
                full = profiles["diagnostic_coordinates_NOT_OP"]
                physical = full[:, :base.size]
                energy, mass = full[:, model.slices["boundary_energy"]], full[:, model.slices["boundary_mass"]]
                re, rm = model.boundaries.residual(physical, energy, mass)
                if abs(re).max() > 1e-8 or abs(rm).max() > 1e-15:
                    raise ValueError("Matched local numerical energy/mass budget failed")
                t = profiles["time_s"]
                if not co:
                    first = t <= 10.
                    if not np.array_equal(t[first], control["time_s"]) or not np.array_equal(physical[first], control["diagnostic_coordinates_NOT_OP"]):
                        raise ValueError("Fresh counter arm does not preserve the isolated-observer C1 numerical control")
                    common_clocks = t.copy()
                elif not np.array_equal(common_clocks, t):
                    raise ValueError("Paired clocks differ; no interpolation")
                arrays[name+"_physical"] = physical
                arrays[name+"_edge_J"] = energy
                arrays[name+"_edge_kg"] = mass
                record["cases"].append({"arm": name, "SMA_heat_cool_signs": [1, 1 if co else -1],
                    "control_volume_contract": model.boundaries.contract(),
                    "maximum_selected_local_energy_residual_J": float(abs(re).max()),
                    "maximum_selected_local_mass_residual_kg": float(abs(rm).max()), **result})
                record["completed_arms"] = len(record["cases"])
                write_json(output/"completed_arm_evidence.json", record)
        heat = common_clocks <= 5.
        if not np.array_equal(arrays["co_physical"][heat], arrays["counter_physical"][heat]):
            raise ValueError("Cooling-direction change perturbed the first heating half")
        raw = output/"paired_direction_profiles.npz"
        np.savez_compressed(raw, time_s=common_clocks, **arrays)
        with np.load(raw, allow_pickle=False) as z:
            if not all(np.array_equal(z[k], a) for k, a in {"time_s": common_clocks, **arrays}.items()):
                raise ValueError("Saved paired observations changed")
        record.update(collection_complete=True, wall_seconds=time.perf_counter()-begin,
                      first_heat_half_array_equal=True, counter_first_cycle_array_equal_to_frozen_C1=True,
                      raw={"file": raw.name, "sha256": sha256(raw), "bytes": raw.stat().st_size})
        write_json(output/"direction_execution.json", record)
    except Exception:
        record.update(wall_seconds=time.perf_counter()-begin, error_traceback=traceback.format_exc())
        write_json(output/"FAILED_DO_NOT_RESUME.json", record)
        raise
    return {"output": str(output), "wall_seconds": record["wall_seconds"], "arms": record["completed_arms"],
            "raw_bytes": record["raw"]["bytes"], "execution_sha256": sha256(output/"direction_execution.json"),
            "local_energy_residuals_J": [c["maximum_selected_local_energy_residual_J"] for c in record["cases"]],
            "production_recovery_allowed": False}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--control-root", type=Path, required=True)
    parser.add_argument("--native-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    a = parser.parse_args()
    print(json.dumps(run(a.control_root.resolve(), a.native_root.resolve(), a.output.resolve()), allow_nan=False))
