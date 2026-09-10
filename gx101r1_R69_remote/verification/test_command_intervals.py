import unittest
from Audit_HeatDriveECC_CommandIntervals import command_intervals


class CommandIntervalTests(unittest.TestCase):
    def fixture(self,mode):
        return dict(block='bias',time_s=[0,.05,.075,.1,.15,.2],values=[0,0,0,0,1,1],interpolate=mode)

    def test_linear_departure_starts_before_changed_value_knot(self):
        r=command_intervals(self.fixture('on'))
        self.assertEqual(r['constant_prefix_end_exclusive_s'],.1)
        self.assertAlmostEqual(r['transitions'][0]['slope'],20)
        self.assertEqual(r['transition_count'],1)

    def test_hold_departure_at_changed_value_knot(self):
        r=command_intervals(self.fixture('off'))
        self.assertEqual(r['constant_prefix_end_exclusive_s'],.15)

    def test_redundant_knots_are_not_events(self):
        c=self.fixture('on');c['values']=[0]*6
        self.assertIsNone(command_intervals(c)['constant_prefix_end_exclusive_s'])

    def test_nonfinite_and_duplicate_times_rejected(self):
        c=self.fixture('on');c['time_s'][2]=.05
        with self.assertRaises(ValueError):command_intervals(c)
        c=self.fixture('on');c['values'][2]=float('nan')
        with self.assertRaises(ValueError):command_intervals(c)


if __name__=='__main__':unittest.main()
