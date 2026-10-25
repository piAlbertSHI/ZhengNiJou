"""Variable-property rigid-volume ACTIVE bed with explicit pressure invariant.

Primary states are cell mass and internal energy, not independently reset T/p.
At continuous time the outflow is chosen from the exact EOS Jacobian to give
dp/dt=0. Finite-step pressure drift is observed, NEVER projected away. This
is an open prescribed-inlet/pressure component, not a sealed dwell model or
the full hydraulic loop. Phase power and mechanical coupling remain absent.
"""
from dataclasses import dataclass

import numpy as np

from Reference_HeatDriveECC_ConservativeTransport import Bed, advective_faces, conductive_faces


class EOSDomainError(ValueError):
    """An inadmissible EOS trial; its conserved input is never modified."""
    def __init__(self, message, details=None):
        super().__init__(message)
        self.details = details or {}


class TabulatedEOS:
    """Exact bilinear rho/u surfaces and their own piecewise derivatives.

    The saved native cp/alpha/beta coefficient tables are deliberately not
    substituted for derivatives of the actual rho/u interpolants.
    """
    def __init__(self, temperature_K, pressure_Pa, rho, internal_energy_J_kg,
                 conductivity_W_mK, reference_temperature_K=303.15, reference_pressure_Pa=850000.):
        self.temperature = np.asarray(temperature_K, dtype=float).copy()
        self.pressure = np.asarray(pressure_Pa, dtype=float).copy()
        self.rho = np.asarray(rho, dtype=float).copy()
        self.u = np.asarray(internal_energy_J_kg, dtype=float).copy()
        self.k = np.asarray(conductivity_W_mK, dtype=float).copy()
        self.Tref, self.pref = float(reference_temperature_K), float(reference_pressure_Pa)
        shape = (len(self.temperature), len(self.pressure))
        if (len(self.temperature) < 2 or len(self.pressure) < 2 or self.rho.shape != shape
                or self.u.shape != shape or self.k.shape != self.temperature.shape
                or any(not np.isfinite(v).all() for v in (self.temperature, self.pressure, self.rho, self.u, self.k))
                or np.any(np.diff(self.temperature) <= 0) or np.any(np.diff(self.pressure) <= 0)
                or np.min(self.rho) <= 0 or np.min(self.k) <= 0
                or np.any(np.diff(self.u, axis=0) <= 0) or np.any(np.diff(self.rho, axis=1) <= 0)
                or np.any(np.diff(self.u, axis=1) > 0)):
            raise ValueError("Require finite monotone invertible EOS tables and positive transport")
        # The determinant is affine inside a bilinear cell. Positive values
        # at all four corners establish monotone density along an iso-u curve.
        dt, dp = np.diff(self.temperature)[:, None], np.diff(self.pressure)[None, :]
        for a in (0., 1.):
            for b in (0., 1.):
                slopes = {}
                for name, table in (("rho", self.rho), ("u", self.u)):
                    slopes[name+"_p"] = ((1-a)*np.diff(table, axis=1)[:-1]+a*np.diff(table, axis=1)[1:])/dp
                    slopes[name+"_T"] = ((1-b)*np.diff(table, axis=0)[:, :-1]+b*np.diff(table, axis=0)[:, 1:])/dt
                if np.any(slopes["rho_p"]*slopes["u_T"]-slopes["rho_T"]*slopes["u_p"] <= 0):
                    raise ValueError("EOS does not have monotone isochoric energy/iso-u density")
        self.uref = float(self.properties([self.Tref], [self.pref])["u"][0])
        self.u_reference_slice = self.properties(self.temperature, np.full(len(self.temperature), self.pref))["u"]
        for array in (self.temperature, self.pressure, self.rho, self.u, self.k, self.u_reference_slice):
            array.flags.writeable = False

    def properties(self, temperature, pressure):
        t, p = np.broadcast_arrays(np.asarray(temperature, dtype=float), np.asarray(pressure, dtype=float))
        if (not np.isfinite(t).all() or not np.isfinite(p).all()
                or np.any(t < self.temperature[0]) or np.any(t > self.temperature[-1])
                or np.any(p < self.pressure[0]) or np.any(p > self.pressure[-1])):
            raise EOSDomainError("EOS state outside actual table domain; extrapolation is forbidden",
                                 {"trial_T_K": t.tolist(), "trial_p_Pa": p.tolist()})
        i = np.searchsorted(self.temperature, t, side="right")-1
        j = np.searchsorted(self.pressure, p, side="right")-1
        # Last-knot indices select the final valid cell, not a clipped state.
        i = np.minimum(i, len(self.temperature)-2)
        j = np.minimum(j, len(self.pressure)-2)
        dt, dp = self.temperature[i+1]-self.temperature[i], self.pressure[j+1]-self.pressure[j]
        a, b = (t-self.temperature[i])/dt, (p-self.pressure[j])/dp
        result = {"T": t, "p": p}
        for name, table in (("rho", self.rho), ("u", self.u)):
            v00, v10, v01, v11 = table[i, j], table[i+1, j], table[i, j+1], table[i+1, j+1]
            result[name] = (1-a)*((1-b)*v00+b*v01)+a*((1-b)*v10+b*v11)
            result[name+"_T"] = ((1-b)*(v10-v00)+b*(v11-v01))/dt
            result[name+"_p"] = ((1-a)*(v01-v00)+a*(v11-v10))/dp
        result["h"] = result["u"] + p/result["rho"]
        result["dh_dT"] = result["u_T"] - p*result["rho_T"]/result["rho"]**2
        result["k"] = np.interp(t, self.temperature, self.k)
        return result

    def invert(self, density, specific_internal_energy):
        """Bracket pressure on the exact iso-u curve, then use safeguarded Newton.

        Infeasible density/energy pairs are certified against EOS boundary
        densities, not misreported as arbitrary Newton iteration failures.
        No input mass/energy, returned temperature or pressure is projected.
        """
        density, energy = np.broadcast_arrays(np.asarray(density, dtype=float),
                                             np.asarray(specific_internal_energy, dtype=float))
        if (not np.isfinite(density).all() or not np.isfinite(energy).all() or np.min(density) <= 0
                or np.any(energy < self.u.min()) or np.any(energy > self.u.max())):
            raise EOSDomainError("Invalid or unsupported EOS inversion target")
        shape = density.shape
        density, energy = density.ravel(), energy.ravel()
        lower = np.full(energy.shape, self.pressure[0])
        upper = np.full(energy.shape, self.pressure[-1])
        low_cross = energy < self.u[0, 0]
        high_cross = energy > self.u[-1, -1]
        lower[low_cross] = np.interp(energy[low_cross], self.u[0, ::-1], self.pressure[::-1])
        upper[high_cross] = np.interp(energy[high_cross], self.u[-1, ::-1], self.pressure[::-1])
        if np.any(lower > upper):
            raise EOSDomainError("Energy target has no pressure bracket in the EOS domain")

        def along_iso_u(pressure):
            j = np.minimum(np.searchsorted(self.pressure, pressure, side="right")-1, len(self.pressure)-2)
            b = (pressure-self.pressure[j])/(self.pressure[j+1]-self.pressure[j])
            u_knots = self.u[:, j]*(1-b)+self.u[:, j+1]*b
            i = np.minimum(np.sum(u_knots <= energy[None, :], axis=0)-1, len(self.temperature)-2)
            if np.any(i < 0):
                raise EOSDomainError("No in-domain temperature on the specified iso-u curve")
            col = np.arange(len(energy))
            fraction = (energy-u_knots[i, col])/(u_knots[i+1, col]-u_knots[i, col])
            temperature = (1-fraction)*self.temperature[i]+fraction*self.temperature[i+1]
            return self.properties(temperature, pressure)

        lo, hi = along_iso_u(lower), along_iso_u(upper)
        tolerance = 5e-11  # Algebraic rho solve accuracy, not a scientific mass gate.
        outside = (density < lo["rho"]-tolerance) | (density > hi["rho"]+tolerance)
        if np.any(outside):
            raise EOSDomainError("Density/internal-energy target has no in-domain EOS solution", {
                "target_density_kg_m3": density.tolist(), "target_u_J_kg": energy.tolist(),
                "admissible_density_lower_kg_m3": lo["rho"].tolist(),
                "admissible_density_upper_kg_m3": hi["rho"].tolist(),
                "infeasible_indices": np.flatnonzero(outside).tolist()})
        width = hi["rho"]-lo["rho"]
        pressure = np.where(width > 0, lower+(density-lo["rho"])/np.where(width > 0, width, 1.)*(upper-lower), lower)
        # Roundoff at a bracket endpoint affects only the initial guess, never
        # the conserved target. Endpoint props still have to satisfy it.
        pressure = np.maximum(lower, np.minimum(upper, pressure))
        for _ in range(20):
            props = along_iso_u(pressure)
            residual = props["rho"]-density
            if np.max(abs(residual)) <= tolerance:
                return {key: value.reshape(shape) for key, value in props.items()}
            lower = np.where(residual < 0, pressure, lower)
            upper = np.where(residual > 0, pressure, upper)
            slope = props["rho_p"]-props["rho_T"]*props["u_p"]/props["u_T"]
            candidate = pressure-residual/slope
            pressure = np.where((candidate > lower) & (candidate < upper), candidate, .5*(lower+upper))
        raise ValueError("Bracketed EOS inversion failed; preserve the conserved targets")


