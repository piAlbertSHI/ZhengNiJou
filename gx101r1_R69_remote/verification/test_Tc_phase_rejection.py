import unittest

import numpy as np

from Analyze_HeatDriveECC_TcPhaseRejection import phase_cycles


class TcPhaseRejectionTests(unittest.TestCase):
    def test_cycle_minimum_does_not_substitute_for_cold_half_completion(self):
        time = 1160+np.arange(20001)*.001
        value = np.full((21, 20001), .5)
        value[:, 0] = .001
        rows = phase_cycles(time, value)
        self.assertAlmostEqual(rows[0]['mean_phase_min'], .001)
        self.assertIsNone(rows[0]['cold_half_completion_s'])
        self.assertFalse(rows[0]['original_cold_half_1_percent_completion_pass'])

    def test_original_thresholds_and_event_timing(self):
        time = 1160+np.arange(20001)*.001
        value = np.ones((21, 20001))
        value[:, 7500] = .009
        value[:, 17500] = .0101
        rows = phase_cycles(time, value)
        self.assertAlmostEqual(rows[0]['cold_half_completion_s'], 2.5)
        self.assertTrue(rows[0]['original_99_percent_swing_pass'])
        self.assertIsNone(rows[1]['cold_half_completion_s'])
        self.assertFalse(rows[1]['original_99_percent_swing_pass'])

    def test_missing_node_or_incomplete_trace_rejected(self):
        time = 1160+np.arange(20001)*.001
        with self.assertRaises(ValueError):
            phase_cycles(time, np.zeros((20, 20001)))


if __name__ == '__main__':
    unittest.main()
