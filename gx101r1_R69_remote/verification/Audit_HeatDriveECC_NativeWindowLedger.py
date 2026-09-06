"""Versioned native component ledger, separate from all legacy runtime fields.

Integrals use retained native samples including both endpoints. Numerical
bookkeeping checks do not grant energy closure, periodicity or recovery status.
"""
import argparse
import copy
import json
from collections import Counter
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_NativeAccumulation import energy_tables, path_integral, ENERGY_ATOL_J_KG
from Audit_HeatDriveECC_NativeInventoryCatalog import audit_block, convert
from Audit_HeatDriveECC_SegmentedEvidence import audit as audit_split, load_traces, sha256
from Audit_HeatDriveECC_TLDomainInventory import reconstruct, DENSITY_ATOL_KG_M3


SCHEMA = "heatdrive_ecc_native_window_ledger_v1"
EXPECTED_COUNTS = {"Pipe (TL)": 67, "Tank (TL)": 4,
                   "Constant Volume Chamber (TL)": 2, "Thermal Mass": 46}


def validate_grid(time, start, stop, dt):
    time = np.asarray(time)
    if not np.isfinite([start, stop, dt]).all() or dt <= 0 or stop <= start:
        raise ValueError("Require a positive finite window and fixed step")
    steps = (stop - start) / dt
    tolerance = 16 * np.spacing(max(abs(start), abs(stop), 1.0))
    if (time.ndim != 1 or time.size != round(steps) + 1 or not np.isfinite(time).all()
            or abs(steps - round(steps)) * dt > tolerance
            or abs(time[0] - start) > tolerance or abs(time[-1] - stop) > tolerance
            or np.any(abs(np.diff(time) - dt) > tolerance)):
        raise ValueError("Missing/nonuniform native samples or wrong window endpoints")


def evaluate_component(block, table=None, nominal_mass=None):
    # Reuse the established unit, geometry-mode and matching-grid validation.
    common = audit_block(block)
    kind = block["mask_type"]
    leaves = {r["name"]: r for r in block["leaf_variables"]}
    time = np.asarray(next(iter(leaves.values()))["time_s"], dtype=float)

    def series(name, unit):
        leaf = leaves[name]
        return convert(leaf["values"], leaf["unit"], unit)

    row = dict(block_path=block["block_path"], mask_type=kind,
               sample_count=int(time.size), start_s=float(time[0]), stop_s=float(time[-1]))
    if kind == "Thermal Mass":
        temp = series("T", "K")
        accumulation = common["sensible_energy_change_J"]
        flow = series("Q", "W")
        row.update(equation_basis="fixed thermal mass sensible energy; latent heat external",
                   temperature_start_K=float(temp[0]), temperature_end_K=float(temp[-1]),
                   energy_equation_accumulation_J=accumulation,
                   energy_endpoint_change_J=accumulation,
                   energy_flow_integral_J=path_integral(flow, time),
                   energy_flow_absolute_integral_J=path_integral(abs(flow), time))
    else:
        if table is None:
            raise ValueError("Missing actual fluid-domain table")
        temp, pressure = series("T_I", "K"), series("p_I", "Pa")
        u, rho, h = series("u_I", "J/kg"), series("rho_I", "kg/m^3"), series("h_I", "J/kg")
        coords = np.column_stack((temp, pressure))
        density_error = float(np.max(abs(table["rho"](coords) - rho)))
        energy_error = float(np.max(abs(table["u"](coords) - u)))
        if density_error > DENSITY_ATOL_KG_M3 or energy_error > ENERGY_ATOL_J_KG:
            raise ValueError("Native values differ from the assigned property table")
        if np.any(rho <= 0) or np.any(temp <= 0):
            raise ValueError("Nonphysical native temperature or density")
        cp, alpha, beta = (table[name](coords) for name in ("cp", "alpha", "beta"))
        ports = common["ports"]
        mass_flows = [series("mdot_" + port, "kg/s") for port in ports]
        energy_flows = [series("Phi_" + port, "W") for port in ports] + [series("Q_H", "W")]
        mass_net = sum(mass_flows, np.zeros_like(time))
        energy_net = sum(energy_flows, np.zeros_like(time))
        pdV = 0.0
        if kind == "Pipe (TL)":
            if nominal_mass is None or not np.isfinite(nominal_mass) or nominal_mass <= 0:
                raise ValueError("Quasisteady pipe needs a positive, fixed nominal mass")
            mass = np.full_like(time, nominal_mass)
            accumulation = nominal_mass * float(u[-1] - u[0])
            mass_accumulation = 0.0
            basis = "M=rho_nominal*V; integral(M du_I); dynamic_compressibility=false"
        elif kind == "Tank (TL)":
            if np.ptp(pressure) > 1e-6:
                raise ValueError("Only the verified constant-pressure tank is supported")
            mass, volume = series("mass", "kg"), series("volume", "m^3")
            if np.any(volume <= 0):
                raise ValueError("Nonpositive tank volume")
            accumulation = path_integral(mass * cp, temp) + path_integral(h, mass)
            mass_accumulation = float(mass[-1] - mass[0])
            pdV = path_integral(pressure, volume)
            basis = "integral(M cp dT + h dM); constant-pressure native Tank (TL)"
            row.update(volume_start_m3=float(volume[0]), volume_end_m3=float(volume[-1]))
        else:
            parameter = block["mask_parameters"]["volume"]
            volume = float(convert(parameter["value"], parameter["unit"], "m^3"))
            if volume <= 0:
                raise ValueError("Nonpositive chamber volume")
            mass = rho * volume
            accumulation = (path_integral((rho * h / beta - temp * alpha) * volume, pressure)
                            + path_integral((cp - h * alpha) * rho * volume, temp))
            mass_accumulation = (path_integral(mass / beta, pressure)
                                 - path_integral(alpha * mass, temp))
            basis = "integral(dUdp dp + dUdT dT); compressible chamber table coefficients"
        if np.any(mass <= 0):
            raise ValueError("Nonpositive native mass")
        row.update(equation_basis=basis, temperature_start_K=float(temp[0]), temperature_end_K=float(temp[-1]),
                   pressure_start_Pa=float(pressure[0]), pressure_end_Pa=float(pressure[-1]),
                   mass_start_kg=float(mass[0]), mass_end_kg=float(mass[-1]),
                   energy_start_J=float(mass[0] * u[0]), energy_end_J=float(mass[-1] * u[-1]),
                   mass_endpoint_change_kg=float(mass[-1] - mass[0]),
                   mass_equation_accumulation_kg=mass_accumulation,
                   mass_flow_integral_kg=path_integral(mass_net, time),
                   mass_flow_absolute_integral_kg=sum(path_integral(abs(v), time) for v in mass_flows),
                   energy_endpoint_change_J=float(mass[-1] * u[-1] - mass[0] * u[0]),
                   energy_enthalpy_endpoint_change_J=float(mass[-1] * h[-1] - mass[0] * h[0]),
                   pressure_volume_work_J=pdV, energy_equation_accumulation_J=accumulation,
                   energy_flow_integral_J=path_integral(energy_net, time),
                   energy_flow_absolute_integral_J=sum(path_integral(abs(v), time) for v in energy_flows),
                   native_density_lookup_max_abs_error_kg_m3=density_error,
                   native_energy_lookup_max_abs_error_J_kg=energy_error)
        row["mass_residual_kg"] = row["mass_flow_integral_kg"] - mass_accumulation
    row["energy_residual_J"] = row["energy_flow_integral_J"] - row["energy_equation_accumulation_J"]
    row["energy_closure_verified"] = False
    row["mass_closure_verified"] = False
    return row


