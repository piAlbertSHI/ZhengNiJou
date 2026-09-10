import unittest
import numpy as np
from Analyze_HeatDriveECC_ResetStepSignature import signature


class ResetSignatureTests(unittest.TestCase):
    def test_synthetic_reset_rectangle_is_detected_but_not_declared_a_gate(self):
        t=np.arange(5)*.01;f=1+t;increments=.5*np.diff(t)*(f[1:]+f[:-1])
        increments[[0,2]]+=.5*np.diff(t)[[0,2]]*np.diff(f)[[0,2]]
        y=np.r_[0,np.cumsum(increments)];r=signature(t,y,f,[0,.02])
        self.assertAlmostEqual(r['groups']['after_reset']['right_rectangle_signature_coefficient'],1)
        self.assertLess(r['hypothetical_mixed_rectangle_trapezoid_max_residual'],1e-15)
        self.assertTrue(r['hypothetical_mixed_rule_is_not_a_scientific_gate'])
        self.assertFalse(r['actual_solver_first_step_formula_verified'])

    def test_trapezoidal_data_does_not_acquire_a_rectangle_defect(self):
        t=np.arange(5)*.01;f=1+t;y=np.r_[0,np.cumsum(.5*np.diff(t)*(f[1:]+f[:-1]))]
        r=signature(t,y,f,[0,.02])
        self.assertAlmostEqual(r['groups']['after_reset']['right_rectangle_signature_coefficient'],0)
        self.assertLess(r['original_max_abs_cumulative_trapezoid_residual'],1e-15)

    def test_invalid_grid_or_nonfinite_value_rejected(self):
        for t,y,f in [([0,0,.02],[1,2,3],[1,2,3]),([0,.01,.02],[1,2],[1,2,3]),([0,.01,.02],[1,2,3],[1,np.nan,3])]:
            with self.assertRaises(ValueError):signature(t,y,f,[0])
