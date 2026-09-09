import unittest
import numpy as np
from scipy.interpolate import RegularGridInterpolator
from Analyze_HeatDriveECC_PumpLocalInitialization import port_flux, central_jacobian


class PumpLocalTests(unittest.TestCase):
    def table(self):
        t, p = np.array([280., 300., 320.]), np.array([.5e6, 2e6])
        return {'u': RegularGridInterpolator((t, p), (1000*(t-273))[:, None]*np.ones((1, 2))),
                'rho': RegularGridInterpolator((t, p), np.full((3, 2), 1000.))}

    def test_zero_flow_retains_conduction(self):
        self.assertAlmostEqual(port_flux(self.table(), 0., 310., 1e6, 27000., 1e-4), 1.)

    def test_both_flow_signs_match_independent_algebra(self):
        for q in (-.02, -1e-8, 0., 1e-8, .02):
            s = np.sqrt(q*q+4e-8)
            expected = .5*((q+s)*37000.+(q-s)*27000.)+q*1e6/1000.
            self.assertAlmostEqual(port_flux(self.table(), q, 310., 1e6, 27000., 1e-4), expected, places=10)

    def test_invalid_domain_and_zero_conductance_rejected(self):
        for t, u, g in ((400., 27000., 1e-4), (310., 1e9, 1e-4), (310., 27000., 0.)):
            with self.assertRaises(ValueError):
                port_flux(self.table(), 0., t, 1e6, u, g)

    def test_jacobian_cross_terms(self):
        def f(x):
            return np.array([x[0]*x[1], x[0]**2+3*x[1]])
        np.testing.assert_allclose(central_jacobian(f, [2., 4.], 1e-5), [[4., 2.], [4., 3.]], atol=1e-9)


if __name__ == '__main__':
    unittest.main()
