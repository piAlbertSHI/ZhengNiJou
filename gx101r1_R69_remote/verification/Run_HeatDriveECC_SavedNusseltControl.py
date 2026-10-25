"""One-factor cold C1: restore saved bed Nu, not tune UA or phase rates.

The legacy reference and its readback remain unchanged. This isolated variant
corrects the conjugate fluid/solid exchange together; no OP is loaded. It is not
the complete native SLX, identified material, a periodic seed or Table4 input.
"""
import argparse
import copy
import json
from pathlib import Path
import subprocess
import time
import traceback

import h5py
import numpy as np

from Analyze_HeatDriveECC_CaloricCycle import read_packet
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Reference_HeatDriveECC_CaloricCoupling import CaloricCycle
from Run_HeatDriveECC_CaloricCycle import simulate
from Run_HeatDriveECC_ConservativeTransport import write_json


class SavedNusseltCycle(CaloricCycle):
    def evaluate(self, y, stage):
        d, p, mechanical = super().evaluate(y, stage)
        for suffix, material, solid in (("a", "SMA", "solid_a"), ("r", "SE", "solid_r")):
            if material == "SE" and stage not in (2, 4):
                continue
            item = self.components["bed_"+suffix]
            k = self.fluids[material].conductivity(p["T"]["bed_"+suffix])
            delta_ua = (self.c["saved_forced_Nu"][material]-3.66)*k*item["surface_m2"]/item["Dh_m"]/self.n
            q = delta_ua*(p["Ta" if material == "SMA" else "Tr"]-p["T"]["bed_"+suffix])
            d[self.slices["bed_"+suffix]] += q
            d[self.slices[solid]] -= q
        return d, p, mechanical


def run(control_root, output):
    baseline, old, clocks, control, _ = read_packet(control_root)
    if baseline["execution_commit"] != "cb8c0b3d5f6383cdd5ce400333a66a7d2e152e10" or baseline["cycles"] != 1:
        raise ValueError("Expected the exact retained scheduled-reduced cold C1 control")
    cfg = Path(next(v["path"] for v in old.c["input_dependencies"] if v["path"].endswith("configuration.mat")))
    with h5py.File(cfg, "r") as f:
        nu = {m: float(np.asarray(f["options/branch/"+key]).item()) for m, key in
              (("SMA", "sma_pipe_Nu"), ("SE", "se_pipe_Nu"))}
    if not np.isfinite(list(nu.values())).all() or min(nu.values()) <= 0:
        raise ValueError("Invalid saved Nu; no fallback or arbitrary UA multiplier")
    c = copy.deepcopy(old.c)
    c["saved_forced_Nu"] = nu
    model = SavedNusseltCycle(c, old.fluids)
    if not np.array_equal(model.initial_state(), old.initial_state()):
        raise ValueError("Cold initial coordinates changed")
    output.mkdir(parents=True, exist_ok=False)
    names = (Path(__file__).name, "Analyze_HeatDriveECC_CaloricCycle.py", "Reference_HeatDriveECC_CaloricCoupling.py",
             "Run_HeatDriveECC_CaloricCycle.py", "Reference_HeatDriveECC_CompensatedBS3.py",
             "Reference_HeatDriveECC_ConservativeTransport.py", "Run_HeatDriveECC_ConservativeTransport.py",
             "Audit_HeatDriveECC_SegmentedEvidence.py")
    record = {"schema": "heatdrive_ecc_saved_Nu_cold_control_v1", "collection_complete": False,
              "execution_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], encoding="utf-8").strip(),
              "source_sha256": {n: sha256(Path(__file__).with_name(n)) for n in names},
              "control_root": str(control_root), "control_execution_sha256": sha256(control_root/"caloric_cycle_execution.json"),
              "control_raw_sha256": baseline["raw"]["sha256"], "saved_configuration": str(cfg), "saved_configuration_sha256": sha256(cfg),
              "network_contract": c, "sole_physical_change": "bed forced Nu from legacy 3.66 to exact saved configuration values",
              "saved_Nu": nu, "legacy_Nu": {"SMA": 3.66, "SE": 3.66},
              "phase_rates_or_materials_changed": False, "production_state_loaded": False,
              "initial_state_is_independently_generated_cold": True, "checkpoint_saved": False,
              "production_recovery_allowed": False, "periodic_or_full_mechanism_qualified": False,
              "Table4_input_allowed": False, "local_observer_with_legacy_Nu_reused": False}
    write_json(output/"preflight.json", record)
    begin = time.perf_counter()
    try:
        with (output/"completed_stage_observations.jsonl").open("x", encoding="utf-8") as stream:
            def sink(row):
                stream.write(json.dumps(row, allow_nan=False)+"\n")
                stream.flush()
            profiles, result = simulate(model, 1, baseline["max_accepted_step_s"], baseline["rtol"], sink)
        if not np.array_equal(profiles["time_s"], clocks):
            raise ValueError("One-factor comparison clocks differ; no interpolation")
        states = profiles["diagnostic_coordinates_NOT_OP"]
        before = int(np.flatnonzero(clocks == 3.5)[0])
        comparisons = {}
        for key in ("Ta", "Tr", "xa", "xr", "bus_T", "buffer_T"):
            differences = [float(np.max(abs(model.unpack(a)[key]-old.unpack(b)[key]))) for a, b in zip(states, control)]
            comparisons["maximum_selected_"+key+"_difference"] = max(differences)
        comparisons["before_hot_blow_SE_min_xM"] = {"legacy": float(old.unpack(control[before])["xr"].min()),
                                                     "saved_Nu": float(model.unpack(states[before])["xr"].min())}
        raw = output/"selected_saved_Nu_control.npz"
        np.savez_compressed(raw, **profiles)
        with np.load(raw, allow_pickle=False) as saved:
            if not all(np.array_equal(saved[k], v) for k, v in profiles.items()):
                raise ValueError("Saved control arrays changed on readback")
        record.update(result, collection_complete=True, wall_seconds=time.perf_counter()-begin,
                      comparisons=comparisons, raw={"file": raw.name, "sha256": sha256(raw), "bytes": raw.stat().st_size})
        write_json(output/"saved_Nu_execution.json", record)
    except Exception:
        record.update(wall_seconds=time.perf_counter()-begin, error_traceback=traceback.format_exc())
        write_json(output/"FAILED_DO_NOT_RESUME.json", record)
        raise
    return {"output": str(output), "wall_seconds": record["wall_seconds"], "saved_Nu": nu,
            "comparisons": comparisons, "numerical_residuals": result["maximum_online_numerical_residuals"],
            "raw_bytes": raw.stat().st_size, "execution_sha256": sha256(output/"saved_Nu_execution.json"),
            "production_recovery_allowed": False}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--control-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    a = parser.parse_args()
    print(json.dumps(run(a.control_root.resolve(), a.output.resolve()), allow_nan=False))
