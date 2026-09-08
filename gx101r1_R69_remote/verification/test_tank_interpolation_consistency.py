"""Exact table integrals must not hide quadrature or property mismatch."""
import unittest
import numpy as np
from scipy.interpolate import RegularGridInterpolator

from Audit_HeatDriveECC_TankInterpolationConsistency import integrate_linear, enthalpy_derivative, analyze_path
from Audit_HeatDriveECC_TankStepRefinement import capacity_integral


class TankInterpolationTests(unittest.TestCase):
    def test_linear_integral(self):
        np.testing.assert_allclose(integrate_linear([0, 1, 2], [0, 2, 4], [0, .5], [2, 1.5]), [4, 2])

    def test_cross_knots_and_reverse(self):
        x = [0, 1, 2]; y = [1, 3, 1]
        np.testing.assert_allclose(integrate_linear(x, y, [0, 2, 1], [2, 0, 1]), [4, -4, 0])

    def test_outside_domain_rejected(self):
        with self.assertRaises(ValueError):
            integrate_linear([0, 1], [1, 1], [0], [2])

    def test_nonuniform_knots(self):
        self.assertAlmostEqual(float(integrate_linear([0, 2, 5], [1, 5, 11], .5, 4)), 19.25)

    def test_density_derivative_term(self):
        value = enthalpy_derivative([1, 3], [10, 30], [2, 4], 12, [2])
        np.testing.assert_allclose(value, [10-12/9])

    def test_cell_derivative_changes_at_knot(self):
        result = enthalpy_derivative([1, 2, 3], [1, 3, 7], [1, 1, 1], 0, [1.5, 2, 3])
        np.testing.assert_allclose(result, [2, 4, 4])

    def fixture(self, cp):
        grid = (np.array([1., 2., 3.]), np.array([1., 2.]))
        values = {'u': np.repeat(np.array([10., 20., 30.])[:, None], 2, axis=1),
                  'rho': np.ones((3, 2))*2, 'cp': np.repeat(np.asarray(cp)[:, None], 2, axis=1)}
        table = {k: RegularGridInterpolator(grid, v) for k, v in values.items()}
        temp = np.array([1.1, 1.5, 2.5, 2.9]); u = temp*10
        return table, temp, u

    def test_consistent_cp_has_no_table_mismatch(self):
        table, temp, u = self.fixture([10., 10., 10.])
        r, _ = analyze_path(table, 1, temp, np.ones(4), u+.5, np.full(4, 2.), u)
        self.assertAlmostEqual(r['exact_table_interpolation_term_J'], 0)
        self.assertAlmostEqual(r['BE_quadrature_term_J'], 0)

    def test_table_mismatch_survives_quadrature_refinement(self):
        table, temp, u = self.fixture([11., 12., 13.])
        r, _ = analyze_path(table, 1, temp, np.ones(4), u+.5, np.full(4, 2.), u)
        self.assertAlmostEqual(r['exact_table_interpolation_term_J'], 3.6)
        first, last = r['fixed_path_quadrature_refinements'][0], r['fixed_path_quadrature_refinements'][-1]
        self.assertAlmostEqual(first['weighted_quadrature_error_J']/64, last['weighted_quadrature_error_J'])
        self.assertFalse(r['physical_time_step_convergence_verified'])

    def test_wrong_native_enthalpy_rejected(self):
        table, temp, u = self.fixture([10., 10., 10.])
        with self.assertRaisesRegex(ValueError, 'Native properties'):
            analyze_path(table, 1, temp, np.ones(4), u+1, np.full(4, 2.), u)

    def test_quadratic_extra_capacity_integral(self):
        # cp=T, rho=2*T: integral((3+2*T)*T, 1, 2)=55/6.
        self.assertAlmostEqual(capacity_integral([1, 2], [1, 2], [2, 4], 3, 1, 1, 2), 55/6)
        self.assertAlmostEqual(capacity_integral([1, 2], [1, 2], [2, 4], 3, 1, 2, 1), -55/6)

    def test_capacity_without_extra_volume(self):
        self.assertAlmostEqual(capacity_integral([1, 2], [1, 2], [2, 4], 3, 0, 1, 2), 4.5)

    def test_invalid_capacity_arrays_rejected(self):
        with self.assertRaises(ValueError):
            capacity_integral([1, 2], [1, 2], [2], 3, 0, 1, 2)
        with self.assertRaises(ValueError):
            capacity_integral([1, 2], [1, 2], [2, -4], 3, 0, 1, 2)


if __name__ == '__main__':
    unittest.main()
