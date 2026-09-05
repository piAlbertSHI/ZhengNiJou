import copy
import unittest

from Audit_HeatDriveECC_NativeInventoryCatalog import audit_block, convert


def tank():
    data = {"T_I": ("K", [300, 300]), "mass": ("kg", [1, 2]),
            "volume": ("m^3", [.001, .002]), "p_I": ("bar", [10, 10]),
            "u_I": ("kJ/kg", [100, 100]), "h_I": ("kJ/kg", [101, 101]),
            "mdot_A": ("kg/s", [1, 1]), "Phi_A": ("kW", [101, 101]),
            "Q_H": ("W", [0, 0])}
    return {"block_path": "test/Tank", "mask_type": "Tank (TL)",
            "reference_block": "test", "mask_parameters": {},
            "leaf_variables": [{"name": k, "unit": u, "values": v, "time_s": [0, 1]}
                               for k, (u, v) in data.items()]}


class NativeInventoryTests(unittest.TestCase):
    def test_tank_pressure_work_is_not_zero(self):
        row = audit_block(tank())
        self.assertEqual(row["pressure_volume_work_J"], 1000)
        self.assertEqual(row["short_window_U_only_residual_J"], 1000)
        self.assertEqual(row["short_window_U_plus_pdV_residual_J"], 0)
        self.assertEqual(row["short_window_H_residual_J"], 0)
        self.assertEqual(row["short_window_mass_residual_kg"], 0)
        self.assertFalse(row["equation_matched_cycle_closure_verified"])

    def test_units(self):
        self.assertEqual(float(convert(2, "bar", "Pa")), 200000)
        with self.assertRaises(ValueError):
            convert(1, "bar", "K")
        with self.assertRaises(ValueError):
            convert(1, "degC", "K")

    def test_bad_samples(self):
        for name, value in [("values", [1, float("nan")]), ("time_s", [0, .5]),
                            ("values", [1])]:
            block = copy.deepcopy(tank())
            block["leaf_variables"][-1][name] = value
            with self.assertRaises(ValueError):
                audit_block(block)

    def test_unknown_or_duplicate(self):
        block = tank()
        block["mask_type"] = "unknown"
        with self.assertRaises(ValueError):
            audit_block(block)
        block = tank()
        block["leaf_variables"].append(block["leaf_variables"][0])
        with self.assertRaises(ValueError):
            audit_block(block)

    def test_missing_port_energy(self):
        block = tank()
        block["leaf_variables"] = [r for r in block["leaf_variables"] if r["name"] != "Phi_A"]
        with self.assertRaises(ValueError):
            audit_block(block)

    def test_thermal_mass_M_is_a_port_not_mass(self):
        block = {"block_path": "test/Mass", "mask_type": "Thermal Mass",
                 "reference_block": "test", "model_modes": {"mass_type": "1"},
                 "mask_parameters": {"mass": {"value": 2, "unit": "kg"},
                                     "sp_heat": {"value": 500, "unit": "J/(K*kg)"}},
                 "leaf_variables": [{"name": "T", "time_s": [0, 1], "values": [300, 301], "unit": "K"},
                                    {"name": "Q", "time_s": [0, 1], "values": [1000, 1000], "unit": "W"}]}
        self.assertEqual(audit_block(block)["short_window_sensible_residual_J"], 0)
        block["model_modes"]["mass_type"] = "2"
        with self.assertRaises(ValueError):
            audit_block(block)


if __name__ == "__main__":
    unittest.main()
