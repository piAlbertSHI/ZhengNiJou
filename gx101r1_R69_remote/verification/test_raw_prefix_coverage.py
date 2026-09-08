import unittest
import numpy as np
from Audit_HeatDriveECC_RawPrefixCoverage import dataset_prefix


class PrefixCoverageTests(unittest.TestCase):
    def test_exact_prefix_not_later_tail(self):
        source=np.array([[1.,2.,3.],[4.,5.,6.]])
        target=np.column_stack((source,[99.,99.]))
        self.assertTrue(dataset_prefix(source,target,3,2)['bitwise_exact'])

    def test_boundary_difference_retained(self):
        source=np.array([[1.,2.,3.]])
        target=np.array([[1.,2.,4.,5.]])
        result=dataset_prefix(source,target,3,2)
        self.assertEqual(result['different_scalar_values'],1)
        self.assertEqual(result['first_different_sample_index'],2)
        self.assertEqual(result['last_different_sample_index'],2)

    def test_signed_zero_is_not_bitwise_equal(self):
        self.assertFalse(dataset_prefix(np.array([[0.]]),np.array([[-0.]]),1)['bitwise_exact'])

    def test_shape_mismatch_rejected(self):
        with self.assertRaises(ValueError):dataset_prefix(np.ones((2,3)),np.ones((1,4)),3)

    def test_dtype_mismatch_rejected(self):
        with self.assertRaises(ValueError):dataset_prefix(np.ones((1,3)),np.ones((1,4),dtype=np.float32),3)

    def test_nonfinite_identical_is_not_finite(self):
        a=np.array([[np.nan]])
        result=dataset_prefix(a,a,1)
        self.assertTrue(result['bitwise_exact'])
        self.assertFalse(result['finite'])


if __name__=='__main__':unittest.main()
