import unittest
import numpy as np

from Analyze_HeatDriveECC_UniformPipeOperator import normalized_flux


class UniformPipeOperatorTests(unittest.TestCase):
    def test_heat_sign_and_zero_temperature_difference(self):
        for ntu in (.001, .1, 30., 60.):
            plus, minus, zero = (normalized_flux(ntu, 3.66, delta) for delta in (1., -1., 0.))
            for key in plus:
                self.assertEqual(minus[key], -plus[key])
                self.assertEqual(zero[key], 0.)

    def test_small_ntu_limit_contains_extra_conduction(self):
        row = normalized_flux(1e-12, 3.66, 1.)
        self.assertAlmostEqual(row["native_total_Q_over_UA_K"], 1 + 1 / 3.66, places=11)

    def test_finite_ntu_can_reduce_total_below_reference(self):
        row = normalized_flux(10., 3.66, 1.)
        self.assertLess(row["native_total_Q_over_UA_K"], row["reference_Q_over_UA_K"])

    def test_ntu_cap_changes_exponent_not_mass_capacity(self):
        row = normalized_flux(60., 3.66, 1.)
        self.assertAlmostEqual(row["native_directional_Qconv_over_UA_K"], (1 - np.exp(-30.)) / 60.)
        self.assertNotAlmostEqual(row["native_directional_Qconv_over_UA_K"], (1 - np.exp(-30.)) / 30.)

    def test_invalid_parameters_rejected(self):
        for values in ((0., 3.66, 1.), (-1., 3.66, 1.), (1., 0., 1.), (1., 3.66, np.nan)):
            with self.assertRaises(ValueError):
                normalized_flux(*values)


if __name__ == "__main__":
    unittest.main()
