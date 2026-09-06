"""Resolve actual TL networks and reconstruct quasisteady pipe storage.

The 30-pressure-point expansion is from the installed R2025b settings source.
Native comparisons are implementation checks, not physical validation or a
cycle energy-closure gate. No recovery authority is granted by this audit.
"""
import argparse
import csv
import hashlib
import json
import re
from collections import Counter
from pathlib import Path

import numpy as np
from scipy.interpolate import RegularGridInterpolator
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

from Audit_HeatDriveECC_NativeInventoryCatalog import audit_probe, convert


SETTINGS = "foundation.thermal_liquid.utilities.thermal_liquid_settings"
PIPE = "foundation.thermal_liquid.elements.pipe"
PRIMITIVES = {
    PIPE: 2,
    "foundation.thermal_liquid.elements.constant_volume_chamber": 2,
    "foundation.thermal_liquid.sensors.flow_sensor": 2,
    "foundation.thermal_liquid.sensors.pressure_temperature_sensor": 1,
    "foundation.thermal_liquid.sources.pressure_source": 2,
    SETTINGS: 1,
    "fluids.thermal_liquid.pipes_fittings.t_junction": 3,
    "fluids.thermal_liquid.tanks_accumulators.tank": 1,
    "fluids.thermal_liquid.valves.flow_coefficient_valve": 2,
}
DOMAIN = "foundation.thermal_liquid.thermal_liquid"
# Absolute implementation-comparison tolerance, declared before comparisons.
DENSITY_ATOL_KG_M3 = 1e-7


def as_list(value):
    return value if isinstance(value, list) else [value]


def resolve_domains(topology):
    if topology["schema"] != "heatdrive_ecc_tl_connectivity_v2":
        raise ValueError("Require branch-aware v2 physical connectivity")
    if topology["source_model_modified"] or topology["domain"] != DOMAIN:
        raise ValueError("Require an unchanged TL model")
    vertices, blocks = topology["vertices"], topology["blocks"]
    if any(v["domain"] != DOMAIN for v in vertices):
        raise ValueError("Non-TL port in the hydraulic graph")
    if len({v["key"] for v in vertices}) != len(vertices):
        raise ValueError("Duplicate vertex keys")
    n = len(vertices)
    edges = []
    covered = []
    for edge in topology["edges"]:
        if edge["kind"] not in ("physical_wire_net", "hierarchy_connector"):
            raise ValueError("Unregistered graph edge kind")
        if not (1 <= edge["a"] <= n and 1 <= edge["b"] <= n):
            raise ValueError("Graph edge index out of bounds")
        edges.append((edge["a"] - 1, edge["b"] - 1))
    for block in blocks:
        indices = as_list(block["vertex_indices"])
        if any(not 1 <= i <= n for i in indices):
            raise ValueError("Block vertex index out of bounds")
        if any(vertices[i - 1]["block_path"] != block["block_path"] for i in indices):
            raise ValueError("Block/vertex owner mismatch")
        covered.extend(indices)
        source = block["source_file"]
        if not source and block["block_type"] in ("SubSystem", "PMIOPort"):
            continue  # Never merge unrelated fluid channels inside a subsystem.
        if source not in PRIMITIVES or len(indices) != PRIMITIVES[source]:
            raise ValueError(f"Unregistered primitive/port count: {block['block_path']}")
        edges.extend((indices[0] - 1, i - 1) for i in indices[1:])
    if sorted(covered) != list(range(1, n + 1)):
        raise ValueError("Each typed vertex must have exactly one owning block")
    if len({b["block_path"] for b in blocks}) != len(blocks):
        raise ValueError("Duplicate block paths")
    adjacency = coo_matrix((np.ones(len(edges)), np.array(edges).T), shape=(n, n))
    count, labels = connected_components(adjacency, directed=False)
    settings_by_label = {}
    for block in blocks:
        if block["source_file"] != SETTINGS:
            continue
        label = int(labels[as_list(block["vertex_indices"])[0] - 1])
        if label in settings_by_label:
            raise ValueError("Two property settings connected to the same fluid network")
        settings_by_label[label] = block["block_path"]
    if len(settings_by_label) != count:
        raise ValueError("An isolated hydraulic component has no unique property settings")
    assignment = {}
    for block in blocks:
        if block["source_file"]:
            indices = as_list(block["vertex_indices"])
            network = {int(labels[i - 1]) for i in indices}
            if len(network) != 1:
                raise ValueError("Primitive fluid channel was split")
            assignment[block["block_path"]] = settings_by_label[network.pop()]
    return assignment, count


