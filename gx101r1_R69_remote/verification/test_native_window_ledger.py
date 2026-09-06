import copy
import unittest

import numpy as np

from Audit_HeatDriveECC_NativeWindowLedger import SCHEMA, compare_partition, evaluate_component, validate_grid
from test_native_inventory_catalog import tank


def lookup(name):
    def evaluate(coords):
        t = np.asarray(coords)[:, 0]
        return {"rho": 1000 - (t - 300), "u": 100000 + 4000 * (t - 300),
                "cp": np.full_like(t, 4000), "alpha": np.full_like(t, .001),
                "beta": np.full_like(t, 1e9)}[name]
    return evaluate


TABLE = {key: lookup(key) for key in ("rho", "u", "cp", "alpha", "beta")}


def pipe():
    block = tank()
    block.update(mask_type="Pipe (TL)", block_path="test/Pipe",
                 model_modes={"dynamic_compressibility": "false"})
    data = {"T_I": ("K", [300, 301]), "p_I": ("Pa", [1e6, 1e6]),
            "rho_I": ("kg/m^3", [1000, 999]), "u_I": ("J/kg", [100000, 104000]),
            "h_I": ("J/kg", [101000, 105001]), "Q_H": ("W", [4, 4]),
            "mdot_A": ("kg/s", [0, 0]), "mdot_B": ("kg/s", [0, 0]),
            "Phi_A": ("W", [0, 0]), "Phi_B": ("W", [0, 0])}
    block["leaf_variables"] = [dict(name=k, unit=u, values=v, time_s=[0, 1]) for k, (u, v) in data.items()]
    return block


class WindowLedgerTests(unittest.TestCase):
    def test_pipe_uses_fixed_mass_not_native_density(self):
        row = evaluate_component(pipe(), TABLE, .001)
        self.assertEqual(row["mass_endpoint_change_kg"], 0)
        self.assertEqual(row["energy_equation_accumulation_J"], 4)
        self.assertEqual(row["energy_residual_J"], 0)
        self.assertFalse(row["energy_closure_verified"])
        self.assertNotEqual(row["energy_equation_accumulation_J"], 1e-6 * (999 * 104000 - 1000 * 100000))

    def test_missing_or_nonpositive_nominal_mass_rejected(self):
        for mass in (None, -1, float("nan")):
            with self.assertRaises(ValueError):
                evaluate_component(pipe(), TABLE, mass)

    def test_tank_internal_mass_and_pressure_work_separate(self):
        block = tank()
        block["leaf_variables"].append(dict(name="rho_I", time_s=[0, 1], values=[1000, 1000], unit="kg/m^3"))
        row = evaluate_component(block, TABLE)
        self.assertEqual(row["energy_equation_accumulation_J"], 101000)
        self.assertEqual(row["energy_endpoint_change_J"], 100000)
        self.assertEqual(row["pressure_volume_work_J"], 1000)
        self.assertEqual(row["energy_residual_J"], 0)
        self.assertEqual(row["mass_residual_kg"], 0)

    def test_chamber_coefficient_accumulation_not_endpoint_substitution(self):
        block = pipe()
        block.update(mask_type="Constant Volume Chamber (TL)", mask_parameters={"volume": {"value": 1e-6, "unit": "m^3"}})
        row = evaluate_component(block, TABLE)
        expected = .5 * ((4000 - 101000 * .001) * 1000 + (4000 - 105001 * .001) * 999) * 1e-6
        self.assertAlmostEqual(row["energy_equation_accumulation_J"], expected)
        self.assertNotEqual(row["energy_endpoint_change_J"], row["energy_equation_accumulation_J"])
        self.assertAlmostEqual(row["mass_equation_accumulation_kg"], -.001 * .5 * (1000 + 999) * 1e-6)

    def test_property_mismatch_and_missing_flow_rejected(self):
        block = pipe()
        block["leaf_variables"][2]["values"][1] = 990
        with self.assertRaises(ValueError):
            evaluate_component(block, TABLE, .001)
        block = pipe()
        block["leaf_variables"] = [r for r in block["leaf_variables"] if r["name"] != "Phi_B"]
        with self.assertRaises(ValueError):
            evaluate_component(block, TABLE, .001)

    def test_thermal_mass_latent_heat_not_duplicated(self):
        block = dict(block_path="test/Mass", mask_type="Thermal Mass", reference_block="test",
                     model_modes={"mass_type": "1"}, mask_parameters={"mass": {"value": 2, "unit": "kg"},
                     "sp_heat": {"value": 500, "unit": "J/(K*kg)"}},
                     leaf_variables=[dict(name="T", time_s=[0, 1], values=[300, 301], unit="K"),
                                     dict(name="Q", time_s=[0, 1], values=[1000, 1000], unit="W")])
        row = evaluate_component(block)
        self.assertEqual(row["energy_equation_accumulation_J"], 1000)
        self.assertNotIn("mass_flow_integral_kg", row)

    def test_grid_rejects_missing_terminal_gap_and_fractional_step(self):
        validate_grid([1800, 1800.001, 1800.002], 1800, 1800.002, .001)
        for time, start, stop, dt in [([0, 1], 0, 2, 1), ([0, .9, 2], 0, 2, 1),
                                      ([0, 1, 2.1], 0, 2.1, 1), ([0, 1], 0, 1, 0),
                                      ([0, float("nan"), 2], 0, 2, 1)]:
            with self.assertRaises(ValueError):
                validate_grid(time, start, stop, dt)

    def partition(self):
        windows = []
        for start, stop, energy in ((0, 2, 3), (0, 1, 1), (1, 2, 2)):
            windows.append(dict(schema=SCHEMA, ledger_computation_pass=True, production_recovery_allowed=False,
                                start_s=start, stop_s=stop, source={"source": "same"},
                                components=[dict(block_path="test", energy_flow_integral_J=energy)]))
        return windows

    def test_partition_additivity_and_nonfinite(self):
        windows = self.partition()
        self.assertTrue(compare_partition(*windows)["partition_integrals_match"])
        windows[2]["components"][0]["energy_flow_integral_J"] = 3
        self.assertFalse(compare_partition(*windows)["partition_integrals_match"])
        windows[2]["components"][0]["energy_flow_integral_J"] = float("nan")
        with self.assertRaises(ValueError):
            compare_partition(*windows)

    def test_partition_rejects_mixed_versions_sources_and_gap(self):
        for field, value in (("schema", "legacy"), ("start_s", 1.1), ("source", {"source": "other"}),
                             ("production_recovery_allowed", True)):
            windows = copy.deepcopy(self.partition())
            windows[2][field] = value
            with self.assertRaises(ValueError):
                compare_partition(*windows)


if __name__ == "__main__":
    unittest.main()
