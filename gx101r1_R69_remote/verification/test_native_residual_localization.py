import unittest

import numpy as np

from Audit_HeatDriveECC_NativeResidualLocalization import backward_euler_integrals, component_terms, event_mask, interval_integrals, summarize
from test_native_inventory_catalog import tank
from test_native_window_ledger import TABLE, pipe


class ResidualLocalizationTests(unittest.TestCase):
    def test_BE_uses_right_endpoint_without_discarding_intervals(self):
        np.testing.assert_array_equal(backward_euler_integrals([2, 4, 8], [0, 1, 3]), [4, 16])
        self.assertNotEqual(sum(backward_euler_integrals([2, 4, 8], [0, 1, 3])),
                            sum(interval_integrals([2, 4, 8], [0, 1, 3])))

    def test_partition_keeps_event_and_terminal_intervals(self):
        time = np.linspace(0, .04, 41)
        terms = {"energy_residual_J": np.arange(40.), "mass_residual_kg": np.arange(40.) * 1e-6}
        result = summarize(time, terms, np.array([0, 10, 20, 30, 40]))
        self.assertTrue(result["interval_partition_pass"])
        self.assertEqual(sum(r["energy_residual_J"] for r in result["stages"]), sum(range(40)))
        self.assertAlmostEqual(result["largest_energy_residual_intervals"][0]["stop_s"], .04)
        mask = event_mask(time, np.array([0, 40]), .005)
        self.assertEqual(mask.sum(), 10)
        self.assertTrue(mask[0] and mask[-1])

    def test_constant_coefficient_interval_integral(self):
        np.testing.assert_array_equal(interval_integrals([2, 2, 2], [0, 1, -1]), [2, -4])
        for a, b in (([1], [1]), ([1, 2], [1]), ([1, float("nan")], [1, 2])):
            with self.assertRaises(ValueError):
                interval_integrals(a, b)

    def test_tank_terms_match_existing_ledger(self):
        block = tank()
        block["leaf_variables"].append(dict(name="rho_I", time_s=[0, 1], values=[1000, 1000], unit="kg/m^3"))
        _, terms, reference = component_terms(block, TABLE)
        self.assertEqual(terms["energy_mass_transport_J"].sum(), 101000)
        self.assertEqual(terms["energy_temperature_J"].sum(), 0)
        self.assertEqual(terms["energy_residual_J"].sum(), reference["energy_residual_J"])

    def test_chamber_terms_match_existing_ledger(self):
        block = pipe()
        block.update(mask_type="Constant Volume Chamber (TL)", mask_parameters={"volume": {"value": 1e-6, "unit": "m^3"}})
        _, terms, reference = component_terms(block, TABLE)
        self.assertEqual(terms["energy_pressure_J"].sum(), 0)
        self.assertAlmostEqual(terms["energy_accumulation_J"].sum(), reference["energy_equation_accumulation_J"])
        self.assertAlmostEqual(terms["mass_temperature_kg"].sum(), reference["mass_equation_accumulation_kg"])


if __name__ == "__main__":
    unittest.main()
