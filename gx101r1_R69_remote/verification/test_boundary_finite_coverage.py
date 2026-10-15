import unittest
import numpy as np

from Audit_HeatDriveECC_BoundaryCoverage import coverage


class BoundaryFiniteCoverageTests(unittest.TestCase):
    def test_long_clock_does_not_imply_measured_history(self):
        values=np.array([[np.nan,np.nan,1.,2.,3.]])
        result=coverage(np.arange(5),values,1,4)
        self.assertFalse(result['requested_window_all_finite'])
        self.assertEqual(result['finite_support_endpoints_s'],[2.,4.])

    def test_valid_subwindow_remains_valid(self):
        result=coverage(np.arange(5),np.array([[np.nan,np.nan,1.,2.,3.]]),2,4)
        self.assertTrue(result['requested_window_all_finite'])

    def test_every_channel_required(self):
        values=np.ones((2,5));values[1,2]=np.nan
        self.assertFalse(coverage(np.arange(5),values,1,4)['requested_window_all_finite'])

    def test_requested_window_extends_before_clock(self):
        self.assertFalse(coverage(np.arange(5),np.ones((1,5)),-1,4)['requested_window_all_finite'])

    def test_holes_are_not_contiguous_support(self):
        values=np.array([[1.,2.,np.nan,3.,4.]])
        self.assertFalse(coverage(np.arange(5),values,1,4)['finite_support_contiguous'])


if __name__=='__main__':unittest.main()
