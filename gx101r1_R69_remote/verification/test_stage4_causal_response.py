import unittest

import numpy as np

from Analyze_HeatDriveECC_Stage4CausalResponse import window_slice


class Stage4CausalResponseTest(unittest.TestCase):
    def test_multicycle_window_uses_requested_cycle(self):
        time = np.arange(0.0, 20.001, 0.001)
        first = window_slice(time)
        second = window_slice(time, offset_s=10.0)
        self.assertEqual(int(first.sum()), 1050)
        self.assertEqual(int(second.sum()), 1050)
        self.assertAlmostEqual(float(time[second][0]), 18.801)


if __name__ == "__main__":
    unittest.main()
