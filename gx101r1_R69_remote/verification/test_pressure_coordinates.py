import unittest
import numpy as np
from Analyze_HeatDriveECC_ChamberPressureCoordinates import inventory_jacobian, pressure_map


class PressureCoordinateTests(unittest.TestCase):
    def test_product_rule_and_inverse(self):
        j = inventory_jacobian(2., 3., 4., 5., 6., 7., .1)
        np.testing.assert_allclose(j, [[.4, .5], [2.4, 2.9]])
        result = pressure_map(j, [2., 3.], [1., 10.])
        np.testing.assert_allclose(np.asarray(result['inverse_Tp_by_MU_SI'])@j, np.eye(2), atol=1e-12)

    def test_singular_map_is_rejected(self):
        with self.assertRaises(ValueError):
            pressure_map([[1., 2.], [2., 4.]], [1., 1.], [1., 1.])

    def test_coordinate_scaling_contract_is_unit_invariant(self):
        j = np.array([[1e-6, 1e-12], [6., -2e-7]])
        a, b = np.array([.0015, 760.]), np.array([1., 1e6])
        baseline = pressure_map(j, a, b)
        output_units = np.array([1e3, 1e-3])
        input_units = np.array([1., 1e-6])
        changed = pressure_map(j*output_units[:, None]/input_units[None, :],
                               a*output_units, b*input_units)
        np.testing.assert_allclose(changed['dimensionless_jacobian'], baseline['dimensionless_jacobian'])
        self.assertLess(changed['dimensionless_inverse_identity_max_abs_error'], 1e-10)

    def test_nonfinite_and_invalid_scales_rejected(self):
        with self.assertRaises(ValueError):
            inventory_jacobian(0., 3., 4., 5., 6., 7., .1)
        with self.assertRaises(ValueError):
            pressure_map(np.eye(2), [0., 1.], [1., 1.])
        with self.assertRaises(ValueError):
            pressure_map(np.eye(2)*np.nan, [1., 1.], [1., 1.])


if __name__ == '__main__':
    unittest.main()
