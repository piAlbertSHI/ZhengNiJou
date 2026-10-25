import unittest

import numpy as np
from scipy.integrate import solve_ivp

from Analyze_HeatDriveECC_ColdSinkStorage import decompose, exact_window, passive_leak_bound


class ColdSinkStorageTests(unittest.TestCase):
    def test_steady_storage_limit_stream_equals_load(self):
        r = decompose(7., 7., 0., 0., 0., [0., 0.])
        self.assertEqual(r["stream_enthalpy_gain_interval_J"], [7., 7.])

    def test_zero_external_load_can_have_large_transient_stream_gain(self):
        r = decompose(0., 7., -7., -6., -1., [0., 0.])
        self.assertEqual(r["stream_enthalpy_gain_interval_J"], [14., 14.])
        self.assertEqual(r["combined_cold_inventory_change_J"], -14.)
        self.assertEqual(r["imposed_external_load_J"], 0.)

    def test_leak_interval_is_not_silently_dropped(self):
        r = decompose(10., 7., 3., -2., -1., [.1, .2])
        np.testing.assert_allclose(r["stream_enthalpy_gain_interval_J"], [10.1, 10.2])

    def test_sensor_inventory_and_heat_ledger_conflict_rejected(self):
        with self.assertRaises(ValueError):
            decompose(10., 7., 0., 0., 0., [0., 0.])

    def test_exact_window_cannot_interpolate_or_use_incomplete_cycles(self):
        t = np.array([0., 10., 100., 200.])
        self.assertEqual(exact_window(t, 100., 200., 10.), (2, 3))
        for a, b in ((100.+1e-12, 200.), (10., 110.), (0., 99.)):
            with self.assertRaises(ValueError):
                exact_window(t, a, b, 10.)

    def test_duplicate_endpoint_is_not_unique_window(self):
        with self.assertRaises(ValueError):
            exact_window(np.array([0., 100., 100., 200.]), 100., 200., 10.)

    def test_passive_bound_covers_continuous_coupled_ODE_with_both_load_signs(self):
        for load in (-5., 0., 5.):
            box = passive_leak_bound(300., [303., 298.], [280., 340.], 3., load, .2, 10.)
            def rhs(t, y):
                fluid = 310.+30*np.sin(t)
                return [(2*(fluid-y[0])+.4*(y[1]-y[0])+.2*(300-y[0]))/2.,
                        (load-.4*(y[1]-y[0]))/3., .2*(300-y[0])]
            sol = solve_ivp(rhs, (0., 10.), [303., 298., 0.], method="DOP853", rtol=1e-11, atol=1e-12, max_step=.02)
            self.assertTrue(sol.success)
            self.assertGreaterEqual(sol.y[2, -1], box[0])
            self.assertLessEqual(sol.y[2, -1], box[1])

    def test_invalid_passive_contract_and_unordered_leak_are_rejected(self):
        with self.assertRaises(ValueError):
            passive_leak_bound(300., [300., 300.], [280., 340.], 0., 0., .2, 10.)
        with self.assertRaises(ValueError):
            decompose(0., 0., 0., 0., 0., [1., -1.])


if __name__ == "__main__":
    unittest.main()
