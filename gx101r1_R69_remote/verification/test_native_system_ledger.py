import unittest

import numpy as np

from Audit_HeatDriveECC_NativeSystemLedger import align_steps, assemble, stage_endpoints


class NativeSystemLedgerTests(unittest.TestCase):
    def test_actual_stage_schedule(self):
        np.testing.assert_array_equal(stage_endpoints([3.5, 1.5, 3.5, 1.5], .001, 10001),
                                      [0, 3500, 5000, 8500, 10000])

    def test_invalid_stage_schedules_rejected(self):
        for durations, dt, count in (([3.5, 1.5, 3.5, 1.5], 0, 10001),
                ([3.5, 1.5, 3.5, 1.5], .001, 10000), ([3.5, 1.5, 5], .001, 10001),
                ([3.5, -1.5, 3.5, 4.5], .001, 10001), ([3.5, np.nan, 3.5, 1.5], .001, 10001),
                ([3.5001, 1.4999, 3.5, 1.5], .001, 10001)):
            with self.subTest(durations=durations, dt=dt, count=count), self.assertRaises(ValueError):
                stage_endpoints(durations, dt, count)

    def test_one_ulp_clock_difference_preserved(self):
        a = np.array([1800., 1800.001, 1800.002])
        b = a.copy(); b[1] = np.nextafter(b[1], np.inf)
        result = align_steps(a, b, 1800., 1800.002, .001)
        self.assertFalse(result["bitwise_time_equal"])
        self.assertEqual(result["differing_time_samples"], 1)
        self.assertTrue(result["original_time_axes_retained"])
        self.assertFalse(result["samples_interpolated"])

    def test_wrong_step_or_missing_endpoint_rejected(self):
        a = np.array([1800., 1800.001, 1800.002])
        for b in (a[:-1], a + .0001):
            with self.assertRaises(ValueError):
                align_steps(a, b, 1800., 1800.002, .001)

    def fixture(self):
        p = {name: np.zeros(2) for name in ("Q_SHEX_source_to_sink_W", "Q_HHEX_sink_to_ambient_W",
              "Q_CHEX_fixed_source_W", "Q_CHEX_load_to_sink_W", "P_pressure_source_native_W",
              "pump_power_SMA_W", "pump_power_SE_W")}
        p["Q_SHEX_source_to_sink_W"][:] = 10
        p["Q_HHEX_sink_to_ambient_W"][:] = 7
        p["Q_CHEX_fixed_source_W"][:] = -2
        p["Q_SMA_constitutive_21_W"] = np.full((2, 21), 1 / 21)
        p["Q_SE_constitutive_21_W"] = np.zeros((2, 21))
        ledger = dict(schema="heatdrive_ecc_native_window_ledger_v1", ledger_computation_pass=True,
                      components=[dict(block_path=str(k), mask_type="Pipe (TL)", energy_equation_accumulation_J=6 / 119,
                                       mass_start_kg=1 / 119) for k in range(119)])
        return p, ledger

    def test_boundary_signs_and_constitutive_not_double_counted(self):
        p, ledger = self.fixture()
        result = assemble(np.array([0., 1.]), p, np.full(2, 6.), np.zeros(2), ledger, 0)
        self.assertAlmostEqual(result["external_thermal_net_input_J"], 5)
        self.assertAlmostEqual(result["measured_constitutive_net_input_J"], 1)
        self.assertAlmostEqual(result["native_equation_energy_residual_J"], 0)
        self.assertFalse(result["production_recovery_allowed"])
        self.assertFalse(result["full_device_first_law_verified"])

    def test_unmeasured_load_and_pressure_power_rejected(self):
        for name in ("Q_CHEX_load_to_sink_W", "P_pressure_source_native_W"):
            p, ledger = self.fixture(); p[name][:] = 1
            with self.assertRaises(ValueError):
                assemble(np.array([0., 1.]), p, np.full(2, 6.), np.zeros(2), ledger, 0)


if __name__ == "__main__":
    unittest.main()
