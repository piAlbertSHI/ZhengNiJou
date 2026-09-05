"""Small deterministic tests for the read-only phase-drift diagnostic."""
import unittest

import numpy as np

from Audit_HeatDriveECC_InternalStateCoverage import drift_metrics


class DriftTests(unittest.TestCase):
    def test_periodic(self):
        result = drift_metrics(np.tile([1, 2, 3], 4), 3)
        self.assertTrue(result["complete_comparison_coverage"])
        self.assertEqual(result["max_K"], 0)

    def test_constant_cycle_drift(self):
        result = drift_metrics(np.arange(12) / 3, 3)
        self.assertAlmostEqual(result["p99_K"], 1)
        self.assertAlmostEqual(result["rms_K"], 1)

    def test_missing_coverage(self):
        result = drift_metrics([np.nan, 1, 2, 3], 2)
        self.assertFalse(result["complete_comparison_coverage"])
        self.assertNotIn("rms_K", result)

    def test_bad_shape_or_stride(self):
        for values, stride in [([[1, 2]], 1), ([1, 2], 2), ([1, 2], 0)]:
            with self.assertRaises(ValueError):
                drift_metrics(values, stride)


if __name__ == "__main__":
    unittest.main()
