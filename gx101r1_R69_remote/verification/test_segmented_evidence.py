import copy
import unittest

import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import compare


class SplitEvidenceTests(unittest.TestCase):
    def traces(self):
        return {"model::state": dict(time=np.array([0., .001, .002, .003]),
                                     values=np.array([[0.], [1.], [2.], [3.]]), unit="K")}

    def test_exact_values(self):
        a = self.traces()
        result = compare(a, copy.deepcopy(a), 0, .003, .001)
        self.assertTrue(result["float64_bits_identical"])
        self.assertEqual(result["scalar_comparisons"], 4)

    def test_signed_zero_differs_bitwise(self):
        a, b = self.traces(), self.traces()
        b["model::state"]["values"][0, 0] = -0.
        result = compare(a, b, 0, .003, .001)
        self.assertEqual(result["max_abs_difference"], 0)
        self.assertFalse(result["float64_bits_identical"])

    def test_terminal_difference_is_retained(self):
        a, b = self.traces(), self.traces()
        b["model::state"]["values"][-1, 0] += .25
        result = compare(a, b, 0, .003, .001)
        self.assertEqual(result["max_abs_difference"], .25)
        self.assertFalse(result["float64_bits_identical"])

    def test_nonfinite_rejected(self):
        a, b = self.traces(), self.traces()
        b["model::state"]["values"][2, 0] = np.nan
        with self.assertRaises(ValueError):
            compare(a, b, 0, .003, .001)

    def test_grid_mismatch_rejected(self):
        a, b = self.traces(), self.traces()
        b["model::state"]["time"][2] += .0001
        with self.assertRaises(ValueError):
            compare(a, b, 0, .003, .001)

    def test_unit_and_inventory_rejected(self):
        a, b = self.traces(), self.traces()
        b["model::state"]["unit"] = "Pa"
        with self.assertRaises(ValueError):
            compare(a, b, 0, .003, .001)
        with self.assertRaises(ValueError):
            compare(a, {}, 0, .003, .001)


if __name__ == "__main__":
    unittest.main()
