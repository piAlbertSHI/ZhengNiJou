import unittest
import numpy as np
from Audit_HeatDriveECC_ResetEventSides import reconstruct,audit_case


class ResetEventSidesTests(unittest.TestCase):
    def test_adjacent_sampled_sides_not_snapped(self):
        h=np.arange(41)*.001;t=np.array([0,np.nextafter(.014,0),.014,.04])
        f,y=reconstruct(t,h)
        self.assertEqual(f[1],1+2*t[1]+.013)
        self.assertEqual(f[2],1+2*t[2]+.014)
        self.assertLess(abs(y[2]-y[1]),5e-16)

    def test_early_acquisition_uses_observed_clock(self):
        h=np.arange(41)*.001;h[9]=.00899999999999996
        t=np.array([0,h[9],.009,.04]);f,_=reconstruct(t,h)
        self.assertEqual(f[1],1+3*h[9])

    def test_missing_hits_rejected(self):
        with self.assertRaises(ValueError):reconstruct([0,.04],np.arange(40)*.001)

    def test_forcing_change_rejected(self):
        h=np.arange(41)*.001;f,y=reconstruct(h,h)
        c=dict(time_s=h,held_value=h,held_time_s=h,flux_time_s=h,flux=f,inventory=y,
               solver='ode23t',reset_method='Fast',sample_time='.001',max_step_s=.00002)
        audit_case(c);f[12]+=.001
        with self.assertRaises(ValueError):audit_case(c)


if __name__=='__main__':unittest.main()
