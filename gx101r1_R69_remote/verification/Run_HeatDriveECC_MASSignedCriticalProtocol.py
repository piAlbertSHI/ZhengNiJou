"""Numerical MAS temperature protocol through sigma_M=0, never a Q01 seed.

Q04's reported E/CA/CM/As/Ms are equation-test inputs. V values are explicitly
synthetic numerical probes; both conflicting reported tau values are retained.
No parameter calibration, system sensitivity, work/COP or validation claim.
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
from scipy.integrate import solve_ivp

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Reference_HeatDriveECC_TwoWayPhase import SingleCrystalMAS, two_way_rate
from Run_HeatDriveECC_ConservativeTransport import write_json


def forcing(clock):
    t = np.asarray(clock)
    # A prescribed numerical input, not a heat-driven system trajectory.
    temperature = 262.25+7.75*np.cos(np.pi*t/4.)
    critical_a = 7.60e6*(temperature-254.)
    critical_m = 7.34e6*(temperature-256.)
    return temperature, critical_a, critical_m


def run_case(volume, tau, method, clocks):
    kernel = SingleCrystalMAS(30e9, 30e9, volume, tau)
    def rhs(clock, phase):
        t, a, m = forcing(clock)
        plus, minus = kernel.coefficients(t, 0., a, m)
        return two_way_rate(phase, plus, minus)
    solution = solve_ivp(rhs, (0., 8.), [0.], method=method, t_eval=clocks,
                         rtol=1e-10 if method == "DOP853" else 1e-8,
                         atol=1e-12 if method == "DOP853" else 1e-10,
                         max_step=.01 if method == "DOP853" else .02)
    if (not solution.success or solution.t[-1] != 8. or not np.array_equal(solution.t, clocks)
            or not np.isfinite(solution.y).all() or solution.y.min() < -1e-10 or solution.y.max() > 1+1e-10):
        raise RuntimeError("Incomplete or inadmissible numerical material protocol: "+solution.message)
    t, a, m = forcing(clocks)
    plus, minus = kernel.coefficients(t, np.zeros_like(t), a, m)
    return solution.y[0], plus, minus, solution.nfev


def run(output):
    output.mkdir(parents=True, exist_ok=False)
    files = [Path(__file__)] + [Path(__file__).with_name(name) for name in (
        "Reference_HeatDriveECC_TwoWayPhase.py", "Reference_HeatDriveECC_CaloricCoupling.py",
        "Reference_HeatDriveECC_ConservativeTransport.py", "Run_HeatDriveECC_ConservativeTransport.py",
        "Audit_HeatDriveECC_SegmentedEvidence.py")]
    record = {"schema": "heatdrive_ecc_MAS_signed_critical_numerical_protocol_v1", "collection_complete": False,
        "execution_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], encoding="utf-8").strip(),
        "source_sha256": {p.name: sha256(p) for p in files},
        "runtime": {"python": platform.python_version(), "scipy": scipy.__version__, "numpy": np.__version__},
        "equation_source": "Qian2017 PDF4 Eqs8-13; Qian2018 PDF4 Eqs5-6",
        "source_E_Pa": 30e9, "source_C_A_Pa_K": 7.60e6, "source_C_M_Pa_K": 7.34e6,
        "source_T_As_K": 254., "source_T_Ms_K": 256.,
        "input_T_K": "262.25+7.75*cos(pi*t/4), t in [0,8] s", "input_stress_Pa": 0.,
        "synthetic_activation_volume_probes_m3": [1e-26, 3e-26],
        "tau_values_s": [.01, .1], "tau_interpretation": "Q04 Table1/body conflict, not resolved or imported to Q01",
        "initial_phase": 0., "initial_state_is_not_claimed_equilibrium": True,
        "phase_clipping_or_reset": False, "checkpoint_saved": False, "production_state_loaded": False,
        "Q01_material_identified": False, "physical_validation_claim": False,
        "system_sensitivity_or_Table4_input": False, "production_recovery_allowed": False,
        "A_nonpositive_branch_implemented": False,
        "cases": []}
    write_json(output/"preflight.json", record)
    begin = time.perf_counter()
    try:
        crossing = 4/np.pi*np.arccos((256.-262.25)/7.75)
        clocks = np.unique(np.r_[np.linspace(0., 8., 161), crossing, 8-crossing])
        t, a, m = forcing(clocks)
        phases, references, forward, reverse = [], [], [], []
        for volume in (1e-26, 3e-26):
            for tau in (.01, .1):
                phase, plus, minus, nf = run_case(volume, tau, "Radau", clocks)
                reference, _, _, nr = run_case(volume, tau, "DOP853", clocks)
                phases.append(phase)
                references.append(reference)
                forward.append(plus)
                reverse.append(minus)
                kernel = SingleCrystalMAS(30e9, 30e9, volume, tau)
                # At sigma_M=sigma=0, pMA=1/tau exactly, independently of V.
                actual = float(kernel.coefficients(256., 0., 15.2e6, 0.)[1])
                if abs(actual-1/tau) > 1e-10:
                    raise ValueError("Wrong zero-crossing coefficient identity")
                difference = float(np.max(abs(phase-reference)))
                if difference > 1e-6:
                    raise ValueError("Independent numerical integrators disagree by more than 1e-6 phase fraction")
                record["cases"].append({"activation_volume_m3": volume, "relaxation_s": tau,
                    "Radau_RHS_calls": nf, "DOP853_RHS_calls": nr,
                    "maximum_selected_phase_difference": difference,
                    "phase_range": [float(phase.min()), float(phase.max())],
                    "pMA_at_exact_zero_critical_per_s": actual,
                    "finite_across_signed_M_critical": bool(np.isfinite(minus).all())})
        raw = output/"signed_M_critical_protocol.npz"
        np.savez_compressed(raw, time_s=clocks, temperature_K=t, sigma_A_Pa=a, sigma_M_Pa=m,
                            phase_Radau=np.asarray(phases), phase_DOP853=np.asarray(references),
                            pAM_per_s=np.asarray(forward), pMA_per_s=np.asarray(reverse))
        record.update(collection_complete=True, wall_seconds=time.perf_counter()-begin,
            raw={"file": raw.name, "sha256": sha256(raw), "bytes": raw.stat().st_size},
            sigma_M_range_Pa=[float(m.min()), float(m.max())], sigma_A_min_Pa=float(a.min()),
            exact_zero_crossing_times_s=sorted([float(crossing), float(8-crossing)]),
            numerical_cross_solver_phase_tolerance=1e-6,
            scientific_gate_thresholds_changed=False,
            scope="numerical operator-domain verification only, no claim for cold Q01 SMA with sigma_A<=0")
        write_json(output/"MAS_protocol_execution.json", record)
        print(json.dumps({"output": str(output), "collection_complete": True, "cases": len(record["cases"]),
            "maximum_phase_numeric_difference": max(r["maximum_selected_phase_difference"] for r in record["cases"]),
            "raw_bytes": raw.stat().st_size, "wall_seconds": record["wall_seconds"],
            "execution_sha256": sha256(output/"MAS_protocol_execution.json"), "Q01_material_identified": False}))
    except Exception:
        record.update(error_traceback=traceback.format_exc(), wall_seconds=time.perf_counter()-begin)
        write_json(output/"FAILED_NOT_A_RECOVERY_SOURCE.json", record)
        raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    run(parser.parse_args().output.resolve())
