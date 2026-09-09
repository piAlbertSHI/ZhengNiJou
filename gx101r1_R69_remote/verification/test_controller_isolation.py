import unittest
import numpy as np
from Audit_HeatDriveECC_ControllerIsolation import step_metrics


class IsolationTests(unittest.TestCase):
    def test_counts_are_recomputed(self):
        t = np.array([0., 1e-7, 1., 2., 10.])
        r = step_metrics(t, np.zeros((5, 3)))
        self.assertEqual(r['steps_below_1e_6_s'], 1)
        self.assertEqual(sum(r['sample_counts_by_second']), 5)

    def test_partial_duplicate_nonfinite_and_wrong_columns_rejected(self):
        for t, v in [(np.array([0., 9.]), np.zeros((2, 3))),
                     (np.array([0., 0., 10.]), np.zeros((3, 3))),
                     (np.array([0., 10.]), np.full((2, 3), np.nan)),
                     (np.array([0., 10.]), np.zeros((2, 6)))]:
            with self.assertRaises(ValueError):
                step_metrics(t, v)


if __name__ == '__main__':
    unittest.main()
