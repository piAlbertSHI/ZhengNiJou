import unittest
import numpy as np

from Audit_HeatDriveECC_C201Horizon import check_period


class C201HorizonTests(unittest.TestCase):
    def setUp(self):
        self.t = np.arange(1990,2011,dtype=float)
        self.y = np.sin(2*np.pi*(self.t-1990)/10).reshape(1,-1)

    def test_repeated_cycle(self):
        self.assertEqual(check_period(self.t,self.y)['knot_count'],11)

    def test_held_endpoint_rejected(self):
        self.y[:,11:] = 0
        with self.assertRaises(ValueError):
            check_period(self.t,self.y)

    def test_missing_knot_rejected(self):
        with self.assertRaises(ValueError):
            check_period(np.delete(self.t,12),np.delete(self.y,12,axis=1))

    def test_nonfinite_and_duplicate_rejected(self):
        for t,y in [(self.t,np.full_like(self.y,np.nan)),(np.sort(np.append(self.t,2005)),np.append(self.y,[[0]],axis=1))]:
            with self.assertRaises(ValueError):
                check_period(t,y)


if __name__ == '__main__':
    unittest.main()
