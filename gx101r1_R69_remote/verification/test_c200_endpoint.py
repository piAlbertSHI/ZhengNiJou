import unittest
import numpy as np

from Audit_HeatDriveECC_C200RestoredSignals import compare


class C200EndpointTests(unittest.TestCase):
    def test_exact_endpoint_match(self):
        self.assertTrue(compare([300,.1],[300,.1])['pass_endpoint_match'])

    def test_state_reset_rejected(self):
        self.assertFalse(compare([300,.1],[303.15,0])['pass_endpoint_match'])

    def test_invalid_channels_rejected(self):
        for a,b in [([],[]),([1],[1,2]),([np.nan],[np.nan]),([np.inf],[np.inf])]:
            with self.assertRaises(ValueError):
                compare(a,b)


if __name__=='__main__':
    unittest.main()
