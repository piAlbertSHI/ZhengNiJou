"""Capture the first fatal inverse iterate, without changing its arithmetic.

This bounded replay is diagnostic only. It never exports a recovery state or
continues after the captured fatal inverse failure.
"""
import argparse
from dataclasses import replace
from pathlib import Path
import json
import time

import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Reference_HeatDriveECC_ConservativeTransport import Bed
from Reference_HeatDriveECC_EnthalpyTransport import EnthalpyBed
from Run_HeatDriveECC_ConservativeTransport import write_json
from Run_HeatDriveECC_EnthalpyTransport import load_inputs
from Run_HeatDriveECC_EnthalpyReference import adaptive_case


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--failed-root", type=Path, required=True)
    arguments = parser.parse_args()
    arguments.output.mkdir(parents=True, exist_ok=False)
    failure_path = arguments.failed_root/"FAILED_DO_NOT_RESUME.json"
    failure = json.loads(failure_path.read_text(encoding="utf-8"))
    control_root = Path("C:/tmp/se21_conservative_transport_r1_20261025")
    fluid_path = Path(failure["fluid_settings_execution_path"])
    control, fluids, contracts = load_inputs(control_root, fluid_path)
    material, rtol = failure["active_case"]["material"], failure["active_case"]["rtol"]
    eos = fluids[material]
    original = eos.invert
    captured = {}
    def witness(density, energy):
        try:
            return original(density, energy)
        except ValueError as error:
            if "failed to converge" in str(error):
                frame = error.__traceback__
                while frame is not None:
                    if frame.tb_frame.f_code.co_name == "invert":
                        values = frame.tb_frame.f_locals
                        for key in ("density", "energy", "temperature", "pressure", "dr", "du", "norm", "step_t", "step_p"):
                            captured[key] = np.asarray(values[key]).tolist()
                        captured["iterations"] = values["iteration"]+1
                    frame = frame.tb_next
            raise
    eos.invert = witness
    c = control["physical_contracts"][material]
    bed = EnthalpyBed(replace(Bed(**c["bed"]), slope_limiter="MC"), eos, 3.66, c["Dh_m"], c["surface_area_m2"])
    started = time.perf_counter()
    try:
        adaptive_case(bed, c["nominal_mass_flow_kg_s"], material, .1, rtol,
                      np.array([0., .01, .02, .025, .05, .06, .075, .1]))
    except ValueError as error:
        if not captured:
            raise
        record = {"schema": "heatdrive_ecc_fatal_inverse_diagnostic_v1", "material": material,
            "failed_packet": str(failure_path), "failed_packet_sha256": sha256(failure_path),
            "diagnostic_source_sha256": sha256(Path(__file__)),
            "arithmetic_or_physical_equations_modified": False,
            "original_inverse_failure": str(error), "failed_inverse_context": captured,
            "wall_seconds": time.perf_counter()-started, "production_recovery_allowed": False,
            "physical_contract": contracts[material]}
        path = arguments.output/"fatal_inverse_context.json"
        write_json(path, record)
        print(json.dumps({"captured_fatal_inverse": True, "output": str(path), "sha256": sha256(path),
                          "maximum_scaled_residual": max(captured["norm"])}))
    else:
        raise RuntimeError("Expected fatal failure was not reproduced; do not infer a repair")
