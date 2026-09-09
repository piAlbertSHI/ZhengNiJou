import unittest
import numpy as np
from Audit_HeatDriveECC_PSControllerEquivalence import metrics


class ControllerPairTests(unittest.TestCase):
    def fixture(self):
        return np.linspace(0,10,10001),np.zeros((10001,6))

    def test_zero_error_is_not_limit_coverage(self):
        t,v=self.fixture();r=metrics(t,v)
        self.assertTrue(r['equivalence_pass']);self.assertFalse(r['all_limits_exercised'])

    def test_mismatch_and_failed_hold_detected(self):
        t,v=self.fixture();v[:,5]=.001;r=metrics(t,v)
        self.assertFalse(r['equivalence_pass']);self.assertFalse(r['reset_hold_pass'])

    def test_nonfinite_duplicate_or_truncated_time_rejected(self):
        for mode in ('nan','duplicate','truncated'):
            t,v=self.fixture()
            if mode=='nan':v[1,0]=np.nan
            elif mode=='duplicate':t[1]=t[0]
            else:t[-1]=9.9995
            with self.assertRaises(ValueError):metrics(t,v)


if __name__=='__main__':unittest.main()
