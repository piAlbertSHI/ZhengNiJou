import unittest
import numpy as np
from Analyze_HeatDriveECC_HeldAlgebraicResiduals import residual_stats,reference_domains


class AlgebraicResidualTests(unittest.TestCase):
    def test_constant_offset_does_not_masquerade_as_time_drift(self):
        r=residual_stats([1e-8,1e-8,1e-8])
        self.assertEqual(r['maximum_change_from_initial'],0)
        self.assertEqual(r['maximum_absolute'],1e-8)

    def test_drift_is_not_cancelled_by_initial_offset(self):
        r=residual_stats(np.array([1.,2.,3.]))
        self.assertEqual(r['maximum_change_from_initial'],2)

    def test_nonfinite_or_missing_history_rejected(self):
        for a in ([1],[0,float('nan')],[[0,1]]):
            with self.assertRaises(ValueError):residual_stats(a)

    def test_unregistered_reference_source_is_rejected_without_mutation(self):
        t=dict(blocks=[dict(block_path='model/ColdFluidBuffer',source_file='unknown')])
        with self.assertRaises(ValueError):reference_domains(t)
        self.assertEqual(t['blocks'][0]['source_file'],'unknown')
