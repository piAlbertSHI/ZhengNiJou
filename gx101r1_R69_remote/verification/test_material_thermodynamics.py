import unittest

import numpy as np
from scipy.integrate import quad

from Reference_HeatDriveECC_MaterialThermodynamics import MaterialThermodynamics


def probe(equal_moduli=False):
    # Synthetic equation probes, not calibration of any Qian alloy.
    return MaterialThermodynamics(35e9, 35e9 if equal_moduli else 25e9,
                                  .03, 6500., 500., 180e6, 320., 7.45e6)


class MaterialEnergyTests(unittest.TestCase):
    def test_explicit_parameters_and_domains(self):
        with self.assertRaises(TypeError):
            MaterialThermodynamics(30e9, 30e9)
        for args in ((0., .03, .5), (320., .03, -.01), (320., .03, 1.01), (320., np.nan, .5)):
            with self.assertRaises(ValueError):
                probe().evaluate(*args)
        with self.assertRaises(ValueError):
            probe().temperature_rate(320., .03, .5, 0., 0., 0.)

    def test_free_energy_derivatives_and_legendre_identity(self):
        m = probe()
        t, e, x = 335., .037, .43
        s = m.evaluate(t, e, x)
        for axis, h, expected in ((0, 1e-3, -s["entropy_J_m3K"]),
                                  (1, 1e-7, s["stress_Pa"]),
                                  (2, 1e-5, -s["affinity_J_m3"])):
            hi, lo = [t, e, x], [t, e, x]
            hi[axis] += h
            lo[axis] -= h
            derivative = (m.evaluate(*hi)["free_energy_J_m3"]-m.evaluate(*lo)["free_energy_J_m3"])/(2*h)
            np.testing.assert_allclose(derivative, expected, rtol=2e-8)
        np.testing.assert_allclose(s["internal_energy_J_m3"], s["free_energy_J_m3"]+t*s["entropy_J_m3K"], rtol=3e-15)

    def test_internal_energy_gradients_match_heat_law(self):
        m = probe()
        t, e, x = 335., .037, .43
        s = m.evaluate(t, e, x)
        for axis, h, expected in ((0, 1e-3, s["effective_capacity_J_m3K"]),
                                  (1, 1e-7, s["stress_Pa"]), (2, 1e-5, -s["latent_x_J_m3"])):
            hi, lo = [t, e, x], [t, e, x]
            hi[axis] += h
            lo[axis] -= h
            derivative = (m.evaluate(*hi)["internal_energy_J_m3"]-m.evaluate(*lo)["internal_energy_J_m3"])/(2*h)
            np.testing.assert_allclose(derivative, expected, rtol=2e-8)

    def test_equal_moduli_reduces_to_constant_chemical_term_plus_transformation_work(self):
        m = probe(True)
        for t in (270., 320., 380.):
            s = m.evaluate(t, .035, .4)
            chemical = m.transformation_strain*(m.maxwell_slope_Pa_K*m.reference_temperature_K-m.maxwell_reference_stress_Pa)
            self.assertEqual(float(s["latent_t_J_m3K"]), 0.)
            self.assertAlmostEqual(float(s["latent_x_J_m3"]), chemical+m.transformation_strain*s["stress_Pa"], places=7)

    def test_closed_path_has_zero_heat_plus_work(self):
        m = probe()
        def powers(t):
            temp, strain, phase = 330+25*np.cos(t), .035+.006*np.sin(2*t), .45+.25*np.sin(t+.3)
            td, ed, xd = -25*np.sin(t), .012*np.cos(2*t), .25*np.cos(t+.3)
            s = m.evaluate(temp, strain, phase)
            return (s["effective_capacity_J_m3K"]*td-s["latent_x_J_m3"]*xd,
                    s["stress_Pa"]*ed)
        q = quad(lambda t: powers(t)[0], 0., 2*np.pi, epsabs=1e-4, epsrel=1e-11)[0]
        w = quad(lambda t: powers(t)[1], 0., 2*np.pi, epsabs=1e-4, epsrel=1e-11)[0]
        self.assertGreater(abs(w), 1e4)
        self.assertLess(abs(q+w), 1e-6)

    def test_affinity_vanishes_at_maxwell_stress_not_a_stage_label(self):
        m = probe()
        for x in (0., .4, 1.):
            t = 330.
            mw = m.maxwell_reference_stress_Pa+m.maxwell_slope_Pa_K*(t-m.reference_temperature_K)
            strain = .03*x+mw*(x/m.young_m_Pa+(1-x)/m.young_a_Pa)
            self.assertLess(abs(float(m.evaluate(t, strain, x)["affinity_J_m3"])), 1e-8)

    def test_nonpositive_capacity_is_rejected_not_floored(self):
        m = MaterialThermodynamics(25e9, 100e9, .03, 6500., 1., 180e6, 320., 10e6)
        with self.assertRaises(ValueError):
            m.temperature_rate(350., .03, 0., 0., 0., 1e-6)

    def test_reference_cannot_be_switched_from_austenite_to_martensite_silently(self):
        s = probe().evaluate(335., .037, 0.)
        self.assertNotEqual(float(s["latent_t_J_m3K"]), 0.)
        self.assertGreater(float(s["effective_capacity_J_m3K"]), 0.)


if __name__ == "__main__":
    unittest.main()
