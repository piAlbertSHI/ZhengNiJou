import unittest

import numpy as np
from scipy.interpolate import RegularGridInterpolator

from Analyze_HeatDriveECC_ChamberChainRule import chord_integrals, split_endpoint_error


def properties():
    temperature = np.array([250.0, 300.0, 350.0])
    pressure = np.array([1e5, 1e6, 2e6])
    shape = (len(temperature), len(pressure))
    values = {
        "rho": np.full(shape, 1000.0),
        "u": 500.0 * temperature[:, None] + np.zeros(shape),
        "cp": np.full(shape, 500.0),
        "alpha": np.zeros(shape),
        "beta": np.full(shape, 2e9),
    }
    return {k: RegularGridInterpolator((temperature, pressure), v) for k, v in values.items()}


class ChamberChainRuleTests(unittest.TestCase):
    def test_constant_coefficients_known_integral(self):
        table = properties()
        states = np.array([[260.0, 2e5], [340.0, 1.8e6]])
        volume = 1e-6
        energy, mass, count = chord_integrals(table, states, volume)
        dtemp, dp = states[1] - states[0]
        expected = volume * (1000 * 500 * dtemp + dp / 2e9 * (
            1000 * 500 * states[:, 0].mean() + states[:, 1].mean()))
        self.assertAlmostEqual(energy[0], expected, places=12)
        self.assertAlmostEqual(mass[0], volume * 1000 / 2e9 * dp, places=16)
        self.assertEqual(count, 2)

    def test_reversing_chord_reverses_integrals(self):
        states = np.array([[260.0, 2e5], [340.0, 1.8e6]])
        forward = chord_integrals(properties(), states, 1e-6)
        reverse = chord_integrals(properties(), states[::-1], 1e-6)
        np.testing.assert_allclose(forward[0], -reverse[0], rtol=0, atol=1e-12)
        np.testing.assert_allclose(forward[1], -reverse[1], rtol=0, atol=1e-18)

    def test_stationary_sample_is_zero(self):
        energy, mass, _ = chord_integrals(properties(), [[300, 1e6], [300, 1e6]], 1e-6)
        np.testing.assert_array_equal(energy, [0])
        np.testing.assert_array_equal(mass, [0])

    def test_temperature_knot_is_split_before_integration(self):
        table = properties()
        table["cp"] = RegularGridInterpolator(
            table["rho"].grid, np.array([1000.0, 5000.0, 2000.0])[:, None] + np.zeros((3, 3)))
        states = np.array([[260.0, 4e5], [340.0, 4e5]])
        energy, _, count = chord_integrals(table, states, 1e-6)
        knots = np.array([260.0, 300.0, 340.0])
        cp = np.interp(knots, [250.0, 300.0, 350.0], [1000.0, 5000.0, 2000.0])
        expected = .001 * np.sum((cp[:-1] + cp[1:]) * .5 * np.diff(knots))
        self.assertAlmostEqual(energy[0], expected, places=11)
        self.assertEqual(count, 2)

    def test_four_and_five_point_gauss_on_bilinear_fields(self):
        table = properties()
        t, p = np.meshgrid(*table["rho"].grid, indexing="ij")
        fields = dict(rho=1000 - .2 * (t - 300) + 1e-6 * (p - 1e6),
                      u=500 * t + 1e-4 * p + 2e-7 * t * p,
                      cp=4000 + .1 * t + 1e-6 * p,
                      alpha=1e-4 + 1e-7 * t + 1e-11 * p)
        for key, values in fields.items():
            table[key] = RegularGridInterpolator(table["rho"].grid, values)
        states = [[251, 1.1e5], [349, 1.9e6], [270, 4e5]]
        a = chord_integrals(table, states, 1e-6, 4)
        b = chord_integrals(table, states, 1e-6, 5)
        np.testing.assert_allclose(a[0], b[0], rtol=0, atol=1e-10)
        np.testing.assert_allclose(a[1], b[1], rtol=0, atol=1e-17)

    def test_nonconstant_bulk_modulus_is_not_declared_polynomial(self):
        table = properties()
        values = table["beta"].values.copy()
        values[0, 0] += 1e8
        table["beta"] = RegularGridInterpolator(table["rho"].grid, values)
        with self.assertRaises(ValueError):
            chord_integrals(table, [[260, 2e5], [340, 1.8e6]], 1e-6)

    def test_no_extrapolation(self):
        with self.assertRaises(ValueError):
            chord_integrals(properties(), [[240, 2e5], [340, 1.8e6]], 1e-6)

    def test_invalid_shape_volume_and_order(self):
        for states, volume, order in (
                ([[300, 1e6]], 1e-6, 4), ([[300, np.nan], [310, 1e6]], 1e-6, 4),
                ([[300, 1e6], [310, 1e6]], 0, 4),
                ([[300, 1e6], [310, 1e6]], 1e-6, 2)):
            with self.assertRaises(ValueError):
                chord_integrals(properties(), states, volume, order)

    def test_signed_cancellation_does_not_erase_absolute_defects(self):
        result = split_endpoint_error([1, -1], [1, -1], [1, -1], [0, 0])
        self.assertEqual(result["assumed_chord_coefficients_vs_inventory"], 0)
        self.assertEqual(result["absolute_interval_property_term_sum"], 2)
        self.assertEqual(result["max_interval_identity_error"], 0)

    def test_three_part_decomposition_keeps_original_endpoint_residual(self):
        result = split_endpoint_error([7, 4], [6, 3], [5, 2], [4, 1])
        self.assertEqual(result["endpoint_residual"], 6)
        self.assertEqual(result["solver_equation_residual"], 2)
        self.assertEqual(result["right_endpoint_vs_assumed_chord"], 2)
        self.assertEqual(result["assumed_chord_coefficients_vs_inventory"], 2)
        self.assertEqual(result["max_interval_identity_error"], 0)


if __name__ == "__main__":
    unittest.main()
