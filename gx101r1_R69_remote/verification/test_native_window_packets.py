import copy
import unittest

import numpy as np

from Audit_HeatDriveECC_NativeWindowPackets import exact_match, unpack_columns


class NativePacketTests(unittest.TestCase):
    def columns(self):
        return [dict(block_path="test", state_name="x", unit="K", first_column_1based=1, channel_count=2)]

    def test_lossless_matrix_views(self):
        time = np.array([0., 1.])
        values = np.array([[-0., 2.], [3., 4.]])
        rows = unpack_columns(time, values, self.columns())
        self.assertEqual(exact_match(rows, rows), 4)
        changed = copy.deepcopy(rows)
        changed["test::x"]["values"][0, 0] = 0.
        with self.assertRaises(ValueError):
            exact_match(rows, changed)

    def test_rejects_column_gaps_overlaps_and_unassigned(self):
        for key, value in (("first_column_1based", 2), ("channel_count", 1), ("channel_count", 3),
                           ("channel_count", 1.5)):
            columns = self.columns()
            columns[0][key] = value
            with self.assertRaises(ValueError):
                unpack_columns(np.array([0., 1.]), np.zeros((2, 2)), columns)

    def test_rejects_single_precision_nonfinite_and_wrong_sample_count(self):
        for values in (np.zeros((2, 2), dtype=np.float32), np.full((2, 2), np.nan), np.zeros((3, 2))):
            with self.assertRaises(ValueError):
                unpack_columns(np.array([0., 1.]), values, self.columns())

    def test_time_bits_and_units_are_checked(self):
        rows = unpack_columns(np.array([0., 1.]), np.zeros((2, 2)), self.columns())
        changed = copy.deepcopy(rows)
        changed["test::x"]["time"][0] = -0.
        with self.assertRaises(ValueError):
            exact_match(rows, changed)
        changed = copy.deepcopy(rows)
        changed["test::x"]["unit"] = "Pa"
        with self.assertRaises(ValueError):
            exact_match(rows, changed)


if __name__ == "__main__":
    unittest.main()
