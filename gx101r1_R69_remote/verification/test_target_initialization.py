import unittest
import numpy as np
from Audit_HeatDriveECC_TargetInitialization import compare_rows


class JointInitializationTests(unittest.TestCase):
    def reference(self):
        return {'state/model/PI/DSTATE':('',np.array([2000,2000.001]),np.array([[.02,.021]]))}

    def test_exact_reference(self):
        ref=self.reference()
        row=compare_rows(ref,ref)[0]
        self.assertTrue(row['exact_initial'] and row['exact_one_step'])

    def test_reset_cannot_pass(self):
        ref=self.reference();other=self.reference()
        other['state/model/PI/DSTATE'][2][0,0]=0
        row=compare_rows(ref,other)[0]
        self.assertFalse(row['initial']['pass_endpoint_match'])
        self.assertTrue(row['one_step']['pass_endpoint_match'])

    def test_step_change_cannot_hide_behind_initial_match(self):
        ref=self.reference();other=self.reference()
        other['state/model/PI/DSTATE'][2][0,1]=.03
        row=compare_rows(ref,other)[0]
        self.assertTrue(row['initial']['pass_endpoint_match'])
        self.assertFalse(row['one_step']['pass_endpoint_match'])

    def test_missing_group_rejected(self):
        with self.assertRaisesRegex(ValueError,'coverage'):
            compare_rows(self.reference(),{})

    def test_time_unit_shape_rejected(self):
        for value in [('Pa',np.array([2000,2000.001]),np.array([[.02,.021]])),
                      ('',np.array([0,.001]),np.array([[.02,.021]])),
                      ('',np.array([2000,2000.001]),np.array([[.02],[.021]]))]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                compare_rows(self.reference(),{'state/model/PI/DSTATE':value})


if __name__=='__main__':
    unittest.main()
