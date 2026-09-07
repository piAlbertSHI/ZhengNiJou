import unittest

from Audit_HeatDriveECC_BoundaryProbe import compare_power


class BoundaryPowerTests(unittest.TestCase):
    def test_exact_and_roundoff(self):
        residual,passed,limit=compare_power([1,2],[1,2+1e-11])
        self.assertTrue(passed)
        self.assertLess(abs(residual[1]),limit)

    def test_missing_flow_not_hidden(self):
        _,passed,_=compare_power([1,2],[1,2.001])
        self.assertFalse(passed)

    def test_nonfinite_or_wrong_window_rejected(self):
        for a,b in (([1],[1]),([1,float('nan')],[1,2]),([1,2],[1,2,3])):
            with self.assertRaises(ValueError):
                compare_power(a,b)


if __name__=='__main__':
    unittest.main()
