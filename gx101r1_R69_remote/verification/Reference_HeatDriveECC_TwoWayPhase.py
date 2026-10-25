"""Stage-independent phase fluxes and a source-explicit MAS probability kernel.

Qian2017 Eqs8-11 / Qian2018 Eqs5-6 give the single-crystal rates. Critical
stresses, activation volume and relaxation time MUST be supplied, not inferred
from Table4. Polycrystal surfaces and disappearing wells are not supplied here.
The shared-surface control below is a structural ablation, NOT that MAS model.
"""
from dataclasses import dataclass

import numpy as np
from scipy.special import erfcx, log_ndtr

from Reference_HeatDriveECC_CaloricCoupling import CaloricCycle, compatibility


def two_way_rate(phase, forward, reverse):
    x, plus, minus = np.broadcast_arrays(phase, forward, reverse)
    if (not all(np.isfinite(v).all() for v in (x, plus, minus))
            or np.any(plus < 0) or np.any(minus < 0)):
        raise ValueError("Finite phase coordinates and nonnegative two-way coefficients required")
    return plus*(1-x)-minus*x


def frozen_coefficient_step(phase, forward, reverse, duration):
    """Exact scalar two-state Markov evolution at FROZEN coefficients only.

    Not a coupled-system integrator: changing stress/T require simultaneous
    treatment. This independent analytic solution is a numerical test oracle.
    """
    x, plus, minus = np.broadcast_arrays(phase, forward, reverse)
    two_way_rate(x, plus, minus)
    if not np.isfinite(duration) or duration < 0 or np.any(x < 0) or np.any(x > 1):
        raise ValueError("Invalid frozen material initial value or duration")
    total = plus+minus
    if not np.isfinite(total).all():
        raise ValueError("Unrepresentable total phase coefficient")
    ratio = np.divide(plus, total, out=np.zeros_like(total, dtype=float), where=total > 0)
    change = -np.expm1(-total*duration)
    return (1-change)*x+change*ratio


@dataclass(frozen=True)
class SingleCrystalMAS:
    young_a_Pa: float
    young_m_Pa: float
    activation_volume_m3: float
    relaxation_time_s: float

    def __post_init__(self):
        values = (self.young_a_Pa, self.young_m_Pa, self.activation_volume_m3, self.relaxation_time_s)
        if not np.isfinite(values).all() or min(values) <= 0:
            raise ValueError("All dimensional MAS inputs must be explicitly finite and positive")

    def coefficients(self, temperature_K, stress_Pa, critical_a_Pa, critical_m_Pa):
        """Thermally activated two-positive-well branch, all inputs in SI.

        sigma_A must be strictly positive for the interval-normalization formula.
        No clipping of sigma_A, arbitrary pole floor, rate cap or substituted
        single-well branch is allowed; other branches require a separate model.
        """
        t, s, ca, cm = np.broadcast_arrays(temperature_K, stress_Pa, critical_a_Pa, critical_m_Pa)
        if (not all(np.isfinite(v).all() for v in (t, s, ca, cm))
                or np.any(t <= 0) or np.any(s < 0) or np.any(ca <= 0) or np.any(cm <= 0)):
            raise ValueError("Outside declared positive-critical-stress MAS branch")
        kb = 1.380649e-23  # Exact SI Boltzmann constant.
        a = self.young_a_Pa*self.activation_volume_m3/(2*kb*t)
        b = self.young_m_Pa*self.activation_volume_m3/(2*kb*t)
        za = np.sqrt(a)*(ca-s)/self.young_a_Pa
        zplus = np.sqrt(a)*(ca+s)/self.young_a_Pa
        zm = np.sqrt(b)*(cm-s)/self.young_m_Pa
        # erf(za)+erf(zplus) = 2*(Phi(sqrt2*za)-Phi(-sqrt2*zplus)).
        # Lower CDF never exceeds the upper for ca>0. log/expm1 avoids
        # cancellation and underflow of the original numerator/denominator.
        upper, lower = log_ndtr(np.sqrt(2)*za), log_ndtr(-np.sqrt(2)*zplus)
        log_interval = upper+np.log(-np.expm1(lower-upper))
        log_forward = -za*za-np.log(2.)-log_interval-np.log(self.relaxation_time_s)
        log_reverse = -np.log(erfcx(zm))-np.log(self.relaxation_time_s)
        with np.errstate(over="ignore", under="ignore"):
            plus, minus = np.exp(log_forward), np.exp(log_reverse)
        if (not np.isfinite(plus).all() or not np.isfinite(minus).all()):
            raise ValueError("Unresolved or unrepresentable MAS probability; do not cap it")
        return plus, minus


def shared_surface_coefficients(temperature, phase, stress, material, width, forward_rate, reverse_rate):
    """Existing reduced coefficients, evaluated BOTH ways without a stage flag."""
    surface = material["T_As_K"]+(material["T_Ms_K"]-material["T_As_K"])*phase
    forward_drive = stress-material["C_M_Pa_per_K"]*(temperature-surface)
    reverse_drive = material["C_A_Pa_per_K"]*(temperature-surface)-stress
    forward = forward_rate*(-np.expm1(-np.maximum(forward_drive, 0)/width))
    reverse = reverse_rate*(-np.expm1(-np.maximum(reverse_drive, 0)/width))
    return forward, reverse


def shared_surface_rates(p, mechanical, c):
    k = c["kinetics"]
    a = shared_surface_coefficients(p["Ta"], p["xa"], mechanical["sigma_a_Pa"], c["materials"]["SMA"],
        k["drive_width_a_Pa"], k["rate_a_to_M_1_per_s"], k["rate_a_to_A_1_per_s"])
    r = shared_surface_coefficients(p["Tr"], p["xr"], mechanical["sigma_r_Pa"], c["materials"]["SE"],
        k["drive_width_r_Pa"], k["rate_r_load_1_per_s"], k["rate_r_stage3_unload_1_per_s"])
    return two_way_rate(p["xa"], *a), two_way_rate(p["xr"], *r)


class TwoWaySharedSurfaceCycle(CaloricCycle):
    """Same thermal graph, two-way reduced phase fluxes; uncalibrated ablation.

    Correct all phase-dependent heat/work together. Do not patch only dx/dt
    while leaving the scheduled phase powers in the energy equations.
    """
    def evaluate(self, y, stage):
        d, p, old = super().evaluate(y, stage)
        rates = shared_surface_rates(p, old, self.c)
        new = compatibility(p["xa"], p["xr"], self.c["geometry"], self.c["materials"], rates)
        for material, phase, solid, work, rate, indices in (
            ("SMA", "phase_a", "solid_a", "mechanical_a_W", rates[0], (3, 5)),
            ("SE", "phase_r", "solid_r", "mechanical_r_W", rates[1], (4, 6))):
            latent_factor = self.c["solid_mass_kg"][material]*self.c["materials"][material]["Delta_h_J_per_kg"]/self.n
            change = rate-d[self.slices[phase]]
            d[self.slices[solid]] += latent_factor*change+new[work]-old[work]
            d[self.slices[phase]] = rate
            d[self.slices["ledgers"]][indices[0]] = latent_factor*rate.sum()
            d[self.slices["ledgers"]][indices[1]] = new[work].sum()
        return d, p, new
