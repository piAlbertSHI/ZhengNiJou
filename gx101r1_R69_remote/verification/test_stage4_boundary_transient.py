import unittest

import numpy as np

from Audit_HeatDriveECC_Stage4BoundaryTransient import (
    first_continuous_band,
    interval,
)


class Stage4BoundaryTransientTest(unittest.TestCase):
    def setUp(self):
        self.time = np.arange(0.0, 10.001, 0.001)

    def test_interval_preserves_boundary_mass_window(self):
        flow = np.full(self.time.size, 0.0032)
        result = interval(self.time, flow, 8.801, 9.85)
        self.assertEqual(result["samples"], 1050)
        self.assertAlmostEqual(result["signed_mass_g"], 3.3568, places=5)

    def test_first_continuous_band_reports_boundary_delay(self):
        flow = np.zeros(self.time.size)
        flow[self.time >= 8.5] = 0.0032
        self.assertAlmostEqual(
            first_continuous_band(self.time, flow, 8.5, 10.0, 0.05), 0.0)


if __name__ == "__main__":
    unittest.main()
