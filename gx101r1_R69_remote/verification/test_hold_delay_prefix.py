import unittest

import numpy as np

from Audit_HeatDriveECC_HoldDelayPrefix import compare


class PrefixComparisonTests(unittest.TestCase):
    def test_exact(self):
        self.assertTrue(compare(np.array([1., 2.]), np.array([1., 2.]))['exactly_equal'])

    def test_no_broadcast(self):
        r = compare(np.array([1., 2.]), np.array([[1., 2.]]))
        self.assertFalse(r['exactly_equal'])
        self.assertIsNone(r['max_abs_difference'])

    def test_no_tolerance(self):
        r = compare(np.array([1.]), np.array([np.nextafter(1., 2.)]))
        self.assertFalse(r['exactly_equal'])
        self.assertGreater(r['max_abs_difference'], 0)

    def test_nonfinite(self):
        r = compare(np.array([np.nan]), np.array([np.nan]))
        self.assertFalse(r['finite'])
        self.assertFalse(r['exactly_equal'])
        self.assertIsNone(r['max_abs_difference'])
