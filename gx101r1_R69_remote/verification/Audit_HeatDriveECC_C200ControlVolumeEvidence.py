"""Audit measured C200 signals against the SMA-SE control-volume contract.

This is a read-only evidence audit. It never imports an operating point and
never treats a configured option or a static summary as a time-resolved port
measurement.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

import h5py
import numpy as np


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _matlab_text(dataset: h5py.Dataset) -> str:
    values = dataset[()].reshape(-1)
    return "".join(chr(int(value)) for value in values if int(value))


def _scalar(h5: h5py.File, path: str) -> float | None:
    if path not in h5:
        return None
    value = h5[path][()]
    try:
        return float(value.reshape(-1)[0])
    except (AttributeError, TypeError, ValueError):
        return None


def _presence(h5: h5py.File, paths: list[str]) -> dict[str, bool]:
    return {path: path in h5 for path in paths}


def _finite_presence(h5: h5py.File, paths: list[str]) -> dict[str, bool]:
    """Require a time-resolved numeric dataset to contain only finite values."""
    result: dict[str, bool] = {}
    for path in paths:
        if path not in h5 or not isinstance(h5[path], h5py.Dataset):
            result[path] = False
            continue
        dataset = h5[path]
        if dataset.dtype.kind in "SUO":
            result[path] = True
            continue
        finite = True
        if dataset.chunks:
            for selection in dataset.iter_chunks():
                if not np.isfinite(dataset[selection]).all():
                    finite = False
                    break
        else:
            finite = bool(np.isfinite(dataset[()]).all())
        result[path] = finite
    return result


def _status(present: dict[str, bool], *, configured_only: bool = False) -> str:
    if configured_only:
        return "configured_only"
    if all(present.values()):
        return "complete"
    if any(present.values()):
        return "partial"
    return "missing"


def _reported_flag(report_path: Path, label: str) -> bool | None:
    if not report_path.exists():
        return None
    pattern = re.compile(rf"^\s*{re.escape(label)}:\s*([01])\s*$", re.IGNORECASE)
    for line in report_path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = pattern.match(line)
        if match:
            return match.group(1) == "1"
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("result", type=Path, help="C200 physical_simscape_result.mat")
    parser.add_argument("contract", type=Path, help="control-volume contract JSON")
    parser.add_argument("--freeze-contract", type=Path)
    parser.add_argument("--validation-report", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    result_path = args.result.resolve()
    contract_path = args.contract.resolve()
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    freeze_contract = None
    freeze_contract_path = None
    if args.freeze_contract:
        freeze_contract_path = args.freeze_contract.resolve()
        freeze_contract = json.loads(freeze_contract_path.read_text(encoding="utf-8"))

    with h5py.File(result_path, "r") as h5:
        physical = h5["physical"]
        sample_count = int(physical["time_s"].shape[-1])
        buffer_required = _presence(h5, [
            "physical/buffer_inventory_names",
        ]) | _finite_presence(h5, [
            "physical/buffer_inventory_mass_kg",
            "physical/buffer_inventory_internal_energy_J",
            "physical/buffer_port_mdot_A_kgps",
            "physical/buffer_port_mdot_B_kgps",
        ])
        pipe_required = _presence(h5, [
            "physical/pipe_inventory_names",
            "physical/manifold_inventory_names",
        ]) | _finite_presence(h5, [
            "physical/pipe_inventory_mass_kg",
            "physical/pipe_inventory_internal_energy_J",
            "physical/manifold_inventory_mass_kg",
            "physical/manifold_inventory_internal_energy_J",
            "physical/pipe_port_mdot_A_kgps",
            "physical/pipe_port_mdot_B_kgps",
            "physical/pipe_port_enthalpy_A_W",
            "physical/pipe_port_enthalpy_B_W",
        ])
        pump_required = _finite_presence(h5, [
            "physical/pump_pressure_port_A_MPa",
            "physical/pump_pressure_port_B_MPa",
        ])
        evidence = {
            "CHEX_sensor_and_boundary": {
                "status": _status(_presence(h5, [
                    "physical/CHEX_T_K",
                    "physical/Q_CHEX_reservoir_to_hx_W",
                ])),
                "time_resolved_signals": _presence(h5, [
                    "physical/CHEX_T_K",
                    "physical/Q_CHEX_reservoir_to_hx_W",
                ]),
                "finite_mass_authoritative": bool(_scalar(
                    h5, "options/validation/cold_boundary_audit/finite_mass_authoritative"
                ) or 0),
                "boundary_mode": _matlab_text(
                    h5["options/system/cold_boundary_mode"]
                ),
            },
            "SHEX_fluid": {
                "status": _status(_presence(h5, [
                    "physical/SHEX_T_K",
                    "physical/SHEX_buffer_T_K",
                    "physical/Q_SHEX_source_to_sink_W",
                ]) | _finite_presence(h5, [
                    "physical/Q_SHEX_fluid_W",
                    "physical/SHEX_mdot_kgps",
                ])),
                "time_resolved_signals": _presence(h5, [
                    "physical/SHEX_T_K",
                    "physical/SHEX_buffer_T_K",
                    "physical/Q_SHEX_source_to_sink_W",
                    "physical/Q_SHEX_fluid_W",
                    "physical/SHEX_mdot_kgps",
                ]),
                "configured_signals": _presence(h5, [
                    "options/output/Q_shex_boundary_W",
                    "options/output/SMA_SHEX_mdot",
                ]),
            },
            "HHEX_fluid": {
                "status": _status(_presence(h5, [
                    "physical/HHEX_T_K",
                    "physical/HHEX_buffer_T_K",
                ]) | _finite_presence(h5, [
                    "physical/Q_HHEX_fluid_W",
                    "physical/HHEX_mdot_SE_kgps",
                    "physical/HHEX_mdot_SMA_kgps",
                ])),
                "time_resolved_signals": _presence(h5, [
                    "physical/HHEX_T_K",
                    "physical/HHEX_buffer_T_K",
                    "physical/Q_HHEX_fluid_W",
                    "physical/HHEX_mdot_SE_kgps",
                    "physical/HHEX_mdot_SMA_kgps",
                ]),
                "configured_signals": _presence(h5, [
                    "options/output/Q_the_sma_boundary_W",
                    "options/output/Q_the_se_boundary_W",
                ]),
            },
            "CHEX_fluid": {
                "status": _status(_presence(h5, [
                    "physical/CHEX_T_K",
                ]) | _finite_presence(h5, [
                    "physical/Q_CHEX_fluid_W",
                    "physical/CHEX_mdot_SE_kgps",
                ])),
                "time_resolved_signals": _presence(h5, [
                    "physical/CHEX_T_K",
                    "physical/Q_CHEX_fluid_W",
                    "physical/CHEX_mdot_SE_kgps",
                ]),
                "configured_signals": _presence(h5, [
                    "options/output/SE_CHEX_Q_21",
                    "options/output/SE_CHEX_mdot",
                ]),
            },
            "SMA_solid": {
                "status": _status(_presence(h5, [
                    "physical/SMA_T_21_K",
                    "physical/xM_SMA_21",
                    "physical/Q_SMA_constitutive_21_W",
                    "physical/Q_SMA_hold_pipe_to_solid_21_W",
                    "physical/Q_SMA_cooldown_pipe_to_solid_21_W",
                ])),
                "time_resolved_signals": _presence(h5, [
                    "physical/SMA_T_21_K",
                    "physical/xM_SMA_21",
                    "physical/Q_SMA_constitutive_21_W",
                    "physical/Q_SMA_hold_pipe_to_solid_21_W",
                    "physical/Q_SMA_cooldown_pipe_to_solid_21_W",
                ]),
            },
            "SE_solid": {
                "status": _status(_presence(h5, [
                    "physical/SE_T_21_K",
                    "physical/xM_SE_21",
                    "physical/Q_SE_constitutive_21_W",
                    "physical/Q_SE_hold_pipe_to_solid_21_W",
                    "physical/Q_SE_cooldown_pipe_to_solid_21_W",
                ])),
                "time_resolved_signals": _presence(h5, [
                    "physical/SE_T_21_K",
                    "physical/xM_SE_21",
                    "physical/Q_SE_constitutive_21_W",
                    "physical/Q_SE_hold_pipe_to_solid_21_W",
                    "physical/Q_SE_cooldown_pipe_to_solid_21_W",
                ]),
            },
            "buffers": {
                "status": _status(buffer_required),
                "time_resolved_signals": _presence(h5, [
                    "physical/SHEX_buffer_T_K",
                    "physical/HHEX_buffer_T_K",
                    "physical/CHEX_buffer_T_K",
                    "physical/SMA_HHEX_buffer_T_K",
                    "physical/buffer_inventory_names",
                    "physical/buffer_inventory_mass_kg",
                    "physical/buffer_inventory_internal_energy_J",
                    "physical/buffer_port_mdot_A_kgps",
                    "physical/buffer_port_mdot_B_kgps",
                ]),
                "missing_required_state": [] if all(buffer_required.values()) else [
                    "buffer inventory/port mass-flow ledger",
                ],
            },
            "pipes_and_manifolds": {
                "status": _status(pipe_required),
                "time_resolved_signals": _presence(h5, [
                    "physical/pressure_command_SMA_MPa",
                    "physical/pressure_command_SE_MPa",
                    "physical/probes",
                    "physical/pipe_inventory_names",
                    "physical/pipe_inventory_mass_kg",
                    "physical/pipe_inventory_internal_energy_J",
                    "physical/manifold_inventory_names",
                    "physical/manifold_inventory_mass_kg",
                    "physical/manifold_inventory_internal_energy_J",
                    "physical/pipe_port_mdot_A_kgps",
                    "physical/pipe_port_mdot_B_kgps",
                    "physical/pipe_port_enthalpy_A_W",
                    "physical/pipe_port_enthalpy_B_W",
                ]),
                "missing_required_state": [] if all(pipe_required.values()) else [
                    "pipe/manifold port mass/enthalpy ledger",
                    "pressure-volume work or wall storage",
                ],
            },
            "pumps": {
                "status": _status(_presence(h5, [
                    "physical/pump_power_SMA_W",
                    "physical/pump_power_SE_W",
                    "physical/mdot_SMA_kgps",
                    "physical/mdot_SE_stage2_in_kgps",
                    "physical/pressure_command_SMA_MPa",
                    "physical/pressure_command_SE_MPa",
                ]) | pump_required),
                "time_resolved_signals": _presence(h5, [
                    "physical/pump_power_SMA_W",
                    "physical/pump_power_SE_W",
                    "physical/mdot_SMA_kgps",
                    "physical/mdot_SE_stage2_in_kgps",
                    "physical/pressure_command_SMA_MPa",
                    "physical/pressure_command_SE_MPa",
                    "physical/pump_pressure_port_A_MPa",
                    "physical/pump_pressure_port_B_MPa",
                ]),
                "missing_required_state": [] if all(pump_required.values()) else [
                    "pump inlet/outlet pressure ports for hydraulic power cross-check",
                ],
            },
        }

        mat_summary_periodic = bool(_scalar(
            h5, "summary/performance/periodic_steady_state"
        ) or 0)
        performance = {
            "qian_window_cycles": _scalar(h5, "summary/performance/qian_window_cycles"),
            "qian_window_start_s": _scalar(h5, "summary/performance/qian_window_start_s"),
            "qian_window_end_s": _scalar(h5, "summary/performance/qian_window_end_s"),
            "eq9_lift_K": _scalar(h5, "summary/performance/temperature_lift_eq9_K"),
            "eq10_SCP_W_per_g": _scalar(h5, "summary/performance/specific_cooling_eq10_W_per_g"),
            "eq10_sensor_consistency_pass": bool(_scalar(
                h5, "summary/performance/eq10_sensor_consistency_pass"
            ) or 0),
            "mat_summary_periodic_steady_state": mat_summary_periodic,
            "strict_table4_pass": bool(_scalar(
                h5, "summary/quantitative_literature_reproduction_pass"
            ) or 0),
        }
        provenance = {
            "authority": _matlab_text(h5["provenance/authority"]),
            "model_name": _matlab_text(h5["provenance/model_name"]),
            "continuous_full_cycle_simulation": bool(_scalar(
                h5, "provenance/continuous_full_cycle_simulation"
            ) or 0),
            "legacy_surrogate_used_for_results": bool(_scalar(
                h5, "provenance/legacy_surrogate_used_for_results"
            ) or 0),
        }

    complete_required = {
        name: row["status"] == "complete"
        for name, row in evidence.items()
        if name not in {"buffers", "pipes_and_manifolds"}
    }
    complete_required.update({
        "buffers": evidence["buffers"]["status"] == "complete",
        "pipes_and_manifolds": evidence["pipes_and_manifolds"]["status"] == "complete",
    })
    result = {
        "schema": "heatdrive_ecc_c200_control_volume_evidence_v1",
        "result_path": str(result_path),
        "result_sha256": _sha256(result_path),
        "contract_path": str(contract_path),
        "contract_sha256": _sha256(contract_path),
        "contract_schema": contract.get("schema"),
        "freeze_contract_path": (
            str(freeze_contract_path) if freeze_contract_path else None
        ),
        "freeze_contract_sha256": (
            _sha256(freeze_contract_path) if freeze_contract_path else None
        ),
        "time_resolved_sample_count": sample_count,
        "control_volume_evidence": evidence,
        "performance_window": performance,
        "periodic_steady_state_evidence": {
            "mat_summary_flag": performance["mat_summary_periodic_steady_state"],
            "validation_report_flag": _reported_flag(
                args.validation_report.resolve(), "periodic steady state"
            ) if args.validation_report else None,
            "freeze_contract_flag": (
                bool(freeze_contract.get("periodic_steady_state"))
                if freeze_contract is not None else None
            ),
        },
        "provenance": provenance,
        "all_required_control_volume_observations_complete": all(complete_required.values()),
        "missing_for_outer_solve": sorted(
            name for name, complete in complete_required.items() if not complete
        ),
        "outer_solve_eligible": False,
        "paired_table4_eligible": False,
        "claim_boundary": (
            "Measured-signal inventory only. Static configuration and local solid "
            "balances do not prove complete device first-law closure."
        ),
    }
    flags = [
        result["periodic_steady_state_evidence"][key]
        for key in ("mat_summary_flag", "validation_report_flag", "freeze_contract_flag")
        if result["periodic_steady_state_evidence"][key] is not None
    ]
    result["periodic_steady_state_evidence"]["conflict_detected"] = len(set(flags)) > 1
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
