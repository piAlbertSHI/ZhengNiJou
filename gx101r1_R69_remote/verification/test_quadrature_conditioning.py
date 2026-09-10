import unittest
import numpy as np
from Audit_HeatDriveECC_QuadratureConditioning import diagnose


class QuadratureConditioningTests(unittest.TestCase):
    def test_regular_constant(self):
        t=np.linspace(0,.12,101)
        r=diagnose(t,np.ones_like(t)*2)
        self.assertLess(r['constant_simpson_max_error_s'],1e-15)
        self.assertLess(r['simpson_offset_invariance_error'],1e-15)

    def test_bad_grid(self):
        with self.assertRaises(ValueError):diagnose([0,0,1],[1,1,1])

    def test_bad_values(self):
        with self.assertRaises(ValueError):diagnose([0,1,2],[1,np.nan,1])
