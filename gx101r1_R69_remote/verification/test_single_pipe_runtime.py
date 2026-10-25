import unittest
import numpy as np

from Analyze_HeatDriveECC_SinglePipeHeatStep import pipe_balance, reference_flux


class SinglePipeRuntimeTests(unittest.TestCase):
    def test_backwards_euler_ledger_matches_right_endpoint_heat(self):
        time = np.array([0., .1, .2])
        rows = {name: np.zeros(3) for name in ("Phi_A", "Phi_B", "mdot_A", "mdot_B")}
        rows.update(Q_H=np.array([0., 10., 20.]), u_I=np.array([0., .5, 1.5]))
        row = pipe_balance(time, rows, 2.)
        self.assertEqual(row["max_abs_step_residual_J"], 0.)
        rows["Q_H"][1] = 9.
        self.assertAlmostEqual(pipe_balance(time, rows, 2.)["endpoint_residual_J"], -.1)

    def test_nominal_mass_not_instantaneous_density_volume(self):
        time = np.array([0., 1.])
        rows = {name: np.zeros(2) for name in ("Phi_A", "Phi_B", "mdot_A", "mdot_B")}
        rows.update(Q_H=np.array([0., 2.]), u_I=np.array([0., 1.]))
        self.assertEqual(pipe_balance(time, rows, 2.)["endpoint_residual_J"], 0.)
        self.assertNotEqual(pipe_balance(time, rows, 3.)["endpoint_residual_J"], 0.)

    def test_same_trajectory_reference_retains_heat_sign_and_nu(self):
        geometry = {"surface_area_m2": 2., "Dh_m": .5}
        values = {"k_I": np.array([.5, .5, .5]), "probe_wall_T": np.array([301., 300., 299.]),
                  "T_I": np.array([300., 300., 300.])}
        np.testing.assert_equal(reference_flux(geometry, values, 3.), [6., 0., -6.])
        np.testing.assert_equal(reference_flux(geometry, values, 6.), [12., 0., -12.])

    def test_missing_nonfinite_and_invalid_inventory_rejected(self):
        rows = {name: np.zeros(2) for name in ("Phi_A", "Phi_B", "Q_H", "u_I", "mdot_A", "mdot_B")}
        for mass in (0., -1., np.nan):
            with self.assertRaises(ValueError):
                pipe_balance([0., 1.], rows, mass)
        rows["Q_H"][1] = np.nan
        with self.assertRaises(ValueError):
            pipe_balance([0., 1.], rows, 1.)


if __name__ == "__main__":
    unittest.main()