def literal_vector(expression):
    # Mask expressions here must be numeric literals, never evaluated MATLAB code.
    text = expression.strip()
    if text.startswith("[") and text.endswith("]"):
        text = text[1:-1]
    tokens = re.split(r"[;,\s]+", text.strip())
    number = r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?"
    if not tokens or any(not re.fullmatch(number, t) for t in tokens):
        raise ValueError("Only explicit finite numeric mask literals are supported")
    values = np.array([float(t) for t in tokens])
    if not np.isfinite(values).all():
        raise ValueError("Nonfinite mask literal")
    return values


def scalar(expression, unit, target):
    values = literal_vector(expression)
    if values.size != 1:
        raise ValueError("Expected scalar mask parameter")
    if unit == "GPa" and target == "Pa":
        return float(values[0] * 1e9)
    return float(convert(values, unit, target)[0])


def density_table(parameters):
    p = parameters
    if p["table_dimensions"] != "1" or p["rho_parameterization_1D"] != "1":
        raise ValueError("Require verified 1D density-vector parameterization")
    if p["T_TLU_unit"] != "K":
        raise ValueError("Validity bounds require the verified kelvin temperature basis")
    temperature = convert(literal_vector(p["T_TLU"]), p["T_TLU_unit"], "K")
    rho = convert(literal_vector(p["rho_TLU_4"]), p["rho_TLU_4_unit"], "kg/m^3")
    if temperature.size < 2 or rho.shape != temperature.shape or np.any(np.diff(temperature) <= 0):
        raise ValueError("Invalid temperature/density table")
    if (np.any(rho <= 0) or float(p["T_min_1D"]) != temperature[0]
            or float(p["T_max_1D"]) != temperature[-1]):
        raise ValueError("This reconstruction requires all table temperature points valid")
    lo = scalar(p["p_min_1D"], p["p_min_1D_unit"], "Pa")
    hi = scalar(p["p_max_1D"], p["p_max_1D_unit"], "Pa")
    reference = scalar(p["p_ref_4"], p["p_ref_4_unit"], "Pa")
    beta = scalar(p["beta_const_4"], p["beta_const_4_unit"], "Pa")
    if not (0 < lo <= reference <= hi and lo < hi and beta > 0):
        raise ValueError("Invalid pressure/bulk modulus domain")
    pressure = 10 ** (np.arange(30) / 29 * (np.log10(hi) - np.log10(lo)) + np.log10(lo))
    table = rho[:, None] * np.exp((pressure[None, :] - reference) / beta)
    lookup = RegularGridInterpolator((temperature, pressure), table, method="linear", bounds_error=True)
    return lookup


