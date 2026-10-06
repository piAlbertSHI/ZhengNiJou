import unittest

import numpy as np

from Analyze_HeatDriveECC_WarmupOutcome import paired_drift, flow_window


class WarmupOutcomeTests(unittest.TestCase):
    def test_pairing_is_exact_not_nearest_time(self):
        phase = np.sin(np.arange(10000) * 2 * np.pi / 10000)
        values = np.concatenate([phase, phase, phase[:1]])[None, :]
        self.assertEqual(paired_drift(values)["same_phase_max"], 0)

    def test_truncated_pair_is_rejected(self):
        with self.assertRaises(ValueError):
            paired_drift(np.zeros((2, 20000)))

    def test_mean_on_target_does_not_hide_ripple(self):
        time = np.arange(1000) * .001
        flow = .0032 * (1 + .14 * np.where(np.arange(1000) % 2, 1, -1))
        result = flow_window(time, flow, .0032, 0, .999, .15, .05)
        self.assertAlmostEqual(result["mean_signed_kg_s"], .0032)
        self.assertFalse(result["tracking_pass"])

    def test_reverse_flow_cannot_pass_magnitude_only_tracking(self):
        result = flow_window(np.arange(20)*.001, np.full(20, -.0032), .0032,
                             0, .019, .15, .05)
        self.assertFalse(result["tracking_pass"])

    def test_nonfinite_flow_cannot_pass(self):
        with self.assertRaises(ValueError):
            flow_window(np.arange(20)*.001, np.full(20, np.nan), .0032,
                        0, .019, .15, .05)
