import unittest

import numpy as np

from Audit_HeatDriveECC_TankEnergyBasis import extra_thermal_accumulation, hydrostatic_transport


class TankEnergyBasisTests(unittest.TestCase):
    def test_constant_coefficients_and_geometry_scaling(self):
        t, temp = [0, .001, .002], [300, 301, 303]
        be, tr = extra_thermal_accumulation(t, temp, [1000]*3, [4000]*3, .001)
        np.testing.assert_allclose(be, [4, 8])
        np.testing.assert_array_equal(be, tr)
        twice, _ = extra_thermal_accumulation(t, temp, [1000]*3, [4000]*3, .002)
        np.testing.assert_array_equal(twice, 2*be)

    def test_endpoint_rule_is_explicit(self):
        be, tr = extra_thermal_accumulation([0, 1], [301, 300], [1000, 900], [4000, 4000], .001)
        np.testing.assert_allclose(be, [-3.6])
        np.testing.assert_allclose(tr, [-3.8])

    def test_constant_temperature_has_no_extra_transport(self):
        be, tr = extra_thermal_accumulation([0, 1], [300, 300], [1000, 900], [4000, 4000], .001)
        np.testing.assert_array_equal(be, [0])
        np.testing.assert_array_equal(tr, [0])

    def test_reject_invalid_inputs(self):
        for args in (([0, 0], [300, 301], [1000]*2, [4000]*2, .001),
                     ([0, 1], [300, 301], [1000]*2, [4000]*2, 0),
                     ([0, 1], [300, np.nan], [1000]*2, [4000]*2, .001),
                     ([0, 1], [300, 301], [-1]*2, [4000]*2, .001),
                     ([0, 1], [300, 301], [1000]*2, [-1]*2, .001),
                     ([0, 1], [300], [1000]*2, [4000]*2, .001)):
            with self.subTest(args=args), self.assertRaises(ValueError):
                extra_thermal_accumulation(*args)

    def test_head_transport_sign_and_height(self):
        be, tr = hydrostatic_transport([0, 1, 2], [2, 2, -2], [1, 1, 1], 10, .2)
        np.testing.assert_array_equal(be, [-16, 16])
        np.testing.assert_array_equal(tr, [-16, 0])

    def test_zero_gravity_or_zero_head(self):
        for g, h in ((0, 0), (10, 1)):
            be, tr = hydrostatic_transport([0, 1], [2, 3], [1, 1], g, h)
            np.testing.assert_array_equal(be, [0])
            np.testing.assert_array_equal(tr, [0])

    def test_reject_unsubmerged_port_and_bad_grid(self):
        for t, y, g in (([0, 1], [.1, .2], 10), ([1, 1], [1, 1], 10), ([0, 1], [1, 1], -10)):
            with self.subTest(t=t, y=y, g=g), self.assertRaises(ValueError):
                hydrostatic_transport(t, [2, 3], y, g, .3)


if __name__ == '__main__':
    unittest.main()
