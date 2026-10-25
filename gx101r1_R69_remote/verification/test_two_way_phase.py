import unittest

import numpy as np
from scipy.integrate import quad, solve_ivp
from scipy.special import erf, erfc

from Reference_HeatDriveECC_TwoWayPhase import (SingleCrystalMAS, two_way_rate, frozen_coefficient_step,
                                                TwoWaySharedSurfaceCycle)
import test_caloric_cycle as fixture


class TwoWayTests(unittest.TestCase):
    def test_two_fluxes_not_a_stage_selected_sign(self):
        self.assertAlmostEqual(float(two_way_rate(.5, 3., 7.)), -2.)
        self.assertEqual(float(two_way_rate(0., 3., 7.)), 3.)
        self.assertEqual(float(two_way_rate(1., 3., 7.)), -7.)

    def test_equilibrium_and_zero_drive_are_not_reset(self):
        np.testing.assert_allclose(frozen_coefficient_step([.3, .8], [0., 2.], [0., 3.], 100.), [.3, .4], atol=1e-15)
        self.assertAlmostEqual(float(two_way_rate(.4, 2., 3.)), 0., places=14)

    def test_exact_frozen_solution_matches_independent_ODE(self):
        expected = frozen_coefficient_step(.8, 2., 7., 1.)
        actual = solve_ivp(lambda t, y: 2*(1-y)-7*y, (0, 1), [.8], method="DOP853", rtol=1e-12, atol=1e-14).y[0, -1]
        self.assertAlmostEqual(float(expected), actual, places=12)

    def test_missing_MAS_material_inputs_and_invalid_domains_rejected(self):
        with self.assertRaises(TypeError):
            SingleCrystalMAS(30e9, 30e9)
        with self.assertRaises(ValueError):
            SingleCrystalMAS(30e9, 30e9, -1., .1)
        model = SingleCrystalMAS(30e9, 30e9, 3e-26, .1)
        for t, s, a, b in ((0., 1e8, 1e8, 2e8), (300., -1., 1e8, 2e8), (300., 1e8, 0., 2e8), (300., 1e8, 1e8, -1.)):
            with self.assertRaises(ValueError):
                model.coefficients(t, s, a, b)

    def test_MAS_moderate_values_match_published_erf_form(self):
        model = SingleCrystalMAS(30e9, 40e9, 3e-26, .1)
        t, stress, ca, cm = 303.15, np.array([0., 1e8, 2e8, 3e8]), 2e8, 1.5e8
        a = model.young_a_Pa*model.activation_volume_m3/(2*1.380649e-23*t)
        b = model.young_m_Pa*model.activation_volume_m3/(2*1.380649e-23*t)
        z = np.sqrt(a)*(ca-stress)/model.young_a_Pa
        q = np.sqrt(a)*(ca+stress)/model.young_a_Pa
        w = np.sqrt(b)*(cm-stress)/model.young_m_Pa
        actual = model.coefficients(t, stress, ca, cm)
        np.testing.assert_allclose(actual[0], np.exp(-z*z)/(erf(z)+erf(q))/.1, rtol=3e-12)
        np.testing.assert_allclose(actual[1], np.exp(-w*w)/erfc(w)/.1, rtol=3e-12)

    def test_MAS_large_forward_drive_avoids_zero_over_zero(self):
        model = SingleCrystalMAS(30e9, 30e9, 1e-24, .1)
        plus, minus = model.coefficients(303.15, 1.5e9, 2e8, 1e8)
        self.assertTrue(np.isfinite(plus))
        self.assertGreater(plus, 100.)
        self.assertGreaterEqual(minus, 0.)

    def test_MAS_normalization_against_direct_interval_quadrature(self):
        model = SingleCrystalMAS(30e9, 30e9, 3e-26, .1)
        a = model.young_a_Pa*model.activation_volume_m3/(2*1.380649e-23*303.15)
        z1, z2 = np.sqrt(a)*(.2e9-.1e9)/30e9, np.sqrt(a)*(.2e9+.1e9)/30e9
        denominator = 2/np.sqrt(np.pi)*quad(lambda x: np.exp(-x*x), -z2, z1, epsabs=1e-14)[0]
        plus, _ = model.coefficients(303.15, .1e9, .2e9, .1e9)
        self.assertAlmostEqual(float(plus), float(np.exp(-z1*z1)/denominator/.1), places=12)


class TwoWayNetworkTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fixture.CoupledTests.setUpClass()
        cls.old = fixture.CoupledTests.model
        cls.new = TwoWaySharedSurfaceCycle(fixture.CoupledTests.contract, cls.old.fluids)

    def state(self):
        helper = fixture.CoupledTests()
        helper.model = self.old
        return helper.varied_state()

    def test_same_state_gives_same_phase_rate_at_all_four_stages(self):
        y = self.state()
        rates = [self.new.evaluate(y, stage)[0] for stage in (1, 2, 3, 4)]
        for name in ("phase_a", "phase_r"):
            for rate in rates[1:]:
                np.testing.assert_allclose(rate[self.new.slices[name]], rates[0][self.new.slices[name]], rtol=0, atol=0)

    def test_old_operator_is_detectably_stage_dependent(self):
        y = self.state()
        hot, cold = self.old.evaluate(y, 1)[0], self.old.evaluate(y, 3)[0]
        self.assertGreater(np.max(abs(hot[self.old.slices["phase_a"]]-cold[self.old.slices["phase_a"]])), .1)

    def test_phase_latent_work_and_inventory_are_changed_together(self):
        m, y = self.new, self.state()
        weights = np.zeros(m.size)
        for key in (*m.components, "solid_a", "solid_r", "buffer_H", "bus_E"):
            weights[m.slices[key]] = 1.
        for material, key in (("SMA", "phase_a"), ("SE", "phase_r")):
            weights[m.slices[key]] = -m.c["solid_mass_kg"][material]*m.c["materials"][material]["Delta_h_J_per_kg"]/m.n
        for stage in (1, 2, 3, 4):
            rate, _, mechanical = m.evaluate(y, stage)
            self.assertLess(abs(weights@rate-rate[m.slices["ledgers"]][:3].sum()), 2e-9)
            self.assertLess(abs(mechanical["mechanical_a_W"].sum()+mechanical["mechanical_r_W"].sum()), 1e-9)


if __name__ == "__main__":
    unittest.main()
