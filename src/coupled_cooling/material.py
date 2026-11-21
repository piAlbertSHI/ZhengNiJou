"""Independent material energy closure, NOT an identified Qian constitutive law.

Mandolino et al., doi:10.1109/LRA.2021.3067254, Eqs1,9,11-16.
The potentials below are derived by integrating those equations. Parameters
must be explicit; no Q01 constants, activation law, branch memory or production
state is imported. Prescribing x(t) is an equation test, not phase kinetics.
"""
from dataclasses import dataclass

import numpy as np


@dataclass(frozen=True)
class MaterialThermodynamics:
    young_a_Pa: float
    young_m_Pa: float
    transformation_strain: float
    density_kg_m3: float
    heat_capacity_J_kgK: float
    maxwell_reference_stress_Pa: float
    reference_temperature_K: float
    maxwell_slope_Pa_K: float

    def __post_init__(self):
        values = tuple(self.__dict__.values())
        positive = (self.young_a_Pa, self.young_m_Pa, self.transformation_strain,
                    self.density_kg_m3, self.heat_capacity_J_kgK,
                    self.reference_temperature_K, self.maxwell_slope_Pa_K)
        if not np.isfinite(values).all() or min(positive) <= 0:
            raise ValueError("Explicit finite material inputs and positive dimensional scales required")

    def gamma(self, stress):
        compliance_change = 1/self.young_m_Pa-1/self.young_a_Pa
        return .5*compliance_change*stress**2+self.transformation_strain*stress

    def evaluate(self, temperature_K, strain, martensite):
        t, e, x = np.broadcast_arrays(temperature_K, strain, martensite)
        if (not all(np.isfinite(v).all() for v in (t, e, x))
                or np.any(t <= 0) or np.any(x < 0) or np.any(x > 1)):
            raise ValueError("Finite coordinates, positive temperature and physical phase required; no clipping")
        da, dm = 1/self.young_a_Pa, 1/self.young_m_Pa
        d = da+(dm-da)*x
        stress = (e-self.transformation_strain*x)/d
        mw = self.maxwell_reference_stress_Pa+self.maxwell_slope_Pa_K*(t-self.reference_temperature_K)
        gamma = self.gamma(mw)
        gamma_t = ((dm-da)*mw+self.transformation_strain)*self.maxwell_slope_Pa_K
        gamma_tt = (dm-da)*self.maxwell_slope_Pa_K**2
        cv = self.density_kg_m3*self.heat_capacity_J_kgK
        elastic = .5*d*stress**2
        # Austenite chemical reference (x-1) reproduces the paper's LT factor.
        # Replacing it with x silently changes the caloric reference for EA != EM.
        free = elastic+(x-1)*gamma+cv*(t-self.reference_temperature_K-t*np.log(t/self.reference_temperature_K))
        entropy = cv*np.log(t/self.reference_temperature_K)-(x-1)*gamma_t
        internal = elastic+(x-1)*(gamma-t*gamma_t)+cv*(t-self.reference_temperature_K)
        affinity = self.gamma(stress)-gamma
        latent_x = t*gamma_t+affinity
        latent_t = t*gamma_tt*(x-1)
        result = {"stress_Pa": stress, "maxwell_stress_Pa": mw,
                  "free_energy_J_m3": free, "entropy_J_m3K": entropy,
                  "internal_energy_J_m3": internal, "affinity_J_m3": affinity,
                  "latent_x_J_m3": latent_x, "latent_t_J_m3K": latent_t,
                  "effective_capacity_J_m3K": cv-latent_t}
        if not all(np.isfinite(v).all() for v in result.values()):
            raise ValueError("Unrepresentable material energy; no numerical cap substituted")
        return result

    def temperature_rate(self, temperature_K, strain, martensite, phase_rate_s, heat_W, volume_m3):
        if not np.isfinite(volume_m3) or volume_m3 <= 0:
            raise ValueError("Positive finite material volume required")
        state = self.evaluate(temperature_K, strain, martensite)
        if (not np.isfinite(phase_rate_s).all() or not np.isfinite(heat_W).all()
                or np.any(state["effective_capacity_J_m3K"] <= 0)):
            raise ValueError("Invalid forcing or nonpositive thermodynamic heat capacity; do not floor")
        return (np.asarray(heat_W)/volume_m3+state["latent_x_J_m3"]*phase_rate_s)/state["effective_capacity_J_m3K"]
