"""Native storage and exact sampled clocks, not new production tolerances."""
import copy
import json
from pathlib import Path
import unittest

import numpy as np
from scipy.io import loadmat

from Analyze_HeatDriveECC_SharedSMAColdInitial import gate_on_clock, native_mass, pipe_ledger, series_index
from Compare_HeatDriveECC_ColdPrefixCoverage import equal_prefix


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

    def test_ZOH_event_uses_last_value_at_duplicate_time(self):
        trace={"time":[0,.001,.001,.002],"signals":{"values":[0,0,1,1]}}
        np.testing.assert_array_equal(gate_on_clock(trace,np.array([0,.001,.002])),[0,1,1])

    def test_half_step_event_is_not_shifted_onto_previous_native_sample(self):
        trace={"time":[0,.0015,.002],"signals":{"values":[0,1,1]}}
        np.testing.assert_array_equal(gate_on_clock(trace,np.array([0,.001,.002])),[0,0,1])

    def test_numeric_prefix_requires_exact_values_not_a_tolerance(self):
        self.assertTrue(equal_prefix([1.,2.],[1.,2.,3.]))
        self.assertFalse(equal_prefix([1.,2.],[1.,2.+1e-12,3.]))


class ActualColdCycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root=Path("C:/tmp/se21_shared_SMA_cold_cycle_r1_20261026")
        cls.raw={arm:loadmat(root/arm/"selected_observations.mat",simplify_cells=True)["traces"] for arm in ("dual","shared")}

    def test_variable_step_gate_logs_agree_at_actual_native_clock(self):
        clock=np.arange(10001)*.001
        gates={a:{k:gate_on_clock(v,clock) for k,v in r["gate_commands"].items()} for a,r in self.raw.items()}
        for name in ("original_hold","original_cooldown"):
            np.testing.assert_array_equal(gates["dual"][name],gates["shared"][name])
        np.testing.assert_array_equal(gates["shared"]["shared_max"],np.maximum(gates["shared"]["original_hold"],gates["shared"]["original_cooldown"]))

    def test_measured_persistent_hot_inventory_is_not_a_switched_temperature_label(self):
        def hold_ends(arm):
            return [r["values"][-1] for r in self.raw[arm]["series"] if "/SMA/HoldPipe_" in r["block_path"] and r["state_name"]=="T_I"]
        self.assertGreater(min(hold_ends("dual")),390.)
        self.assertLess(max(hold_ends("shared")),310.)

    def test_complete_raw_is_selected_observation_not_restart_state(self):
        for r in self.raw.values():
            self.assertTrue(r["not_an_OP_or_restart_state"])
            self.assertFalse(r["partial_diagnostic_only"])
            self.assertEqual(np.asarray(r["constitutive_output"]["signals"]["values"]).shape,(10001,252))


if __name__ == "__main__":
    unittest.main()
