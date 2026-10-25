"""Decompose observed native chamber endpoint errors without altering gates.

The intermediate path is explicitly the straight state-space chord between
retained samples, not an observation of the unknown substep trajectory.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_NativeAccumulation import ENERGY_ATOL_J_KG, energy_tables
from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_NativeWindowLedger import validate_grid
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field
from Audit_HeatDriveECC_TLDomainInventory import DENSITY_ATOL_KG_M3, resolve_domains


def chord_integrals(table, states, volume, order=4):
    """Integrate native coefficients on chords split at every property knot."""
    states = np.asarray(states, dtype=float)
    if (states.ndim != 2 or states.shape[1] != 2 or len(states) < 2
            or not np.isfinite(states).all() or not np.isfinite(volume)
            or volume <= 0 or order not in (4, 5)):
        raise ValueError("Require finite [T,p] observations and positive volume")
    grids = table["rho"].grid
    if np.ptp(table["beta"].values) != 0:
        raise ValueError("Polynomial chord quadrature requires constant bulk modulus")
    if any(np.any(np.diff(g) <= 0) for g in grids):
        raise ValueError("Invalid property knots")
    if any(np.any(states[:, k] < g[0]) or np.any(states[:, k] > g[-1])
           for k, g in enumerate(grids)):
        raise ValueError("Observed chord endpoints outside the property domain")
    delta = np.diff(states, axis=0)
    parents, left, widths = [], [], []
    for i, (point, change) in enumerate(zip(states[:-1], delta)):
        cuts = [0.0, 1.0]
        for k in (0, 1):
            if change[k] != 0:
                fractions = (grids[k] - point[k]) / change[k]
                cuts.extend(fractions[(fractions > 0) & (fractions < 1)].tolist())
        cuts = np.unique(cuts)
        for lo, hi in zip(cuts[:-1], cuts[1:]):
            parents.append(i)
            left.append(lo)
            widths.append(hi - lo)
    parents = np.asarray(parents, dtype=int)
    left, widths = np.asarray(left), np.asarray(widths)
    energy, mass = np.zeros(len(delta)), np.zeros(len(delta))
    nodes, weights = np.polynomial.legendre.leggauss(order)
    # Bilinear rho/u/cp/alpha and constant beta give polynomials of degree
    # at most six on each knot-bounded chord; four-point Gauss is exact.
    for node, weight in zip((nodes + 1) / 2, weights / 2):
        points = states[parents] + (left + widths * node)[:, None] * delta[parents]
        rho, u, cp, alpha, beta = [
            table[key](points) for key in ("rho", "u", "cp", "alpha", "beta")]
        temperature, pressure = points.T
        rho_h = rho * u + pressure
        dp, dtemp = delta[parents, 1], delta[parents, 0]
        e = volume * ((rho_h / beta - temperature * alpha) * dp
                      + (rho * cp - rho_h * alpha) * dtemp)
        m = volume * rho * (dp / beta - alpha * dtemp)
        energy += np.bincount(parents, weights=weight * widths * e, minlength=len(delta))
        mass += np.bincount(parents, weights=weight * widths * m, minlength=len(delta))
    return energy, mass, len(parents)


def split_endpoint_error(input_increments, be_increments, chord_increments, endpoint_increments):
    arrays = [np.asarray(v, dtype=float) for v in
              (input_increments, be_increments, chord_increments, endpoint_increments)]
    if (arrays[0].ndim != 1 or not arrays[0].size
            or any(a.shape != arrays[0].shape for a in arrays)
            or not np.isfinite(arrays).all()):
        raise ValueError("Require matching finite interval increments")
    source, be, chord, endpoint = arrays
    error, equation, right_rule, property_term = (
        source - endpoint, source - be, be - chord, chord - endpoint)
    return dict(
        endpoint_residual=float(error.sum()),
        solver_equation_residual=float(equation.sum()),
        right_endpoint_vs_assumed_chord=float(right_rule.sum()),
        assumed_chord_coefficients_vs_inventory=float(property_term.sum()),
        absolute_interval_endpoint_residual_sum=float(abs(error).sum()),
        absolute_interval_right_endpoint_term_sum=float(abs(right_rule).sum()),
        absolute_interval_property_term_sum=float(abs(property_term).sum()),
        max_interval_identity_error=float(abs(error - equation - right_rule - property_term).max()),
        interval_count=int(error.size),
    )


def analyze(root, start=180.0, stop=200.0):
    root = Path(root).resolve()
    paths = dict(observations=root / "native/observations.mat",
                 metadata=root / "native/inventory_metadata.json",
                 topology=root / "native/tl_connectivity.json",
                 configuration=root / "native/configuration.mat",
                 execution=root / "cold_chamber_execution.json")
    execution = json.loads(paths["execution"].read_text(encoding="utf-8-sig"))
    if not execution["requested_arm_collection_pass"] or execution["error_message"]:
        raise ValueError("Require an already completed observation package")
    metadata = json.loads(paths["metadata"].read_text(encoding="utf-8-sig"))
    topology = json.loads(paths["topology"].read_text(encoding="utf-8-sig"))
    assignment, domains = resolve_domains(topology)
    if domains != 2:
        raise ValueError("Unexpected fluid-domain assignment")
    settings = {r["block_path"]: r["parameters"] for r in metadata["settings_tables"]}
    with h5py.File(paths["configuration"], "r") as f:
        solver = f["options/simscape"]
        dt = float(solver["local_solver_sample_time_s"][0, 0])
        if (not bool(solver["local_solver_enabled"][0, 0])
                or text_field(solver["local_solver_choice"]) != "NE_BACKWARD_EULER_ADVANCER"):
            raise ValueError("This decomposition requires the actual local BE scheme")
    components = []
    with h5py.File(paths["observations"], "r") as f:
        rows = named_rows(f, f["native"])
        for block in metadata["storage_blocks"]:
            if block["mask_type"] != "Constant Volume Chamber (TL)":
                continue
            path = block["block_path"]
            table = energy_tables(settings[assignment[path]])
            all_time = rows[path, "T_I"]["time_s"][:].ravel()
            selected = (all_time >= start - 1e-10) & (all_time <= stop + 1e-10)
            time = all_time[selected]
            validate_grid(time, start, stop, dt)

            def get(name, unit):
                row = rows[path, name]
                if not np.array_equal(row["time_s"][:].ravel(), all_time):
                    raise ValueError("Native coordinates have different clocks")
                return convert(row["values"][:].ravel()[selected], text_field(row["unit"]), unit)

            temp, pressure, rho, u, h = [get(n, unit) for n, unit in (
                ("T_I", "K"), ("p_I", "Pa"), ("rho_I", "kg/m^3"),
                ("u_I", "J/kg"), ("h_I", "J/kg"))]
            states = np.column_stack((temp, pressure))
            rho_error = float(abs(table["rho"](states) - rho).max())
            u_error = float(abs(table["u"](states) - u).max())
            if rho_error > DENSITY_ATOL_KG_M3 or u_error > ENERGY_ATOL_J_KG:
                raise ValueError("Actual native inventories do not match the assigned property table")
            parameter = block["mask_parameters"]["volume"]
            volume = float(convert(parameter["value"], parameter["unit"], "m^3"))
            cp, alpha, beta = [table[k](states) for k in ("cp", "alpha", "beta")]
            be_energy = volume * (
                (rho * h / beta - temp * alpha)[1:] * np.diff(pressure)
                + ((cp - h * alpha) * rho)[1:] * np.diff(temp))
            be_mass = volume * rho[1:] * (
                np.diff(pressure) / beta[1:] - alpha[1:] * np.diff(temp))
            ports = [n[5:] for p, n in rows if p == path and n.startswith("mdot_")]
            net_energy = sum((get("Phi_" + p, "W") for p in ports), np.zeros(len(time))) + get("Q_H", "W")
            net_mass = sum((get("mdot_" + p, "kg/s") for p in ports), np.zeros(len(time)))
            chord_e, chord_m, segments = chord_integrals(table, states, volume, 4)
            check_e, check_m, _ = chord_integrals(table, states, volume, 5)
            endpoint_energy, endpoint_mass = np.diff(volume * rho * u), np.diff(volume * rho)
            energy = split_endpoint_error(net_energy[1:] * np.diff(time), be_energy, chord_e, endpoint_energy)
            mass = split_endpoint_error(net_mass[1:] * np.diff(time), be_mass, chord_m, endpoint_mass)
            ranking = np.argsort(abs(net_energy[1:] * np.diff(time) - endpoint_energy))[-5:][::-1]
            components.append(dict(
                block_path=path, samples=len(time), window_s=[start, stop], volume_m3=volume,
                temperature_range_K=[float(temp.min()), float(temp.max())],
                pressure_range_MPa=[float(pressure.min() / 1e6), float(pressure.max() / 1e6)],
                native_density_lookup_max_abs_error_kg_m3=rho_error,
                native_energy_lookup_max_abs_error_J_kg=u_error,
                knot_bounded_chord_segments=segments, energy_J=energy, mass_kg=mass,
                gauss4_vs5_max_interval_J=float(abs(chord_e - check_e).max()),
                gauss4_vs5_max_interval_kg=float(abs(chord_m - check_m).max()),
                largest_intervals=[dict(
                    window_s=[float(time[i]), float(time[i + 1])],
                    temperature_change_K=float(temp[i + 1] - temp[i]),
                    pressure_change_MPa=float((pressure[i + 1] - pressure[i]) / 1e6),
                    endpoint_residual_J=float(net_energy[i + 1] * (time[i + 1] - time[i]) - endpoint_energy[i]),
                    right_endpoint_vs_assumed_chord_J=float(be_energy[i] - chord_e[i]),
                    assumed_chord_vs_inventory_J=float(chord_e[i] - endpoint_energy[i]))
                    for i in ranking],
            ))
    if len(components) != 2:
        raise ValueError("Require exactly the two native connecting chambers")
    return dict(
        schema="heatdrive_ecc_chamber_discrete_chain_rule_v1", source_root=str(root),
        producer=execution["execution_commit"], window_s=[start, stop],
        local_step_s=dt, components=components,
        interpretation=dict(
            state_chords_are_assumed_not_observed_substep_paths=True,
            signed_property_defects_can_cancel_do_not_omit_absolute_sums=True,
            decomposition_does_not_supply_missing_heat=True,
            endpoint_residuals_not_removed=True, physical_gates_unchanged=True,
            timestep_convergence_of_the_coupled_model_not_proven=True),
        simulation_executed=False, source_state_edited=False,
        full_device_first_law_verified=False, production_recovery_allowed=False,
        input_sha256={k: sha256(p) for k, p in paths.items()},
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--experiment-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--start", type=float, default=180.0)
    parser.add_argument("--stop", type=float, default=200.0)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Never overwrite diagnostic evidence")
    result = analyze(args.experiment_root, args.start, args.stop)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({r["block_path"]: r["energy_J"] for r in result["components"]}, indent=2))


if __name__ == "__main__":
    main()
