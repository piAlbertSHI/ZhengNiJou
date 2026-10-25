import unittest

import numpy as np

from Analyze_HeatDriveECC_ObservedPhaseDrive import common_stress, frozen_endpoint, numerical_match, phase_rate


class ObservedPhaseDriveTests(unittest.TestCase):
    def setUp(self):
        self.a = {"T_As_K": 323.15, "T_Ms_K": 313.15, "C_A_Pa_per_K": 7.6e6,
                  "C_M_Pa_per_K": 7.3e6, "epsilon_T": .03, "E_m_Pa": 30e9}
        self.r = dict(self.a, T_As_K=268.15, T_Ms_K=258.15)
        self.g = {"L_a_m": .8191207665316702, "L_r_m": .37843290919687267,
                  "S_a_m2": 2.5132741228718343e-5, "S_r_m2": 1.7e-5}

    def test_loading_and_unloading_signs_and_saturation(self):
        x = np.array([0., .4, 1.])
        p, gate, v = phase_rate(np.full(3, 300.), x, 1e9, self.r, 5e5, 8., True, 2.)
        np.testing.assert_equal(v, [2., 2., 0.])
        self.assertTrue(np.all(p > 0))
        np.testing.assert_equal(gate, np.ones(3))
        _, _, v = phase_rate(np.full(3, 300.), x, -1e9, self.r, 5e5, 8., False, 2.)
        np.testing.assert_equal(v, [0., -2., -2.])

    def test_subcritical_drive_is_not_rescued_by_rate_multiplier(self):
        for rate in (1., 1e6):
            p, gate, v = phase_rate(np.array([320.]), np.array([.8]), 400e6,
                                    self.r, 5e5, rate, True, 1e8)
            self.assertLess(p[0], 0)
            self.assertEqual(gate[0], 0)
            self.assertEqual(v[0], 0)

    def test_force_displacement_compatibility_with_signed_force(self):
        xa = np.array([1., 1.]); xr = np.array([.5, .2])
        sa, sr = common_stress(xa, xr, self.a, self.r, self.g)
        self.assertLess(sr, 0)
        self.assertAlmostEqual(sa * self.g["S_a_m2"], sr * self.g["S_r_m2"])
        displacement_a = self.g["L_a_m"] * np.mean(.03 * (1 - xa) - sa / 30e9)
        displacement_r = self.g["L_r_m"] * np.mean(.03 * xr + sr / 30e9)
        self.assertAlmostEqual(displacement_a, displacement_r)

    def test_frozen_loading_bound_uses_hottest_node_and_preserves_inputs(self):
        xa = np.array([.15, .2]); tr = np.array([310., 322.])
        before = xa.copy(), tr.copy()
        row = frozen_endpoint(xa, tr, self.a, self.r, self.g, True)
        self.assertEqual(row["limiting_node_1based"], 2)
        self.assertFalse(row["necessary_drive_nonnegative"])
        self.assertFalse(row["predicts_modified_coupled_trajectory"])
        np.testing.assert_equal(xa, before[0]); np.testing.assert_equal(tr, before[1])

    def test_frozen_unloading_bound_uses_coldest_node(self):
        row = frozen_endpoint(np.ones(2), np.array([263., 280.]), self.a, self.r, self.g, False)
        self.assertEqual(row["limiting_node_1based"], 1)
        self.assertEqual(row["target_common_SE_stress_Pa"], 0)
        self.assertLess(row["necessary_drive_margin_Pa"], 0)

    def test_changed_temperature_can_change_frozen_feasibility(self):
        cold = frozen_endpoint(np.ones(2), np.array([263., 280.]), self.a, self.r, self.g, False)
        warm = frozen_endpoint(np.ones(2), np.array([280., 290.]), self.a, self.r, self.g, False)
        self.assertFalse(cold["necessary_drive_nonnegative"])
        self.assertTrue(warm["necessary_drive_nonnegative"])

    def test_reconstruction_rejects_real_change_nonfinite_and_bad_shape(self):
        x = np.array([4e8, 1e6])
        self.assertEqual(numerical_match(x, x.copy(), "identity")["max_abs_difference"], 0)
        for changed in (x + .1, np.array([np.nan, 1e6]), np.array([[4e8, 1e6]])):
            with self.assertRaises(ValueError):
                numerical_match(x, changed, "corruption")


if __name__ == "__main__":
    unittest.main()
