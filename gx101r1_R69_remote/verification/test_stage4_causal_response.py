import unittest

import numpy as np

from Analyze_HeatDriveECC_Stage4CausalResponse import transport_time_scale, window_slice


class Stage4CausalResponseTest(unittest.TestCase):
    def test_multicycle_window_uses_requested_cycle(self):
        time = np.arange(0.0, 20.001, 0.001)
        first = window_slice(time)
        second = window_slice(time, offset_s=10.0)
        self.assertEqual(int(first.sum()), 1050)
        self.assertEqual(int(second.sum()), 1050)
        self.assertAlmostEqual(float(time[second][0]), 18.801)

    def test_solid_mass_cannot_establish_fluid_residence(self):
        result = transport_time_scale(np.full(1050, 0.0032))
        self.assertIsNone(result["estimated_residence_s"])
        self.assertIsNone(result["window_shorter_than_residence"])
        self.assertFalse(result["solid_mass_substitution_allowed"])


if __name__ == "__main__":
    unittest.main()
