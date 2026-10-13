import unittest
import numpy as np
from Analyze_HeatDriveECC_SECommutationInventory import partition,reference_comparison


class CommutationTests(unittest.TestCase):
    def test_every_BE_interval_once(self):
        time=np.arange(20001)*.001;flow=np.ones_like(time)*1e-6;mass=.1+time*1e-6
        rows=partition(time,mass,flow,.15)
        self.assertEqual(len(rows),8)
        self.assertAlmostEqual(sum(row['endpoint_mass_change_kg'] for row in rows),20e-6)
        self.assertTrue(all(p['local_mass_pass'] for row in rows for p in row['parts']))

    def test_transition_is_not_inactive_leakage(self):
        time=np.arange(10001)*.001;flow=np.zeros_like(time);flow[1:151]=.001
        mass=.1+np.r_[0,np.cumsum(flow[1:]*.001)]
        row=partition(time,mass,flow,.15)[0]
        self.assertAlmostEqual(row['parts'][0]['endpoint_mass_change_kg'],.00015)
        self.assertEqual(row['parts'][1]['endpoint_mass_change_kg'],0)

    def test_missing_interval_rejected(self):
        time=np.arange(10000)*.001
        with self.assertRaises(ValueError):partition(time,np.ones_like(time),np.zeros_like(time),.15)

    def test_bad_mass_equation_reported(self):
        time=np.arange(10001)*.001
        rows=partition(time,np.ones_like(time),np.ones_like(time)*1e-5,.15)
        self.assertFalse(rows[0]['parts'][0]['local_mass_pass'])

    def test_unaligned_ramp_rejected(self):
        time=np.arange(10001)*.001
        with self.assertRaises(ValueError):partition(time,np.ones_like(time),np.zeros_like(time),.1505)

    def test_reference_conflict_detected(self):
        time=np.arange(101)*.001;alpha=np.linspace(1,0,101);nominal=.003
        result=reference_comparison(time,alpha,alpha*nominal,np.ones_like(time)*nominal,np.ones_like(time),nominal)
        self.assertFalse(result['pressure_envelope_and_PI_reference_identical'])
        self.assertEqual(result['PI_full_while_FF_ramped_samples'],99)

    def test_common_reference_pass(self):
        time=np.arange(101)*.001;alpha=np.linspace(1,0,101);nominal=.003
        result=reference_comparison(time,alpha,alpha*nominal,alpha*nominal,alpha,nominal)
        self.assertTrue(result['pressure_envelope_and_PI_reference_identical'])

    def test_wrong_ff_authority_rejected(self):
        time=np.arange(101)*.001;alpha=np.ones_like(time)
        with self.assertRaises(ValueError):reference_comparison(time,alpha,alpha*.002,alpha*.003,alpha,.003)


if __name__=='__main__':unittest.main()
