import unittest
import numpy as np

from Audit_HeatDriveECC_C201Horizon import check_period, check_ablation


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

    def test_boundary_ablation_exact_scope(self):
        t,y = np.array([1999.,2000.,2000.002,2010.]), np.array([[1.,0.,0.,1.]])
        changed_t,changed_y = np.insert(t,2,2000.001),np.insert(y,1,y[:,0],axis=1)
        self.assertEqual(check_ablation(t,y,changed_t,changed_y)['held_at_boundary'],1)
        changed_y[0,-1] = 0
        with self.assertRaises(ValueError):
            check_ablation(t,y,changed_t,changed_y)

    def test_altered_release_time_rejected(self):
        with self.assertRaises(ValueError):
            check_ablation([1999,2000,2000.002],np.array([[1,0,0]]),
                           [1999,2000,2000.0005,2000.002],np.array([[1,1,0,0]]))


if __name__ == '__main__':
    unittest.main()
