"""Compare native short-window accumulation equations with endpoint ledgers.

The tank's documented equation simplifies to M*cp*dT + h*dM = net energy.
For a chamber, the actual table-derived differential coefficients are retained.
Interpolated property tables need not have exactly consistent derivatives, so
endpoint M*u and a coefficient-path integral are reported separately.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from scipy.integrate import cumulative_trapezoid
from scipy.interpolate import RegularGridInterpolator

from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_TLDomainInventory import density_table, literal_vector, reconstruct, scalar


ENERGY_ATOL_J_KG = 1e-6  # Implementation comparison, not an energy closure tolerance.


def energy_tables(parameters):
    if parameters["u_parameterization_1D"] != "1":
        raise ValueError("Only the observed internal-energy-vector mode is supported")
    density = density_table(parameters)
    temperature, pressure = density.grid
    rho = density.values
    u_ref = convert(literal_vector(parameters["u_TLU_4"]), parameters["u_TLU_4_unit"], "J/kg")
    if u_ref.shape != temperature.shape:
        raise ValueError("Internal energy and temperature table shapes differ")
    beta = scalar(parameters["beta_const_4"], parameters["beta_const_4_unit"], "Pa")
    reference = scalar(parameters["p_ref_4"], parameters["p_ref_4_unit"], "Pa")
    # First-order end differences and nonuniform central differences match R2025b.
    alpha = -np.gradient(rho, temperature, axis=0, edge_order=1) / rho
    du_dp = (pressure[None, :] / beta - temperature[:, None] * alpha) / rho
    integral = cumulative_trapezoid(du_dp, pressure, axis=1, initial=0)
    ref_integral = RegularGridInterpolator((temperature, pressure), integral)(
        np.column_stack((temperature, np.full(temperature.size, reference))))
    u = integral + (u_ref - ref_integral)[:, None]
    cp = np.gradient(u + pressure[None, :] / rho, temperature, axis=0, edge_order=1)
    if np.any(cp <= 0) or not np.isfinite([rho, u, cp, alpha]).all():
        raise ValueError("Invalid reconstructed thermodynamic tables")
    return {name: RegularGridInterpolator((temperature, pressure), values, bounds_error=True)
            for name, values in {"rho": rho, "u": u, "cp": cp, "alpha": alpha,
                                 "beta": np.full_like(rho, beta)}.items()}


def path_integral(coefficient, coordinate):
    coefficient, coordinate = np.asarray(coefficient), np.asarray(coordinate)
    if (coefficient.shape != coordinate.shape or coefficient.ndim != 1
            or coefficient.size < 2 or not np.isfinite([coefficient, coordinate]).all()):
        raise ValueError("Path integral requires matching finite scalar sample vectors")
    return float(np.sum(.5 * (coefficient[:-1] + coefficient[1:]) * np.diff(coordinate)))


def audit_accumulation(topology, probe, metadata):
    basis = reconstruct(topology, probe, metadata)
    if not basis["nominal_pipe_storage_reconstruction_pass"]:
        raise ValueError("Require successful domain and density reconstruction first")
    assignment = {r["block_path"]: r["settings_path"] for r in basis["components"]}
    lookups = {row["block_path"]: energy_tables(row["parameters"]) for row in topology["settings_tables"]}
    rows = []
    for block in probe["storage_blocks"]:
        kind = block["mask_type"]
        if kind == "Thermal Mass":
            continue
        leaves = {r["name"]: r for r in block["leaf_variables"]}
        def series(name, unit):
            leaf = leaves[name]
            return convert(leaf["values"], leaf["unit"], unit)
        time = np.array(leaves["T_I"]["time_s"])
        temp, pressure = series("T_I", "K"), series("p_I", "Pa")
        coords = np.column_stack((temp, pressure))
        table = lookups[assignment[block["block_path"]]]
        u, rho, h = series("u_I", "J/kg"), series("rho_I", "kg/m^3"), series("h_I", "J/kg")
        cp, alpha, beta = (table[name](coords) for name in ("cp", "alpha", "beta"))
        u_error = float(np.max(np.abs(table["u"](coords) - u)))
        row = dict(block_path=block["block_path"], mask_type=kind,
                   settings_path=assignment[block["block_path"]], sample_count=int(time.size),
                   start_s=float(time[0]), stop_s=float(time[-1]),
                   internal_energy_lookup_max_abs_error_J_kg=u_error,
                   internal_energy_lookup_matches_native=u_error <= ENERGY_ATOL_J_KG,
                   cp_range_J_kg_K=[float(cp.min()), float(cp.max())])
        ports = [name[5:] for name in leaves if name.startswith("mdot_")]
        mdot = sum((series("mdot_" + port, "kg/s") for port in ports), np.zeros_like(time))
        flow = sum((series("Phi_" + port, "W") for port in ports), np.zeros_like(time)) + series("Q_H", "W")
        net_J, net_kg = path_integral(flow, time), path_integral(mdot, time)
        if kind == "Tank (TL)":
            if float(np.ptp(pressure)) > 1e-6:
                raise ValueError("This audit supports only the observed constant-pressure tank")
            mass, volume = series("mass", "kg"), series("volume", "m^3")
            accumulation_J = path_integral(mass * cp, temp) + path_integral(h, mass)
            delta_U = float(mass[-1] * u[-1] - mass[0] * u[0])
            pdV = path_integral(pressure, volume)
            row.update(equation_basis="integral(M*cp dT + h dM); constant pressure",
                       equation_accumulation_J=accumulation_J,
                       endpoint_internal_energy_change_J=delta_U, pressure_volume_work_J=pdV,
                       endpoint_enthalpy_change_J=float(mass[-1] * h[-1] - mass[0] * h[0]),
                       coefficient_vs_endpoint_U_plus_pdV_J=accumulation_J - delta_U - pdV,
                       native_mass_change_kg=float(mass[-1] - mass[0]),
                       integrated_net_mass_kg=net_kg, short_window_mass_residual_kg=net_kg - float(mass[-1] - mass[0]),
                       integrated_net_energy_J=net_J, short_window_equation_energy_residual_J=net_J - accumulation_J,
                       short_window_endpoint_U_plus_pdV_residual_J=net_J - delta_U - pdV)
        elif kind == "Constant Volume Chamber (TL)":
            param = block["mask_parameters"]["volume"]
            volume = float(convert(param["value"], param["unit"], "m^3"))
            if volume <= 0:
                raise ValueError("Chamber volume must be positive")
            dU_dp = (rho * h / beta - temp * alpha) * volume
            dU_dT = (cp - h * alpha) * rho * volume
            accumulation_J = path_integral(dU_dp, pressure) + path_integral(dU_dT, temp)
            accumulation_kg = path_integral(rho * volume / beta, pressure) - path_integral(alpha * rho * volume, temp)
            endpoint_J = float(volume * (rho[-1] * u[-1] - rho[0] * u[0]))
            endpoint_kg = float(volume * (rho[-1] - rho[0]))
            row.update(equation_basis="integral(dUdp dp + dUdT dT), with native table coefficients",
                       equation_accumulation_J=accumulation_J, endpoint_internal_energy_change_J=endpoint_J,
                       equation_mass_accumulation_kg=accumulation_kg, endpoint_mass_change_kg=endpoint_kg,
                       integrated_net_energy_J=net_J, integrated_net_mass_kg=net_kg,
                       short_window_equation_energy_residual_J=net_J - accumulation_J,
                       short_window_endpoint_energy_residual_J=net_J - endpoint_J,
                       short_window_equation_mass_residual_kg=net_kg - accumulation_kg,
                       short_window_endpoint_mass_residual_kg=net_kg - endpoint_kg)
        rows.append(row)
    return dict(schema="heatdrive_ecc_native_accumulation_v1", component_count=len(rows),
                native_energy_sample_count=sum(r["sample_count"] for r in rows),
                internal_energy_comparison_atol_J_kg=ENERGY_ATOL_J_KG,
                internal_energy_lookup_matches_native=all(r["internal_energy_lookup_matches_native"] for r in rows),
                internal_energy_lookup_max_abs_error_J_kg=max(r["internal_energy_lookup_max_abs_error_J_kg"] for r in rows),
                components=rows, scope="Three-step differential-equation and property-table diagnostics, not cycle closure",
                equation_matched_cycle_closure_verified=False, complete_internal_state_periodicity_verified=False,
                production_continuation_allowed=False, diagnostic_checkpoint_recovery_allowed=False,
                table4_reproduction_claim=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("topology", "probe", "metadata", "output"):
        parser.add_argument("--" + name, required=True, type=Path)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Do not overwrite accumulation evidence")
    inputs = {name: getattr(args, name).read_bytes() for name in ("topology", "probe", "metadata")}
    result = audit_accumulation(*(json.loads(data.decode("utf-8-sig")) for data in inputs.values()))
    result["input_sha256"] = {name: hashlib.sha256(data).hexdigest().upper() for name, data in inputs.items()}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k != "components"}, indent=2))
    if not result["internal_energy_lookup_matches_native"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
