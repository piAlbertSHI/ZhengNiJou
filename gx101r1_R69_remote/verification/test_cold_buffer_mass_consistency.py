import unittest

import numpy as np

from Analyze_HeatDriveECC_ColdBufferMassConsistency import _ledger


class ColdBufferMassConsistencyTests(unittest.TestCase):
    def test_exact_right_endpoint_flux_closes_on_declared_grid(self):
        time = np.arange(5, dtype=float) * 0.1
        flux = np.array([0.0, 1.0, 1.0, -2.0, 0.5])
        mass = 2.0 + np.r_[0.0, np.cumsum(np.diff(time) * flux[1:])]
        result = _ledger(time, mass, flux)
        self.assertTrue(result["methods"]["backward_euler_right"]["pass_at_1e-15_kg"])
        self.assertEqual(result["methods"]["measured_state_increment"]["max_abs_residual_kg"], 0.0)

    def test_quadrature_failure_is_not_hidden_by_kahan_sum(self):
        time = np.arange(5, dtype=float) * 0.1
        flux = np.array([0.0, 1.0, 1.0, -2.0, 0.5])
        mass = 2.0 + np.r_[0.0, np.cumsum(np.diff(time) * flux[:-1])]
        result = _ledger(time, mass, flux)
        self.assertFalse(result["methods"]["backward_euler_right"]["pass_at_1e-15_kg"])
        self.assertFalse(result["methods"]["backward_euler_right_kahan"]["pass_at_1e-15_kg"])
        self.assertTrue(result["methods"]["measured_state_increment"]["pass_at_1e-15_kg"])


if __name__ == "__main__":
    unittest.main()
