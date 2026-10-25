import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

import h5py
import numpy as np

from Analyze_HeatDriveECC_SinglePipeReference import measured_grid_difference, refinement_summary
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


if __name__ == "__main__":
    unittest.main()
