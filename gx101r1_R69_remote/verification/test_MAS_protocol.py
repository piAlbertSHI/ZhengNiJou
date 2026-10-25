import unittest

import numpy as np

from Run_HeatDriveECC_MASSignedCriticalProtocol import forcing, run_case


class MaterialProtocolTests(unittest.TestCase):
    def test_forcing_crosses_only_M_critical_boundary(self):
        crossing = 4/np.pi*np.arccos((256.-262.25)/7.75)
        t, a, m = forcing(np.array([0., crossing, 4., 8-crossing, 8.]))
        np.testing.assert_allclose(t, [270., 256., 254.5, 256., 270.], atol=1e-12)
        self.assertTrue((a > 0).all())
        np.testing.assert_allclose(m[[1, 3]], 0., atol=1e-6)
        self.assertLess(m[2], 0.)

    def test_time_varying_signed_M_protocol_has_independent_solution(self):
        clocks = np.linspace(0., 8., 17)
        phase, plus, minus, _ = run_case(3e-26, .1, "Radau", clocks)
        reference, _, _, _ = run_case(3e-26, .1, "DOP853", clocks)
        np.testing.assert_allclose(phase, reference, rtol=0., atol=1e-6)
        self.assertTrue((plus >= 0).all() and (minus >= 0).all())


if __name__ == "__main__":
    unittest.main()
