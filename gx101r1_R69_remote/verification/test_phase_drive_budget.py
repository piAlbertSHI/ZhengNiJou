import copy
import unittest

import numpy as np

from Analyze_HeatDriveECC_PhaseDriveBudget import normalized_recipe, reverse_coordinate


class PhaseDriveBudgetTests(unittest.TestCase):
    def inputs(self):
        material = dict(T_As_K=268.15, T_Ms_K=258.15, C_A_Pa_per_K=7.6e6)
        kinetics = dict(rate_r_stage3_unload_1_per_s=8., drive_width_r_Pa=5e5, phase_front_smoothing_1_per_s=0.)
        phase = np.full(21, .13)
        drive = np.full(21, .2)
        stress = np.zeros(21)
        rate = -8*(-np.expm1(-drive*1e6/5e5))*phase
        return phase, drive, stress, rate, material, kinetics

    def test_frozen_coordinate_and_inferred_temperature(self):
        x, drive, stress, rate, mat, kin = self.inputs()
        r = reverse_coordinate(x, drive, stress, rate, mat, kin)
        self.assertAlmostEqual(r['nodes'][-1]['frozen_zero_drive_phase_coordinate'], .13-.2/76)
        self.assertAlmostEqual(r['nodes'][-1]['inferred_constitutive_input_temperature_K'], 268.15-1.3+.2/7.6)
        self.assertFalse(r['frozen_coordinate_is_causal_contribution_or_asymptotic_bound'])

    def test_zero_drive_and_saturation(self):
        x, drive, stress, rate, mat, kin = self.inputs()
        drive[:] = 0
        rate[:] = 0
        r = reverse_coordinate(x, drive, stress, rate, mat, kin)
        self.assertAlmostEqual(r['mean_frozen_zero_drive_coordinate'], .13)
        drive[:] = 100
        rate[:] = -8*x
        r = reverse_coordinate(x, drive, stress, rate, mat, kin)
        self.assertEqual(r['mean_frozen_zero_drive_coordinate'], 0)

    def test_rate_mismatch_and_unmodeled_smoothing_are_rejected(self):
        values = list(self.inputs())
        values[3] = values[3]*1.1
        with self.assertRaises(ValueError):
            reverse_coordinate(*values)
        values = list(self.inputs())
        values[-1]['phase_front_smoothing_1_per_s'] = .01
        with self.assertRaises(ValueError):
            reverse_coordinate(*values)

    def test_recipe_exclusions_do_not_hide_physics_change(self):
        a = dict(output_root='a', diagnostic_observation_options=dict(collection_root='c', candidate_Tc_K=272.85), geometry=1)
        b = copy.deepcopy(a)
        b['output_root'] = 'b'
        b['diagnostic_observation_options']['candidate_Tc_K'] = 273.85
        self.assertEqual(normalized_recipe(a), normalized_recipe(b))
        b['geometry'] = 2
        self.assertNotEqual(normalized_recipe(a), normalized_recipe(b))


if __name__ == '__main__':
    unittest.main()
