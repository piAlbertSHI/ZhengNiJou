import unittest
import json
from pathlib import Path
from tempfile import TemporaryDirectory

import h5py
import numpy as np

from Analyze_HeatDriveECC_SinglePipeReference import (
    measured_grid_difference, refinement_summary, require_solver_contract, sampled_global_energy, sampled_heat_equation)
from Analyze_HeatDriveECC_SinglePipeHeatStep import read_traces


class IntegratedReferenceTests(unittest.TestCase):
    def test_nested_measured_grid_without_interpolation(self):
        coarse = np.arange(3)*.001
        fine = np.arange(5)*.0005
        row = measured_grid_difference(coarse, coarse**2, fine, fine**2)
        self.assertEqual(row["max_abs_difference"], 0)
        self.assertFalse(row["interpolation_used"])
        changed = fine**2; changed[2] += .2
        self.assertAlmostEqual(measured_grid_difference(coarse, coarse**2, fine, changed)["max_abs_difference"], .2)

    def test_missing_shifted_or_nonfinite_grid_rejected(self):
        a = np.arange(3)*.001; b = np.arange(5)*.0005
        for clock, values in ((b+.0001, b), (b, b*np.nan), (b[:3], b[:3])):
            with self.assertRaises(ValueError):
                measured_grid_difference(a, a, clock, values)

    def test_refinement_order_and_nonconvergence_remain_distinct(self):
        row = refinement_summary([.002, .001])
        self.assertEqual(row["observed_log2_ratio"], 1.)
        self.assertTrue(row["decreased"])
        self.assertFalse(refinement_summary([.001, .002])["decreased"])
        self.assertIsNone(refinement_summary([0., 0.])["observed_log2_ratio"])

    def test_invalid_refinement_data_not_treated_as_zero_error(self):
        for values in ([np.nan, 1.], [-1., 1.], [.1]):
            with self.assertRaises(ValueError):
                refinement_summary(values)

    def test_trace_reader_uses_declared_grid_not_hardcoded_1ms(self):
        with TemporaryDirectory() as folder, h5py.File(Path(folder)/"fixture.mat", "w") as f:
            g = f.create_group("trace")
            for key, value in (("name", "T_I"), ("unit", "K")):
                g.create_dataset(key, data=np.array([ord(c) for c in value], dtype=np.uint16))
            g.create_dataset("time_s", data=np.arange(201)*.0005)
            g.create_dataset("values", data=np.full(201, 303.15))
            f.create_dataset("native_traces", data=np.array([g.ref], dtype=h5py.ref_dtype))
            clock, values = read_traces(f, "native_traces", step=.0005)
            self.assertEqual(len(clock), 201)
            self.assertEqual(values["T_I"][-1], 303.15)
            with self.assertRaises(ValueError):
                read_traces(f, "native_traces")

    def test_global_method_is_not_accepted_as_local_BE(self):
        case = {"fixed_step_s": .001, "solver_contract": {
            "integration_request": "global_ODE3", "global_solver": "ode3", "solver_type": "Fixed-step",
            "local_solver_enabled": "off", "global_fixed_step": "0.001", "wall_converter_handling": "zero"}}
        ex = {"integration": "global_ODE3"}
        self.assertIsInstance(require_solver_contract(ex, case, "global_ODE3"), dict)
        with self.assertRaises(ValueError):
            require_solver_contract(ex, case, "local_BE")
        case["solver_contract"]["local_solver_enabled"] = "on"
        with self.assertRaises(ValueError):
            require_solver_contract(ex, case, "global_ODE3")

    def test_global_energy_is_sampled_quadrature_not_a_BE_gate(self):
        time = np.arange(11)*.1
        values = np.exp(-time)
        rows = {"u_I": values, "Phi_A": np.zeros(11), "Phi_B": np.zeros(11), "Q_H": -values}
        result = sampled_global_energy(time, rows, 1., post_start=.2)
        self.assertFalse(result["BE_step_residual_gate_applicable"])
        self.assertFalse(result["discrete_stage_energy_closure_verified"])
        self.assertFalse(result["scientific_pass_or_fail_claimed"])
        self.assertNotEqual(result["whole_storage_minus_trapezoid_J"], 0.)
        self.assertLess(abs(result["post_step_storage_minus_Simpson_J"]), 1e-6)

    def test_missing_stage_flux_does_not_get_synthetic_energy_proof(self):
        time = np.arange(4)*.001
        rows = {name: np.zeros(4) for name in ("Phi_A", "Phi_B", "Q_H", "u_I")}
        with self.assertRaises(ValueError):
            sampled_global_energy(time, rows, 1.)
        self.assertFalse(sampled_global_energy(time, rows, 1., post_start=.001)["ODE3_internal_stage_fluxes_captured"])

    def test_global_roundoff_failure_is_preserved_not_relaxed(self):
        expected = np.array([40., 45.]); actual = expected + 1e-7
        result = sampled_heat_equation(actual, expected, "global_ODE3")
        json.dumps(result, allow_nan=False)
        self.assertFalse(result["sampled_roundoff_identity_pass"])
        self.assertLess(result["unchanged_roundoff_allowance_W"], 1e-9)
        with self.assertRaises(ValueError):
            sampled_heat_equation(actual, expected, "local_BE")
        self.assertTrue(sampled_heat_equation(expected, expected, "local_BE")["sampled_roundoff_identity_pass"])


if __name__ == "__main__":
    unittest.main()
