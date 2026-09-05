"""Deterministic state-comparison tests without a MATLAB license."""
import unittest

import numpy as np

from Audit_HeatDriveECC_ObservedStateDrift import comparison_grid, coordinate_metrics


class StateDriftTests(unittest.TestCase):
    def test_periodic_and_linear_coordinates_separately(self):
        time = np.arange(111, dtype=float) / 10
        current, prior = comparison_grid(time, 1)
        values = np.vstack((np.tile(np.arange(10), 12)[:111], 2 * time))
        result = coordinate_metrics(values, current, prior)
        self.assertEqual(result["max_abs"][0], 0)
        self.assertAlmostEqual(result["rms"][1], 2)
        self.assertAlmostEqual(result["last_endpoint_signed"][1], 2)

    def test_insufficient_history(self):
        self.assertIsNone(comparison_grid(np.arange(101) / 10, 1))

    def test_nonuniform_or_repeated_times(self):
        for time in ([0, 1, 3], [0, 0, 1], [0, np.nan, 1], []):
            with self.assertRaises(ValueError):
                comparison_grid(time, 1)

    def test_noninteger_period_grid(self):
        with self.assertRaises(ValueError):
            comparison_grid(np.arange(121) / 10, 1.05)

    def test_nonfinite_state(self):
        with self.assertRaises(ValueError):
            coordinate_metrics([[1, np.nan]], np.array([1]), np.array([0]))

    def test_large_absolute_time(self):
        time = 1890 + np.arange(110001) * .001
        current, prior = comparison_grid(time, 10)
        self.assertEqual(current.size, 100001)
        self.assertTrue(np.allclose(time[current] - time[prior], 10))


if __name__ == "__main__":
    unittest.main()