@dataclass(frozen=True)
class EnthalpyBed:
    geometry: Bed
    eos: TabulatedEOS
    Nu: float = 3.66
    hydraulic_diameter_m: float = .001
    surface_area_m2: float = 1.

    def __post_init__(self):
        if self.geometry.periodic or self.geometry.slope_limiter != "MC":
            raise ValueError("This active open-bed contract requires explicit MC reconstruction")
        if not np.isfinite([self.Nu, self.hydraulic_diameter_m, self.surface_area_m2]).all() or min(
                self.Nu, self.hydraulic_diameter_m, self.surface_area_m2) <= 0:
            raise ValueError("Invalid conjugate heat-transfer geometry")

    @property
    def nodes(self):
        return self.geometry.nodes

    @property
    def volume(self):
        return self.geometry.fluid_area_m2*self.geometry.dx

    @property
    def state_size(self):
        return 3*self.nodes+2

    def initial_state(self):
        density = float(self.eos.properties([self.eos.Tref], [self.eos.pref])["rho"][0])
        return np.r_[np.full(self.nodes, density*self.volume), np.zeros(2*self.nodes+2)]

    def unpack(self, state):
        n = self.nodes
        mass = state[:n]
        if state.shape != (self.state_size,) or np.any(mass <= 0) or not np.isfinite(state).all():
            raise ValueError("Invalid conservative state")
        props = self.eos.invert(mass/self.volume, state[n:2*n]/mass+self.eos.uref)
        props["solid_T"] = self.eos.Tref+state[2*n:3*n]/self.geometry.solid_capacity
        return props

    def evaluate(self, state, mdot_command, left_K, right_K):
        if not np.isfinite([mdot_command, left_K, right_K]).all() or mdot_command == 0:
            raise ValueError("Active prescribed-inlet contract excludes sealed/zero-flow dwell; use a pressure/compliance closure")
        n = self.nodes
        props = self.unpack(state)
        fluid_T, solid_T = props["T"], props["solid_T"]
        exchange = self.Nu*props["k"]*self.surface_area_m2/(n*self.hydraulic_diameter_m)*(solid_T-fluid_T)
        conductance = 2*props["k"][:-1]*props["k"][1:]/(props["k"][:-1]+props["k"][1:])
        fluid_conduction = np.r_[0., -conductance*self.geometry.fluid_area_m2*np.diff(fluid_T)/self.geometry.dx, 0.]
        solid_conduction = conductive_faces(solid_T, self.geometry.solid_k_W_mK*self.geometry.solid_area_m2/self.geometry.dx)
        heat = fluid_conduction[:-1]-fluid_conduction[1:]+exchange
        solid_power = solid_conduction[:-1]-solid_conduction[1:]-exchange
        boundary_T = right_K if mdot_command < 0 else left_K
        inlet = self.eos.properties([boundary_T], [self.eos.pref])
        inlet_h = float(inlet["h"][0]-self.eos.uref)
        enthalpy = props["h"]-self.eos.uref
        mass_T = self.volume*props["rho_T"]
        energy_T = self.volume*(props["rho_T"]*(props["u"]-self.eos.uref)+props["rho"]*props["u_T"])
        if np.any(energy_T <= 0):
            raise ValueError("Nonmonotone local energy/temperature coordinate")
        if mdot_command < 0:
            enthalpy, mass_T, energy_T, heat = (v[::-1] for v in (enthalpy, mass_T, energy_T, heat))
        h_face = advective_faces(enthalpy, 1., inlet_h, 0., limiter="MC")
        flow = np.empty(n+1)
        flow[0] = abs(mdot_command)
        energy_rate = np.empty(n)
        mass_rate = np.empty(n)
        for i in range(n):
            ratio = mass_T[i]/energy_T[i]
            denominator = 1-ratio*h_face[i+1]
            if denominator <= 0:
                raise ValueError("Nonpositive constant-pressure outflow denominator")
            flow[i+1] = (flow[i]-ratio*(flow[i]*h_face[i]+heat[i]))/denominator
            if flow[i+1] <= 0:
                raise ValueError("Thermal-expansion flow changes donor direction; this active contract is no longer applicable")
            mass_rate[i] = flow[i]-flow[i+1]
            energy_rate[i] = flow[i]*h_face[i]-flow[i+1]*h_face[i+1]+heat[i]
        boundary_mass = flow[0]-flow[-1]
        boundary_energy = flow[0]*h_face[0]-flow[-1]*h_face[-1]
        if mdot_command < 0:
            mass_rate, energy_rate = mass_rate[::-1], energy_rate[::-1]
            flow, h_face = -flow[::-1], h_face[::-1]
        derivative = np.r_[mass_rate, energy_rate, solid_power, boundary_mass, boundary_energy]
        # Recover dp/dt from both conservative rates, independently of the
        # outflow recurrence's ratio form; this is a differential identity.
        mT = self.volume*props["rho_T"]
        mp = self.volume*props["rho_p"]
        eT = self.volume*(props["rho_T"]*(props["u"]-self.eos.uref)+props["rho"]*props["u_T"])
        ep = self.volume*(props["rho_p"]*(props["u"]-self.eos.uref)+props["rho"]*props["u_p"])
        pressure_rate = (mT*energy_rate-eT*mass_rate)/(mT*ep-mp*eT)
        return derivative, {**props, "mass_faces_kg_s": flow, "enthalpy_faces_relative_J_kg": h_face,
                            "pressure_rate_Pa_s": pressure_rate, "exchange_W": exchange}

    def rhs(self, state, mdot_command, left_K, right_K):
        return self.evaluate(state, mdot_command, left_K, right_K)[0]
