import unittest
import numpy as np

from Audit_HeatDriveECC_PhaseBeforeBlow import before_flow


class BeforeBlowTests(unittest.TestCase):
    def test_half_cycle_end_does_not_replace_before_blow_state(self):
        time = np.array([0., 1., 2., 3.])
        phase = np.array([[.5, .8, .9, 1.], [.9, 1., 1., 1.]])
        row = before_flow(time, phase, [0., 0., 1., 1.], 0, 4, 1, .1)
        self.assertEqual(row["onset_time_s"], 2.)
        self.assertEqual(row["prior_measured_phase"]["minimum_xM"], .8)
        self.assertEqual(phase[:, -1].min(), 1.)

    def test_unloading_and_negative_flow(self):
        phase = np.array([[1., .1, 0., 0.], [1., .35, .1, 0.]])
        row = before_flow([0., 1., 2., 3.], phase, [0., 0., -1., -1.], 0, 4, 1, .1)
        self.assertEqual(row["prior_measured_phase"]["maximum_xM"], .35)

    def test_missing_onset_and_bad_phase_rejected(self):
        with self.assertRaises(ValueError):
            before_flow([0., 1.], np.zeros((2, 2)), [0., 0.], 0, 2, 1, .1)
        with self.assertRaises(ValueError):
            before_flow([0., 1.], np.full((2, 2), np.nan), [0., 1.], 0, 2, 1, .1)


if __name__ == "__main__":
    unittest.main()