def reconstruct(topology, probe, metadata):
    audit_probe(probe, metadata)  # Source, units, mask modes, samples, and strict restore.
    for key in ("source_result_sha256", "source_checkpoint_sha256"):
        if topology[key] != probe[key]:
            raise ValueError("Topology and native probe provenance differ")
    if topology["simulation_run"] or topology["checkpoint_saved"] or not topology["metadata_collection_pass"]:
        raise ValueError("Require successful build-only topology metadata")
    assignment, count = resolve_domains(topology)
    if count != 2:
        raise ValueError("Expected exactly two separately configured fluid domains")
    settings = {r["block_path"]: r["parameters"] for r in topology["settings_tables"]}
    if len(settings) != len(topology["settings_tables"]) or set(settings) != set(assignment.values()):
        raise ValueError("Connected settings and exported property tables differ")
    lookups = {path: density_table(p) for path, p in settings.items()}
    rows = []
    for block in probe["storage_blocks"]:
        if block["mask_type"] == "Thermal Mass":
            continue
        path = block["block_path"]
        settings_path = assignment[path]
        leaves = {r["name"]: r for r in block["leaf_variables"]}
        def series(name, unit):
            leaf = leaves[name]
            return convert(leaf["values"], leaf["unit"], unit)
        temp, pressure = series("T_I", "K"), series("p_I", "Pa")
        rho = series("rho_I", "kg/m^3")
        predicted = lookups[settings_path](np.column_stack((temp, pressure)))
        error = float(np.max(np.abs(predicted - rho)))
        row = dict(block_path=path, mask_type=block["mask_type"], settings_path=settings_path,
                   native_density_sample_count=int(rho.size), density_max_abs_error_kg_m3=error,
                   density_lookup_matches_native=error <= DENSITY_ATOL_KG_M3)
        if block["mask_type"] == "Pipe (TL)":
            mode = block["model_modes"]
            if mode["dynamic_compressibility"] != "false":
                raise ValueError("Pipe is not the audited quasisteady mode")
            nominal_t = scalar(mode["T_nominal"], mode["T_nominal_unit"], "K")
            nominal_p = scalar(mode["p_nominal"], mode["p_nominal_unit"], "Pa")
            nominal_rho = float(lookups[settings_path]([[nominal_t, nominal_p]])[0])
            params = block["mask_parameters"]
            if params["area"]["unit"] != "m^2" or params["length"]["unit"] != "m":
                raise ValueError("Unsupported pipe geometry units")
            volume = float(params["area"]["value"] * params["length"]["value"])
            if not np.isfinite(volume) or volume <= 0:
                raise ValueError("Expected positive finite pipe volume")
            mass = nominal_rho * volume
            u = series("u_I", "J/kg")
            time = np.asarray(leaves["u_I"]["time_s"])
            net = series("Phi_A", "W") + series("Phi_B", "W") + series("Q_H", "W")
            net_J = float(np.sum(.5 * (net[1:] + net[:-1]) * np.diff(time)))
            delta_U = float(mass * (u[-1] - u[0]))
            legacy_U = float(volume * (rho[-1] * u[-1] - rho[0] * u[0]))
            row.update(nominal_temperature_K=nominal_t, nominal_pressure_Pa=nominal_p,
                       nominal_density_kg_m3=nominal_rho, volume_m3=volume,
                       equation_mass_kg=mass, equation_mass_change_kg=0.0,
                       equation_internal_energy_change_J=delta_U,
                       legacy_internal_energy_change_J=legacy_U,
                       legacy_mass_change_kg=float(volume * (rho[-1] - rho[0])),
                       legacy_mass_relative_difference_max=float(np.max(np.abs(rho / nominal_rho - 1))),
                       integrated_net_energy_J=net_J,
                       short_window_energy_residual_J=net_J - delta_U,
                       short_window_legacy_energy_residual_J=net_J - legacy_U)
        rows.append(row)
    pipe_rows = [r for r in rows if r["mask_type"] == "Pipe (TL)"]
    density_pass = all(r["density_lookup_matches_native"] for r in rows)
    groups = []
    for path in settings:
        selected = [r for r in rows if r["settings_path"] == path]
        groups.append(dict(settings_path=path, storage_counts=dict(Counter(r["mask_type"] for r in selected)),
                           nominal_pipe_mass_kg=sum(r.get("equation_mass_kg", 0) for r in selected)))
    return dict(schema="heatdrive_ecc_tl_domain_inventory_v1", hydraulic_domains_verified=True,
                hydraulic_domain_count=count, domain_groups=groups, fluid_storage_count=len(rows),
                pipe_count=len(pipe_rows), native_density_sample_count=sum(r["native_density_sample_count"] for r in rows),
                density_comparison_atol_kg_m3=DENSITY_ATOL_KG_M3,
                density_lookup_matches_native=density_pass,
                density_max_abs_error_kg_m3=max(r["density_max_abs_error_kg_m3"] for r in rows),
                nominal_pipe_storage_reconstruction_pass=density_pass and len(pipe_rows) == 67,
                implementation_source="Installed MATLAB R2025b pipe.ssc and thermal_liquid_settings.ssc",
                pressure_grid_points=30, interpolation="bilinear; all evaluated points must be in bounds",
                components=rows, equation_matched_cycle_closure_verified=False,
                complete_internal_state_periodicity_verified=False,
                production_continuation_allowed=False, diagnostic_checkpoint_recovery_allowed=False,
                table4_reproduction_claim=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--topology", required=True, type=Path)
    parser.add_argument("--probe", required=True, type=Path)
    parser.add_argument("--metadata", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.output.exists() or args.output.with_suffix(".csv").exists():
        raise FileExistsError("Do not overwrite domain inventory evidence")
    inputs = {name: getattr(args, name).read_bytes() for name in ("topology", "probe", "metadata")}
    result = reconstruct(*(json.loads(inputs[name].decode("utf-8-sig")) for name in inputs))
    result["input_sha256"] = {name: hashlib.sha256(data).hexdigest().upper() for name, data in inputs.items()}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    with args.output.with_suffix(".csv").open("w", newline="", encoding="utf-8-sig") as stream:
        fields = sorted(set().union(*(r.keys() for r in result["components"])))
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(result["components"])
    print(json.dumps({k: v for k, v in result.items() if k not in ("components", "domain_groups")}, indent=2))
    if not result["nominal_pipe_storage_reconstruction_pass"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