class NativeWindowLedger:
    def __init__(self, topology, probe, metadata):
        # Validate frozen source hashes and model modes without relabeling new
        # trace data as a historical probe or inheriting its scientific status.
        probe = copy.deepcopy(probe)
        basis = reconstruct(topology, probe, metadata)
        if not basis["nominal_pipe_storage_reconstruction_pass"]:
            raise ValueError("The source metadata reconstruction failed")
        self.templates = {b["block_path"]: b for b in probe["storage_blocks"]}
        if dict(Counter(b["mask_type"] for b in self.templates.values())) != EXPECTED_COUNTS:
            raise ValueError("Unexpected storage inventory")
        self.keys = {p + "::" + leaf["name"] for p, b in self.templates.items() for leaf in b["leaf_variables"]}
        self.basis = {r["block_path"]: r for r in basis["components"]}
        self.tables = {r["block_path"]: energy_tables(r["parameters"]) for r in topology["settings_tables"]}
        self.source = {key: probe[key] for key in ("source_result_sha256", "source_checkpoint_sha256")}

    def evaluate(self, traces, start, stop, dt):
        if set(traces) != self.keys:
            raise ValueError("Window native inventory differs from frozen model metadata")
        rows = []
        for path, template in self.templates.items():
            block = {k: v for k, v in template.items() if k != "leaf_variables"}
            leaves = []
            for old_leaf in template["leaf_variables"]:
                name = old_leaf["name"]
                trace = traces[path + "::" + name]
                validate_grid(trace["time"], start, stop, dt)
                values = np.asarray(trace["values"])
                if (trace["block_path"] != path or trace["unit"] != old_leaf["unit"]
                        or values.shape != (len(trace["time"]), 1) or not np.isfinite(values).all()):
                    raise ValueError("Window leaf identity, unit, shape or finiteness differs")
                leaves.append(dict(name=name, time_s=trace["time"], values=values[:, 0], unit=trace["unit"]))
            block["leaf_variables"] = leaves
            basis = self.basis.get(path, {})
            row = evaluate_component(block, self.tables.get(basis.get("settings_path")), basis.get("equation_mass_kg"))
            row["settings_path"] = basis.get("settings_path", "")
            rows.append(row)
        return dict(schema=SCHEMA, start_s=start, stop_s=stop, fixed_step_s=dt,
                    source=self.source, component_count=len(rows), native_trace_count=len(traces),
                    components=rows, ledger_computation_pass=True,
                    legacy_fields_imported=False, external_control_volume_assembled=False,
                    equation_matched_cycle_closure_verified=False, full_internal_periodicity_verified=False,
                    production_recovery_allowed=False, table4_reproduction_claim=False)


