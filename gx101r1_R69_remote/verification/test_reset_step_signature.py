import unittest
from pathlib import Path
import numpy as np
from Analyze_HeatDriveECC_ResetStepSignature import signature
from Audit_HeatDriveECC_AnalyticResetProbe import exact_solution,audit_case


class ResetSignatureTests(unittest.TestCase):
    def test_trbdf2_requires_analytic_evidence_and_isolated_settings(self):
        source=(Path(__file__).parent/'Inspect_HeatDriveECC_ColdCompiledStates.m').read_text(encoding='utf-8')
        self.assertIn('848959AE2B7CE4D7D906949D7B12E63172FACA93B9B2EB6F51AADB6B2035E6B4',source)
        self.assertIn('~held_profiler && ~held_split_tolerances && ~held_robust_reset',source)
        self.assertIn('~probe.coupled_conservation_pass && ~probe.production_recovery_allowed',source)

    def test_analytic_integral_at_sampled_boundaries(self):
        t=np.array([0,.001,.0015,.002])
        np.testing.assert_allclose(exact_solution(t,True)-(1+t+t*t),[0,0,5e-7,1e-6],rtol=0,atol=3e-16)
        c=dict(time_s=t.tolist(),inventory=exact_solution(t,True).tolist(),logged_flux=[1,1,1,1],
               forcing='sampled',reset_method='Fast',initial_step_setting='auto')
        with self.assertRaises(ValueError):audit_case(c)

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
