import unittest
import numpy as np
from Audit_HeatDriveECC_BoundedPressureCounterexample import pressure_interval, flow_metrics


class BoundedPressureCounterexampleTests(unittest.TestCase):
    def test_reference_port_changes_sign_not_the_domain(self):
        self.assertAlmostEqual(pressure_interval(.85,.45,5,.01,[-.5,.02],'A')[0],-.39)
        self.assertEqual(pressure_interval(.85,.45,5,.01,[-.5,.02],'B'),[-.5,.02])

    def test_invalid_reference_cannot_grant_a_domain(self):
        with self.assertRaises(ValueError):
            pressure_interval(.85,.45,5,.01,[-.5,.02],'guessed')

    def test_saturation_and_rms_are_independent_of_absolute_pressure(self):
        result=flow_metrics(np.array([.0032,.00288]),np.array([-.3,-.39]),
                            np.array([-.3,-.45]),.0032,-.39,.02,.05)
        self.assertFalse(result['rms_pass'])
        self.assertEqual(result['lower_saturation_fraction'],.5)
        self.assertEqual(result['clipped_sum_command_max_error_MPa'],0)


if __name__ == '__main__':
    unittest.main()
