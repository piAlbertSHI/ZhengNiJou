import unittest
import numpy as np

from Audit_HeatDriveECC_MappedDiagnosticState import FIELDS, compare, exact_indices


class MappedStateTests(unittest.TestCase):
    def test_exact_delayed_millisecond_clock(self):
        t=1200+np.arange(100)*.001
        self.assertTrue(np.array_equal(exact_indices(t[1:],t,.001), np.arange(99)))

    def test_missing_previous_sample_rejected(self):
        t=np.arange(100)*.001
        with self.assertRaises(ValueError):
            exact_indices(t,t,.001)

    def test_half_step_and_nonuniform_clocks_rejected(self):
        t=np.arange(100)*.001
        with self.assertRaises(ValueError):
            exact_indices(t[1:]+.0005,t,.001)
        changed=t.copy();changed[30]+=.00001
        with self.assertRaises(ValueError):
            exact_indices(t[1:],changed,.001)

    def test_distinct_units_not_joint_norm(self):
        self.assertEqual(len(FIELDS),10)
        self.assertEqual(dict(FIELDS)['sigma_a_21'],'Pa')
        self.assertEqual(dict(FIELDS)['r_xi_r_21'],'1/s')
        self.assertEqual(dict(FIELDS)['xM_r_21'],'1')

    def test_exact_identity_not_tolerance_based(self):
        a=np.ones((21,100));compare(a,a.copy())
        b=a.copy();b[0,0]+=1e-15
        with self.assertRaises(ValueError):
            compare(a,b)

    def test_nonfinite_and_dimensions_rejected(self):
        with self.assertRaises(ValueError):
            compare([[float('nan')]],[[float('nan')]])
        with self.assertRaises(ValueError):
            compare(np.zeros((1,10)),np.zeros((10,1)))


if __name__=='__main__':
    unittest.main()
