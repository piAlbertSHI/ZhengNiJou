"""Conservative implicit-midpoint ACTIVE-bed integrator on the EOS manifold.

End states and integrated outflows solve mass + energy + EOS constraints
together. This is NOT integrate-then-project: no inconsistent accepted M/U is
overwritten to enforce pressure. Only a new cold chain may use this contract.
No claim of fixed ODE3 equivalence, sealed dwell or full hydraulic feasibility.
"""
import numpy as np
from scipy.optimize import root

from Reference_HeatDriveECC_ConservativeTransport import advective_faces, conductive_faces


def constrained_midpoint_step(bed, old_state, command, left_K, right_K, dt):
    if not np.isfinite(dt) or dt <= 0 or command == 0 or not np.isfinite(command):
        raise ValueError("Require a positive step and an active finite inlet command")
    n, eos = bed.nodes, bed.eos
    previous = bed.unpack(old_state)
    if np.max(abs(previous["p"]-eos.pref)) > 1.:
        raise ValueError("Off-manifold prior state cannot be repaired/projected into this chain")
    old_T, old_solid = previous["T"], previous["solid_T"]
    mass0, energy0, solid0 = old_state[:n], old_state[n:2*n], old_state[2*n:3*n]
    incoming_T = left_K if command > 0 else right_K
    inlet = eos.properties([incoming_T], [eos.pref])
    inlet_h = float(inlet["h"][0]-eos.uref)

    def endpoint_and_residual(unknown):
        fluid, solid = unknown[:n], unknown[n:]
        endpoint = eos.properties(fluid, np.full(n, eos.pref))
        mass1 = bed.volume*endpoint["rho"]
        energy1 = mass1*(endpoint["u"]-eos.uref)
        solid1 = bed.geometry.solid_capacity*(solid-eos.Tref)
        midpoint_T, midpoint_solid = .5*(old_T+fluid), .5*(old_solid+solid)
        stage = eos.properties(midpoint_T, np.full(n, eos.pref))
        heat = bed.Nu*stage["k"]*bed.surface_area_m2/(n*bed.hydraulic_diameter_m)*(midpoint_solid-midpoint_T)
        k = 2*stage["k"][:-1]*stage["k"][1:]/(stage["k"][:-1]+stage["k"][1:])
        conduction = np.r_[0., -k*bed.geometry.fluid_area_m2*np.diff(midpoint_T)/bed.geometry.dx, 0.]
        solid_conduction = conductive_faces(midpoint_solid, bed.geometry.solid_k_W_mK*bed.geometry.solid_area_m2/bed.geometry.dx)
        fluid_power = conduction[:-1]-conduction[1:]+heat
        solid_power = solid_conduction[:-1]-solid_conduction[1:]-heat
        dm = (mass1-mass0)/dt
        h = stage["h"]-eos.uref
        if command < 0:
            dm, h = dm[::-1], h[::-1]
        mass_faces = np.r_[abs(command), abs(command)-np.cumsum(dm)]
        if np.any(mass_faces <= 0):
            raise ValueError("Active constrained trial changed donor direction; use a more general flow closure")
        h_faces = advective_faces(h, 1., inlet_h, 0., limiter="MC")
        enthalpy_faces = mass_faces*h_faces
        advective_power = enthalpy_faces[:-1]-enthalpy_faces[1:]
        if command < 0:
            advective_power = advective_power[::-1]
        residual = np.r_[energy1-energy0-dt*(advective_power+fluid_power),
                         solid1-solid0-dt*solid_power]
        boundary_mass = dt*(mass_faces[0]-mass_faces[-1])
        boundary_energy = dt*(enthalpy_faces[0]-enthalpy_faces[-1])
        return residual, mass1, energy1, solid1, boundary_mass, boundary_energy

    # A temperature-coordinate solve avoids a stiff pressure correction. All
    # residuals are still the ORIGINAL conservative finite-volume equations.
    scale = np.r_[np.full(n, bed.geometry.fluid_capacity), np.full(n, bed.geometry.solid_capacity)]
    def objective(unknown):
        return endpoint_and_residual(unknown)[0]/scale
    solution = root(objective, np.r_[old_T, old_solid], method="hybr", options={"xtol": 1e-12})
    unknown = solution.x.copy()
    residual, mass1, energy1, solid1, dm, de = endpoint_and_residual(unknown)
    max_residual = float(np.max(abs(residual)))
    # Independent residual acceptance, including statuses that only report
    # lack of further progress at roundoff; the status itself is retained.
    allowance = 512*np.finfo(float).eps*max(1., float(np.max(abs(np.r_[energy1, solid1]))))
    polish_iterations, polish_evaluations = 0, 0
    # HYBR stops on scaled coordinate change, not this conservation residual.
    # Polish its UNACCEPTED nonlinear unknowns, not the physical prior state.
    # The independent residual threshold is unchanged.
    for _ in range(4):
        if max_residual <= allowance:
            break
        jacobian = np.empty((2*n, 2*n))
        for j in range(2*n):
            perturbation = 1e-4*max(1., abs(unknown[j])/300.)
            plus, minus = unknown.copy(), unknown.copy()
            plus[j] += perturbation
            minus[j] -= perturbation
            jacobian[:, j] = (endpoint_and_residual(plus)[0]-endpoint_and_residual(minus)[0])/(2*perturbation)
        polish_evaluations += 4*n
        correction = np.linalg.solve(jacobian, -residual)
        for factor in (1., .5, .25, .125):
            candidate = unknown+factor*correction
            trial = endpoint_and_residual(candidate)
            polish_evaluations += 1
            if np.max(abs(trial[0])) < max_residual:
                unknown = candidate
                residual, mass1, energy1, solid1, dm, de = trial
                max_residual = float(np.max(abs(residual)))
                polish_iterations += 1
                break
        else:
            break
    if not np.isfinite(unknown).all() or max_residual > allowance:
        raise RuntimeError(f"Conservative nonlinear residual {max_residual:g} J exceeds {allowance:g} J: {solution.message}")
    state = np.r_[mass1, energy1, solid1, old_state[-2]+dm, old_state[-1]+de]
    observed = bed.unpack(state)
    return state, {"nonlinear_success_flag": bool(solution.success), "nonlinear_message": str(solution.message),
        "RHS_evaluations": int(solution.nfev)+polish_evaluations, "max_nonlinear_energy_residual_J": max_residual,
        "unaccepted_nonlinear_unknown_polish_iterations": polish_iterations,
        "roundoff_scaled_residual_allowance_J": allowance,
        "max_endpoint_pressure_deviation_Pa": float(np.max(abs(observed["p"]-eos.pref))),
        "integrated_mass_boundary_increment_kg": dm, "integrated_energy_boundary_increment_J": de,
        "accepted_state_projected_or_reset": False}
