import json
import unittest
import numpy as np
from Audit_HeatDriveECC_DigitalConverterHistory import check_channel


class DigitalHistoryTests(unittest.TestCase):
    def setUp(self):
        self.q=np.array([.12,.11,.10,0.])
        self.observed=np.array([[1.,1.,1.,1.],self.q])
        self.snapshot=np.array([1.,.10])

    def test_matching_channel(self):
        r=check_channel(self.q,self.observed,self.snapshot,self.q)
        self.assertTrue(r['digital_observation_exact'])
        self.assertTrue(r['snapshot_previous_input_exact'])
        json.dumps(r,allow_nan=False)

    def test_wrong_sample_rejected(self):
        r=check_channel(self.q,self.observed,np.array([1.,0.]),self.q)
        self.assertFalse(r['snapshot_previous_input_exact'])

    def test_one_ulp_digital_change_rejected(self):
        self.observed[1,0]=np.nextafter(self.q[0],np.inf)
        self.assertFalse(check_channel(self.q,self.observed,self.snapshot,self.q)['digital_observation_exact'])

    def test_native_bitwise_failure_is_not_hidden(self):
        heat=self.q.copy();heat[0]=np.nextafter(heat[0],np.inf)
        r=check_channel(self.q,self.observed,self.snapshot,heat)
        self.assertFalse(r['native_heat_bitwise_exact'])
        self.assertTrue(r['native_heat_existing_tolerance_pass'])

    def test_wrong_heat_fails_existing_tolerance(self):
        self.assertFalse(check_channel(self.q,self.observed,self.snapshot,self.q+.001)['native_heat_existing_tolerance_pass'])

    def test_missing_sample_rejected(self):
        with self.assertRaises(ValueError):check_channel(self.q[:-1],self.observed,self.snapshot,self.q)

    def test_nonfinite_rejected(self):
        self.snapshot[0]=np.nan
        with self.assertRaises(ValueError):check_channel(self.q,self.observed,self.snapshot,self.q)


if __name__=='__main__':unittest.main()
