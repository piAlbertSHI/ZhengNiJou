"""Native storage and exact sampled clocks, not new production tolerances."""
import copy
import json
from pathlib import Path
import unittest

import numpy as np

from Analyze_HeatDriveECC_SharedSMAColdInitial import native_mass, pipe_ledger, series_index


class NativeLedgerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path("C:/tmp/se21_shared_SMA_cold_initial_r2_20261026/shared")
        cls.p = json.loads((root/"cold_preflight.json").read_text(encoding="utf-8"))
        cls.raw = json.loads((root/"selected_observations.json").read_text(encoding="utf-8"))

    def test_actual_shared_pipe_BE_ledger_readback(self):
        rows = series_index(self.raw)
        ledgers = [pipe_ledger(rows, g, self.p["fluid_tables"], .01) for g in self.p["pipe_geometry"]]
        self.assertEqual(len(ledgers), 21)
        self.assertLess(max(r["BE_energy_residual_max_J"] for r in ledgers), 1e-10)
        self.assertEqual(max(r["mass_port_sum_max_kg_s"] for r in ledgers), 0.)
        self.assertTrue(all(r["initial_temperature_K"] == 303.15 for r in ledgers))

    def test_instantaneous_density_does_not_change_native_storage_definition(self):
        rows = series_index(self.raw)
        g = self.p["pipe_geometry"][0]
        a = pipe_ledger(rows, g, self.p["fluid_tables"], .01)
        key = (g["block_path"], "rho_I")
        clock, values = rows[key]
        rows[key] = clock, values*np.linspace(1., 2., len(values))
        self.assertEqual(a, pipe_ledger(rows, g, self.p["fluid_tables"], .01))

    def test_missing_BE_sample_cannot_be_interpolated_into_a_pass(self):
        rows = series_index(self.raw)
        g = self.p["pipe_geometry"][0]
        key = (g["block_path"], "u_I")
        t, v = rows[key]
        rows[key] = np.delete(t, 5), np.delete(v, 5)
        with self.assertRaisesRegex(ValueError, "actual complete"):
            pipe_ledger(rows, g, self.p["fluid_tables"], .01)

    def test_wrong_SI_unit_rejected(self):
        raw = copy.deepcopy(self.raw)
        raw["series"][0]["unit"] = "degC"
        with self.assertRaisesRegex(ValueError, "unit"):
            series_index(raw)

    def test_nominal_density_contract_tamper_rejected(self):
        g = copy.deepcopy(self.p["pipe_geometry"][0])
        g["native_nominal_density_kg_m3"] *= 1.001
        with self.assertRaisesRegex(ValueError, "Nominal density"):
            native_mass(g, self.p["fluid_tables"])


if __name__ == "__main__":
    unittest.main()
