import unittest
import numpy as np

from Audit_HeatDriveECC_NativeLagTransfer import identical_traces


class TestNativeLagTransfer(unittest.TestCase):
    def fixture(self):
        return {'state':('K',np.array([1.,2.]),np.array([[300.,301.]]))}

    def test_equal(self):self.assertTrue(identical_traces(self.fixture(),self.fixture()))

    def test_missing_group(self):
        with self.assertRaises(ValueError):identical_traces(self.fixture(),{})

    def test_ulp_value_not_equal(self):
        other=self.fixture();other['state'][2][0,0]=np.nextafter(300.,301.)
        self.assertFalse(identical_traces(self.fixture(),other))

    def test_ulp_time_not_equal(self):
        other=self.fixture();other['state'][1][0]=np.nextafter(1.,2.)
        self.assertFalse(identical_traces(self.fixture(),other))

    def test_units_not_equal(self):
        other=self.fixture();_,t,y=other['state'];other['state']=('C',t,y)
        self.assertFalse(identical_traces(self.fixture(),other))


if __name__=='__main__':unittest.main()
