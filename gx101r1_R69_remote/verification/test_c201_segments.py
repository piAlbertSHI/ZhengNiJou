import unittest
import numpy as np

from Audit_HeatDriveECC_C201Segments import grid,boundary


class C201SegmentTests(unittest.TestCase):
    def test_full_grid(self):
        t=2000+np.arange(4001)*.001
        grid(t,np.ones((2,4001)),2000,2004)

    def test_truncated_log_rejected(self):
        with self.assertRaises(ValueError):
            grid(2000+np.arange(4000)*.001,np.ones((1,4000)),2000,2004)

    def test_boundary_state_change_rejected(self):
        a=dict(stop_s=2004,last={'PI':np.array([.1])},units={'PI':'MPa'})
        b=dict(start_s=2004,first={'PI':np.array([0.])},units={'PI':'MPa'})
        self.assertFalse(boundary(a,b)['pass_boundary'])

    def test_changed_units_rejected(self):
        a=dict(stop_s=2004,last={'PI':np.array([.1])},units={'PI':'MPa'})
        b=dict(start_s=2004,first={'PI':np.array([.1])},units={'PI':'Pa'})
        with self.assertRaises(ValueError):
            boundary(a,b)

    def test_source_trace_is_included_in_boundary_gate(self):
        a=dict(stop_s=2004,last={'state/PI':np.array([.1]),'source/SHEX/Q':np.array([80.])},
               units={'state/PI':'MPa','source/SHEX/Q':'W'})
        b=dict(start_s=2004,first={'state/PI':np.array([.1]),'source/SHEX/Q':np.array([81.])},units=a['units'])
        result=boundary(a,b)
        self.assertEqual(result['compared_groups'],2)
        self.assertFalse(result['pass_boundary'])
        self.assertEqual(result['failed_groups'][0]['identity'],'source/SHEX/Q')

    def test_source_cannot_disappear_between_segments(self):
        a=dict(stop_s=2004,last={'source/SHEX/Q':np.array([80.])},units={'source/SHEX/Q':'W'})
        b=dict(start_s=2004,first={},units={})
        with self.assertRaises(ValueError):
            boundary(a,b)


if __name__=='__main__':
    unittest.main()
