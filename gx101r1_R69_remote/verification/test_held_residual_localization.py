import unittest
import numpy as np
from Analyze_HeatDriveECC_HeldResidualLocalization import localization


class ResidualLocalizationTests(unittest.TestCase):
    def test_early_jump_is_distinct_from_cumulative_drift(self):
        t=np.linspace(0,.04,41);f=np.zeros_like(t)
        early=np.zeros_like(t);early[1:]=1e-6
        drift=t*1e-6
        a=localization(t,early,f,1e-10);b=localization(t,drift,f,1e-10)
        self.assertEqual(a['largest_increment_interval_s'],[0,.001])
        self.assertEqual(a['maximum_residual_first_ms'],a['maximum_absolute_residual'])
        self.assertLess(b['maximum_residual_first_ms'],b['maximum_absolute_residual'])
        self.assertFalse(a['solver_error_source_identified'])
        self.assertFalse(b['scientific_gate_pass'])

    def test_conservation_is_not_changed_by_localization(self):
        t=np.array([0,.001,.005,.02,.04])
        r=localization(t,1+t*t,2*t,1e-15)
        self.assertTrue(r['scientific_gate_pass'])

    def test_partial_or_duplicate_history_is_rejected(self):
        for t in (np.array([0,.02]),np.array([0,.02,.02,.04])):
            with self.assertRaises(ValueError):localization(t,t,t,1e-15)
