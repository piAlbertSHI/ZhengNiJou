import unittest
import numpy as np

from Audit_HeatDriveECC_OneSecondTransfer import compare_trace


class TestOneSecondTransfer(unittest.TestCase):
    def test_matching_trace(self):
        row = ('K', np.array([0., 1., 2.]), np.array([[300., 301., 302.]]))
        self.assertTrue(compare_trace(row, row)['full_transfer_pass'])

    def test_ulp_grid_is_not_silently_accepted(self):
        time = np.array([0., 1., 2.]); other = time.copy(); other[1] = np.nextafter(1., 2.)
        value = np.ones((1, 3))
        result = compare_trace(('K', time, value), ('K', other, value))
        self.assertFalse(result['full_transfer_pass'])
        self.assertTrue(result['common_timestamp_values_pass'])
        self.assertTrue(result['index_only_diagnostic_values_pass'])
        self.assertEqual(result['common_timestamp_count'], 2)

    def test_common_grid_can_prove_real_value_failure(self):
        time = np.array([0., 1., 2.]); other = time.copy(); other[1] = np.nextafter(1., 2.)
        result = compare_trace(('K', time, np.ones((1, 3))), ('K', other, np.array([[1., 1., 2.]])))
        self.assertFalse(result['common_timestamp_values_pass'])
        self.assertEqual(result['first_common_value_failure_s'], 2.)

    def test_bad_units_and_nonfinite(self):
        time = np.array([0., 1.]); value = np.ones((1, 2))
        with self.assertRaises(ValueError): compare_trace(('K', time, value), ('C', time, value))
        with self.assertRaises(ValueError): compare_trace(('K', time, value), ('K', time, value * np.nan))

    def test_duplicate_grid_rejected(self):
        row = ('K', np.array([0., 0.]), np.ones((1, 2)))
        with self.assertRaises(ValueError): compare_trace(row, row)


if __name__ == '__main__': unittest.main()
