"""Retained samples stay on their original absolute clock; no held endpoints."""
from pathlib import Path
import unittest

import numpy as np

from Analyze_HeatDriveECC_CoupledCVBalance import window_indices,balance_window
from Review_HeatDriveECC_CoupledCVPacket import on_grid


class TailTests(unittest.TestCase):
    def test_absolute_clock_is_not_used_as_an_array_index(self):
        t=np.arange(180000,200001)*.001
        self.assertEqual(window_indices(t,190.,200.),(10000,20000))
        for a,b in ((0.,20.),(179.,180.),(190.,201.)):
            with self.assertRaises(ValueError):window_indices(t,a,b)

    def test_one_floating_point_ulp_is_not_a_missing_physical_sample(self):
        clock=np.arange(180000,180003)*.001
        row={'time_s':np.nextafter(clock,np.inf),'values':np.arange(3)[:,None]}
        np.testing.assert_array_equal(on_grid(row,clock).ravel(),np.arange(3))
        with self.assertRaises(ValueError):on_grid(row,clock+.0001)

    def test_native_BE_ledger_works_on_nonzero_time_origin_without_energy_shift(self):
        t=np.arange(180000,180003)*.001;dt=np.diff(t);p=np.array([999.,2.,3.])
        E=np.r_[100.,100.+np.cumsum(dt*p[1:])]
        c=dict(path='fixture',kind='Endpoint Buffer',basis='fixture',power=p,mdot=np.zeros(3),
               M=np.ones(3),U=E,dM=np.zeros(2),dE=np.diff(E))
        b=dict(path='source',kind='fixture',role='fixture',sign=1,rule='fixture',power=p)
        r=balance_window({'time':t},[c],[b],180.,180.002)
        self.assertAlmostEqual(r['BE_identified_native_equation_residual_J'],0.,places=12)
        self.assertAlmostEqual(r['endpoint_energy_change_J'],.005,places=10)

    def test_configuration_does_not_change_sample_time_or_controller(self):
        root=Path(__file__).resolve().parent
        source=(root/'Configure_HeatDriveECC_CVTailObservation.m').read_text(encoding='utf-8')
        self.assertIn("set_param(p,'MaxDataPoints'",source)
        self.assertNotIn("set_param(p,'SampleTime'",source)
        self.assertNotIn('setInitialState(',source)
        self.assertNotIn("'InitialCondition'",source)
        select=(root/'Select_HeatDriveECC_TraceWindow.m').read_text(encoding='utf-8')
        self.assertNotIn('interp1(',select)
        self.assertNotIn('resample(',select)


if __name__=='__main__':unittest.main()
