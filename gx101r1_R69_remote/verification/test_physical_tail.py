import tempfile
import unittest
from pathlib import Path

import h5py
import numpy as np

from Export_HeatDriveECC_PhysicalTail import read_field


class PhysicalTailTests(unittest.TestCase):
    def test_tail_keeps_both_endpoints_and_all_coordinates(self):
        with tempfile.TemporaryDirectory() as directory, h5py.File(Path(directory) / "test.mat", "w") as file:
            data = np.arange(20, dtype=float).reshape(2, 10)
            field = file.create_dataset("values", data=data)
            field.attrs["MATLAB_class"] = np.bytes_("double")
            actual = read_field(file, field, 10, slice(6, 10))
            np.testing.assert_array_equal(actual, data[:, 6:10].T)
            self.assertEqual(actual.shape, (4, 2))

    def test_unknown_layout_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory, h5py.File(Path(directory) / "test.mat", "w") as file:
            field = file.create_dataset("values", data=np.zeros((2, 3)))
            field.attrs["MATLAB_class"] = np.bytes_("double")
            with self.assertRaises(ValueError):
                read_field(file, field, 10, slice(6, 10))

    def test_scalar_logical_is_not_a_time_series(self):
        with tempfile.TemporaryDirectory() as directory, h5py.File(Path(directory) / "test.mat", "w") as file:
            field = file.create_dataset("value", data=np.array([[0]], dtype=np.uint8))
            field.attrs["MATLAB_class"] = np.bytes_("logical")
            actual = read_field(file, field, 10, slice(6, 10))
            self.assertEqual(actual.dtype, bool)
            self.assertFalse(actual[0, 0])


if __name__ == "__main__":
    unittest.main()
