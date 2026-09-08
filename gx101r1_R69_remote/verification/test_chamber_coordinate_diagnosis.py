"""Exact local table derivatives do not imply discrete endpoint conservation."""
import unittest
import numpy as np
from scipy.interpolate import RegularGridInterpolator
from Audit_HeatDriveECC_ColdChamberStateCoordinates import bilinear_gradient


class ChamberCoordinateTests(unittest.TestCase):
    def table(self):
        x = np.array([270., 290., 330.]); y = np.array([1., 2., 4.])*1e6
        t, p = np.meshgrid(x, y, indexing='ij')
        return RegularGridInterpolator((x, y), 2*t+3e-5*p+1e-7*t*p)

    def test_bilinear_analytic_gradient(self):
        t, p = np.array([275., 315.]), np.array([1.1e6, 3e6])
        dt, dp = bilinear_gradient(self.table(), t, p)
        np.testing.assert_allclose(dt, 2+1e-7*p, atol=1e-12)
        np.testing.assert_allclose(dp, 3e-5+1e-7*t, atol=1e-15)

    def test_derivative_increment_not_endpoint_difference(self):
        table = self.table(); t = np.array([275., 276.]); p = np.array([1.1e6, 1.2e6])
        dt, dp = bilinear_gradient(table, t[1:], p[1:])
        right = dt*np.diff(t)+dp*np.diff(p)
        endpoints = np.diff(table(np.column_stack((t, p))))
        self.assertAlmostEqual(float((right-endpoints)[0]), .01)

    def test_nonuniform_piecewise_gradient(self):
        table = RegularGridInterpolator(([0., 1., 3.], [0., 2.]), np.array([[0., 0.], [1., 1.], [7., 7.]]))
        dt, dp = bilinear_gradient(table, np.array([.5, 1., 2.]), np.ones(3))
        np.testing.assert_allclose(dt, [1, 3, 3]); np.testing.assert_allclose(dp, 0)

    def test_invalid_coordinates_rejected(self):
        for t, p in [([260.], [1e6]), ([300.], [5e6]), ([300., 301.], [1e6]), ([np.nan], [1e6])]:
            with self.assertRaises(ValueError): bilinear_gradient(self.table(), t, p)


if __name__ == '__main__': unittest.main()
