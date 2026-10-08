import unittest
import numpy as np

from Audit_HeatDriveECC_DistributedPressureRuntime import window_coordinates, native_window_values
from Analyze_HeatDriveECC_WarmupOutcome import paired_drift


class CompletedWarmupWindowTests(unittest.TestCase):
    def test_original_ten_second_clock_unchanged(self):
        time = np.arange(10001)*.001
        np.testing.assert_array_equal(window_coordinates(time, 0, 10), time)

    def test_long_clock_native_last_two_cycles(self):
        time = np.arange(200001)*.001
        expected = window_coordinates(time, 180, 200)
        self.assertEqual(expected.size, 20001)
        native = np.r_[179.999, expected]
        values = native+300
        actual = native_window_values(native, values, 180, expected)
        np.testing.assert_array_equal(actual, values[1:])

    def test_wrong_leading_sample_rejected(self):
        expected = 180+np.arange(20001)*.001
        with self.assertRaises(ValueError):
            native_window_values(np.r_[179.998, expected], np.ones(20002), 180, expected)

    def test_missing_public_sample_rejected(self):
        with self.assertRaises(ValueError):
            window_coordinates(np.arange(200000)*.001, 180, 200)

    def test_noninteger_window_rejected(self):
        with self.assertRaises(ValueError):
            window_coordinates(np.arange(200001)*.001, 180.0001, 200)

    def test_reordered_native_clock_rejected(self):
        expected = 180+np.arange(20001)*.001
        wrong = expected.copy()
        wrong[[20, 21]] = wrong[[21, 20]]
        with self.assertRaises(ValueError):
            native_window_values(wrong, np.ones(20001), 180, expected)

    def test_small_endpoint_does_not_hide_transition_drift(self):
        values = np.zeros((1, 20001))
        values[0, 11000] = .3
        drift = paired_drift(values)
        self.assertEqual(drift['endpoint_max'], 0)
        self.assertEqual(drift['same_phase_max'], .3)
