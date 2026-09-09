import unittest
from Audit_HeatDriveECC_SMADerivativeContract import schedule


class ScheduleTests(unittest.TestCase):
    def test_piecewise_linear_slope_not_sample_delta(self):
        rows,events=schedule(dict(time_s=[0,2,10],values=[0,1,1],interpolate='on'))
        self.assertEqual([r['slope'] for r in rows],[.5,0]);self.assertEqual(events,[])
        self.assertEqual(sum((r['end_s']-r['start_s'])*r['slope'] for r in rows),1)

    def test_held_command_jump_is_not_classical_derivative(self):
        rows,events=schedule(dict(time_s=[0,2,10],values=[0,1,1],interpolate='off'))
        self.assertTrue(all(r['slope']==0 for r in rows));self.assertEqual(events[0]['jump'],1)
        self.assertFalse(events[0]['classical_derivative_at_jump_defined'])
        self.assertEqual(rows[0]['right_limit'],0)

    def test_bad_time_domain_or_nan_rejected(self):
        for times,values in [([0,0,10],[0,1,1]),([0,1,9],[0,1,1]),([0,1,10],[0,float('nan'),1]),([0,10],[1])]:
            with self.assertRaises(ValueError):schedule(dict(time_s=times,values=values,interpolate='on'))

    def test_unknown_interpolation_rejected(self):
        with self.assertRaises(ValueError):schedule(dict(time_s=[0,10],values=[0,1],interpolate='cubic'))


if __name__=='__main__':unittest.main()
