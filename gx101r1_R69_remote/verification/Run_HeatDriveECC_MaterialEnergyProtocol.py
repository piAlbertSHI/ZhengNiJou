"""Small independent energy-equation test; never a cold/system seed or OP.

The phase and strain paths are prescribed synthetic inputs, not an identified
finite-rate law. Check first-law storage against independent Radau/DOP853 runs.
Do not promote this numerical check to a material or system validation gate.
"""
import argparse
from dataclasses import asdict
import json
from pathlib import Path
import platform
import subprocess
import traceback

import numpy as np
import scipy
from scipy.integrate import solve_ivp
from scipy.special import erfc

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Reference_HeatDriveECC_MaterialThermodynamics import MaterialThermodynamics
from Run_HeatDriveECC_ConservativeTransport import write_json


def inputs(t):
    e = .035+.004*np.sin(np.pi*t/2)
    ed = .002*np.pi*np.cos(np.pi*t/2)
    x = .45+.2*np.sin(np.pi*t/4)
    xd = .05*np.pi*np.cos(np.pi*t/4)
    heat = 2*np.cos(np.pi*t/4)
    return e, ed, x, xd, heat


def run(output):
    output.mkdir(parents=True, exist_ok=False)
    source_pdf = Path("C:/tmp/se21_material_path_sources_20261026/mandolino_2021_hybrid_single_crystal.pdf")
    expected = "613B8BE866A7482E537256F587B31DE309288D0B2DFE40E603CA8538DFF5C8D8"
    if sha256(source_pdf).upper() != expected:
        raise ValueError("Material equation source PDF does not match the read source")
    source_names = (Path(__file__).name, "Reference_HeatDriveECC_MaterialThermodynamics.py",
                    "Run_HeatDriveECC_ConservativeTransport.py", "Audit_HeatDriveECC_SegmentedEvidence.py")
    m = MaterialThermodynamics(35e9, 25e9, .03, 6500., 500., 180e6, 320., 7.45e6)
    volume = 1e-6
    clocks = np.linspace(0., 8., 161)
    record = {"schema": "heatdrive_ecc_independent_material_energy_protocol_v1", "collection_complete": False,
              "execution_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], encoding="utf-8").strip(),
              "source_sha256": {n: sha256(Path(__file__).with_name(n)) for n in source_names},
              "runtime": {"python": platform.python_version(), "numpy": np.__version__, "scipy": scipy.__version__},
              "equation_source": {"doi": "10.1109/LRA.2021.3067254", "PDF_pages": [2, 3],
                                  "equations": [1, 9, 11, 12, 13, 14, 15, 16, 17],
                                  "path": str(source_pdf), "sha256": expected},
              "synthetic_material_inputs": asdict(m), "synthetic_volume_m3": volume,
              "initial_temperature_K": 330., "forcing_source": "inputs(t), prescribed strain and phase, NOT kinetics",
              "potential_derivation": "F=elastic+(x-1)*Gamma(sigmaMW)+rho*cp*(T-Tref-T*log(T/Tref)); S=-F_T; U=F+T*S",
              "phase_clipping_or_reset": False, "Q01_material_identified": False,
              "finite_rate_phase_law_implemented": False, "system_model_run": False,
              "physical_validation_claim": False, "production_recovery_allowed": False,
              "Table4_input_allowed": False, "checkpoint_saved": False, "cases": []}
    write_json(output/"preflight.json", record)
    initial = m.evaluate(330., inputs(0.)[0], inputs(0.)[2])["internal_energy_J_m3"]*volume

    def rhs(t, y):
        e, ed, x, xd, heat = inputs(t)
        s = m.evaluate(y[0], e, x)
        return [m.temperature_rate(y[0], e, x, xd, heat, volume), heat, volume*s["stress_Pa"]*ed]

    raw = {}
    try:
        for method, rt, at, step in (("Radau", 1e-9, 1e-10, .03), ("DOP853", 1e-12, 1e-12, .01)):
            sol = solve_ivp(rhs, (0., 8.), [330., 0., 0.], method=method, t_eval=clocks,
                            rtol=rt, atol=at, max_step=step)
            if not sol.success or not np.array_equal(sol.t, clocks) or not np.isfinite(sol.y).all():
                raise ValueError("Incomplete equation protocol: "+sol.message)
            e, _, x, _, _ = inputs(clocks)
            s = m.evaluate(sol.y[0], e, x)
            residual = volume*s["internal_energy_J_m3"]-initial-sol.y[1]-sol.y[2]
            if np.max(abs(residual)) > 1e-6:
                raise ValueError("First-law equation protocol exceeds numerical 1e-6 J readback tolerance")
            raw[method] = sol.y
            record["cases"].append({"method": method, "RHS_calls": sol.nfev, "final_state": sol.y[:, -1].tolist(),
                                    "maximum_energy_residual_J": float(np.max(abs(residual))),
                                    "temperature_range_K": [float(sol.y[0].min()), float(sol.y[0].max())],
                                    "effective_capacity_min_J_m3K": float(s["effective_capacity_J_m3K"].min())})
        difference = float(np.max(abs(raw["Radau"][0]-raw["DOP853"][0])))
        if difference > 1e-6:
            raise ValueError("Independent solvers differ by more than the numerical 1e-6 K tolerance")
        # A counterexample to literal transfer, not a correction or production law.
        # Springer doi:10.1007/s11665-020-04668-2 prints pMA's erfc branch at s<cm.
        # Above both critical stresses, both printed rates are 1/tau for EA=EM.
        tau = .1
        stress, ca, cm, t, v, young = 1e9, 200e6, 100e6, 320., 3e-26, 30e9
        p_am = erfc(.910*np.sqrt(v/(2*young*1.380649e-23*t))*(ca-stress))/tau if stress < ca else 1/tau
        p_ma = erfc(-.910*np.sqrt(v/(2*young*1.380649e-23*t))*(cm-stress))/tau if stress < cm else 1/tau
        record["literal_2020_equation_counterexample"] = {
            "source_url": "https://link.springer.com/article/10.1007/s11665-020-04668-2",
            "source_scope": "HTML Kinetic Transformation / MAS, no source-code verification or erratum established",
            "synthetic_input_SI": {"stress_Pa": stress, "critical_A_Pa": ca, "critical_M_Pa": cm,
                                   "T_K": t, "activation_volume_m3": v, "EA_equals_EM_Pa": young, "tau_s": tau},
            "literal_pAM_per_s": float(p_am), "literal_pMA_per_s": float(p_ma),
            "literal_frozen_equilibrium_xM": float(p_am/(p_am+p_ma)),
            "decision": "Do not transfer the printed approximation or silently reverse its branch inequality",
            "author_model_error_proven": False}
        # Conditional algebra only: Q01 has unequal CA/CM and no established MW
        # midpoint mapping. This range is NOT a mandatory reproduction gate.
        low, high = [.03*c*318.15/6500. for c in (7.3e6, 7.6e6)]
        record["conditional_Q01_equal_modulus_comparison"] = {
            "assumptions": "EA=EM, zero-stress Maxwell T=midpoint(40,50)degC, common slope within [7.3,7.6]MPa/K",
            "these_assumptions_identified_from_Q01": False,
            "implied_chemical_term_J_kg_range": [low, high], "Q01_constant_Delta_h_J_kg": 10000.,
            "relative_difference_range": [low/10000.-1, high/10000.-1],
            "interpretation": "Different energy closures; not a measured latent-heat correction or explanation of the SCP deficit",
            "mandatory_scientific_gate": False}
        path = output/"material_energy_protocol.npz"
        np.savez_compressed(path, time_s=clocks, **raw)
        with np.load(path, allow_pickle=False) as saved:
            if not all(np.array_equal(saved[k], a) for k, a in {"time_s": clocks, **raw}.items()):
                raise ValueError("Saved material protocol differs from numerical arrays")
        record.update(collection_complete=True, maximum_cross_solver_temperature_difference_K=difference,
                      raw={"file": path.name, "sha256": sha256(path), "bytes": path.stat().st_size})
        write_json(output/"execution.json", record)
    except Exception as error:
        record["error"] = {"type": type(error).__name__, "message": str(error), "traceback": traceback.format_exc()}
        write_json(output/"execution.json", record)
        raise
    return {"collection_complete": True, "output": str(output), "execution_sha256": sha256(output/"execution.json"),
            "maximum_cross_solver_temperature_difference_K": difference,
            "maximum_energy_residual_J": max(c["maximum_energy_residual_J"] for c in record["cases"]),
            "Q01_material_identified": False, "production_recovery_allowed": False}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    print(json.dumps(run(parser.parse_args().output), ensure_ascii=False, allow_nan=False))