def compare_partition(reference, prefix, suffix):
    for result in (reference, prefix, suffix):
        if result["schema"] != SCHEMA or not result["ledger_computation_pass"] or result["production_recovery_allowed"]:
            raise ValueError("Mixed ledger version, failed computation or invalid recovery scope")
    if (reference["start_s"] != prefix["start_s"] or reference["stop_s"] != suffix["stop_s"]
            or prefix["stop_s"] != suffix["start_s"]
            or not reference["source"] == prefix["source"] == suffix["source"]):
        raise ValueError("Noncontiguous or different-source partition")
    groups = [{r["block_path"]: r for r in result["components"]} for result in (reference, prefix, suffix)]
    if any(len(group) != len(result["components"]) for group, result in zip(groups, (reference, prefix, suffix))):
        raise ValueError("Duplicate ledger component")
    if not groups[0].keys() == groups[1].keys() == groups[2].keys():
        raise ValueError("Partition component inventories differ")
    fields = ("energy_equation_accumulation_J", "energy_endpoint_change_J", "energy_flow_integral_J",
              "energy_flow_absolute_integral_J", "energy_residual_J", "pressure_volume_work_J",
              "energy_enthalpy_endpoint_change_J", "mass_endpoint_change_kg", "mass_equation_accumulation_kg",
              "mass_flow_integral_kg", "mass_flow_absolute_integral_kg", "mass_residual_kg")
    comparisons = []
    for path, whole in groups[0].items():
        for field in fields:
            if field not in whole:
                if any(field in group[path] for group in groups[1:]):
                    raise ValueError("Partition ledger fields differ")
                continue
            values = [group[path][field] for group in groups]
            if not np.isfinite(values).all():
                raise ValueError("Nonfinite partition ledger")
            error = abs(values[0] - values[1] - values[2])
            # Addition-roundoff check only, never a physical closure threshold.
            atol = 1e-12 if field.endswith("_kg") else 1e-9
            limit = atol + 1e-11 * max(abs(v) for v in values)
            comparisons.append(dict(block_path=path, field=field, abs_difference=error,
                                    numerical_limit=limit, pass_check=bool(error <= limit)))
    return dict(partition_integrals_match=all(r["pass_check"] for r in comparisons),
                comparison_count=len(comparisons), comparisons=comparisons,
                scope="numerical additivity of retained native intervals, not physical closure")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("topology", "probe", "metadata", "split-root", "output"):
        parser.add_argument("--" + name, required=True, type=Path)
    parser.add_argument("--execution-commit", required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Do not overwrite native ledger evidence")
    provenance = audit_split(args.split_root, args.execution_commit)
    if not provenance["independent_mat_recalculation_pass"]:
        raise ValueError("Split trace experiment failed independent verification")
    inputs = {n: getattr(args, n) for n in ("topology", "probe", "metadata")}
    ledger = NativeWindowLedger(*(json.loads(p.read_text(encoding="utf-8-sig")) for p in inputs.values()))
    summary = json.loads((args.split_root / "segmented_inventory_restore.json").read_text(encoding="utf-8-sig"))
    if any(summary[key] != value for key, value in ledger.source.items()):
        raise ValueError("Split experiment and metadata sources differ")
    cases = []
    for i, case in enumerate(summary["cases"], 1):
        windows = {}
        with h5py.File(args.split_root / f"case_{i}_traces.mat", "r") as file:
            for part, start, stop in (("reference", case["start_s"], case["end_s"]),
                                      ("prefix", case["start_s"], case["split_s"]),
                                      ("suffix", case["split_s"], case["end_s"])):
                windows[part] = ledger.evaluate(load_traces(file, part, "native"), start, stop, summary["fixed_step_s"])
        comparison = compare_partition(windows["reference"], windows["prefix"], windows["suffix"])
        cases.append(dict(kind=case["kind"], windows=windows, partition=comparison))
    result = dict(schema="heatdrive_ecc_split_native_ledger_audit_v1", cases=cases,
                  source_execution_commit=args.execution_commit,
                  input_sha256={n: sha256(p) for n, p in inputs.items()},
                  split_input_sha256=provenance["input_sha256"],
                  partition_integrals_match=all(c["partition"]["partition_integrals_match"] for c in cases),
                  equation_matched_cycle_closure_verified=False, full_internal_periodicity_verified=False,
                  production_recovery_allowed=False, table4_reproduction_claim=False)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k not in ("cases", "input_sha256", "split_input_sha256")}, indent=2))
    if not result["partition_integrals_match"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
