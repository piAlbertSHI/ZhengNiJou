import unittest
import numpy as np

from Audit_HeatDriveECC_GlobalEnergyObserver import invariant
from Analyze_HeatDriveECC_SinglePipeReference import producer_comparison_allowances


class GlobalEnergyObserverTests(unittest.TestCase):
    def test_invariant_uses_nominal_mass_and_energy_increment(self):
        record = invariant(2., [50., 51., 53.], [0., 2., 6.])
        self.assertTrue(record["numerical_inventory_invariant_pass"])
        self.assertEqual(record["max_abs_storage_minus_integrated_net_J"], 0.)
        self.assertFalse(invariant(3., [50., 51., 53.], [0., 2., 6.])["numerical_inventory_invariant_pass"])

    def test_wrong_sign_or_hidden_initial_offset_rejected(self):
        self.assertFalse(invariant(2., [50., 51.], [0., -2.])["numerical_inventory_invariant_pass"])
        with self.assertRaises(ValueError):
            invariant(2., [50., 51.], [1., 3.])

    def test_nonfinite_or_misaligned_coordinates_rejected(self):
        for mass, u, e in ((0., [1., 2.], [0., 1.]), (1., [1., np.nan], [0., 1.]), (1., [1., 2.], [0.])):
            with self.assertRaises(ValueError):
                invariant(mass, u, e)

    def test_raw_kW_comparison_envelope_is_converted_not_redefined(self):
        case = {"native_probe_comparisons": [{"name": "Q_H", "allowance": 1e-10}]}
        values = {"Q_H": np.array([0., 120.])}
        actual = producer_comparison_allowances(case, {"Q_H": "kW"}, values)
        self.assertAlmostEqual(actual["Q_H"], 1e-7)
        case["native_probe_comparisons"][0]["allowance"] = 1e-7
        with self.assertRaises(ValueError):
            producer_comparison_allowances(case, {"Q_H": "kW"}, values)


if __name__ == "__main__":
    unittest.main()
