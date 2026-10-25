"""Dimensionless single-cell operator check, not a coupled-network simulation.

Assume constant common k, fixed laminar Nu, equal inlet/internal fluid T and
a uniform wall. For nonzero flow, consider only the directional branch outside
the native reversal blend. Compare with Q01's h*S*(Ts-Tf), not a fitted UA.
"""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256


NATIVE_SOURCES = {
    "pipe.ssc": "CC478BAB8A9B5DD6156ACE2239BF837FE0849843EF5BDBFE6F55C315343FAC3E",
    "pipe_convection.ssc": "366B69CB32DD3FC08D2323CF69EFA587FE0786869EC6A3AB2AEA2A6761F2369F"}


def normalized_flux(ntu, nu, delta_t):
    if not np.isfinite([ntu, nu, delta_t]).all() or ntu <= 0 or nu <= 0:
        raise ValueError("Require finite positive uncapped NTU and Nu")
    # Fluxes normalized by the reference UA (W/K); units of the result are K.
    convection = delta_t * (-np.expm1(-min(ntu, 30.))) / ntu
    conduction = delta_t / nu
    return {"reference_Q_over_UA_K": float(delta_t),
            "native_directional_Qconv_over_UA_K": float(convection),
            "native_Qcond_over_UA_K": float(conduction),
            "native_total_Q_over_UA_K": float(convection + conduction)}


def analyze(configuration, source_dir):
    sources = []
    for name, expected in NATIVE_SOURCES.items():
        path = source_dir / name
        digest = sha256(path)
        if digest != expected:
            raise ValueError("Recheck installed operator before using formula: " + str(path))
        sources.append({"path": str(path), "sha256": digest})
    rows = []
    with h5py.File(configuration, "r") as cfg:
        # Read saved scalar nominal coefficients only; do not infer fluid-table properties.
        for name, field in (("SMA", "options/branch/sma_pipe_Nu"),
                            ("SE", "options/branch/se_pipe_Nu")):
            nu = float(np.asarray(cfg[field]).item())
            rows.append({"material": name, "saved_Nu": nu,
                "small_NTU_native_to_reference_limit": 1 + 1 / nu,
                "uniform_zero_flow_native_Q_over_UA_per_K": 1 / nu,
                "zero_flow_reference_forced_law_applicability": "not asserted; separate natural/flow gating required",
                "cases": [{"uncapped_NTU": ntu, "wall_minus_fluid_K": delta,
                           **normalized_flux(ntu, nu, delta)}
                          for ntu in (.001, .01, .1, 1., 10., 30., 60.) for delta in (-1., 0., 1.)]})
    return {"schema": "heatdrive_ecc_uniform_pipe_operator_review_v1",
            "configuration_path": str(configuration), "configuration_sha256": sha256(configuration),
            "installed_operator_sources": sources, "cases": rows,
            "derivation": "NTU=UA/(abs(mdot)*cp); Qconv/UA=dT*(1-exp(-min(NTU,30)))/NTU; Qcond/UA=dT/Nu",
            "scope": "uniform-state, constant-property, fixed-laminar-Nu directional-branch algebra",
            "not_evaluated": ["reversal blend at small nonzero flow", "Re-dependent Nu",
                              "native wall vs actual solid temperature", "distributed transport/energy evolution",
                              "actual C20 heat-flux discrepancy", "performance-gap attribution"],
            "conclusion": "nominal Nu*k*S/Dh mask equality does not imply heat-operator identity",
            "simulation_executed": False, "material_or_transport_modified": False,
            "scientific_gates_modified": False, "production_recovery_allowed": False,
            "table4_reproduction_claim": False}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--configuration", type=Path, required=True)
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = analyze(args.configuration.resolve(), args.source_dir.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as stream:
        json.dump(result, stream, indent=2, allow_nan=False)
        stream.write("\n")
    print(json.dumps({"output": str(args.output), "sha256": sha256(args.output),
                      "scope": result["scope"], "simulation_executed": False}))
