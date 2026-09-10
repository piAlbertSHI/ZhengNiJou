import unittest
import numpy as np
from Audit_HeatDriveECC_HeldIntervalBalance import balance


class BalanceIntervalTests(unittest.TestCase):
    def arrays(self):
        t=np.linspace(.1,.12,21)
        return t, np.ones(21), np.ones(21), np.zeros(21), np.zeros(21)

    def test_default_rejects_other_window(self):
        with self.assertRaises(ValueError):balance(*self.arrays())

    def test_explicit_window(self):
        r=balance(*self.arrays(),interval=(.1,.12))
        self.assertTrue(r['mass_closure_pass'] and r['energy_closure_pass'])
        self.assertEqual(r['mass_limit_kg'],1e-15)
        self.assertEqual(r['energy_limit_J'],1e-8)

    def test_wrong_endpoint(self):
        with self.assertRaises(ValueError):balance(*self.arrays(),interval=(.1,.13))

    def test_invalid_interval(self):
        for interval in ((.12,.1),(.1,.1),(.1,np.nan)):
            with self.assertRaises(ValueError):balance(*self.arrays(),interval=interval)
