import unittest

import numpy as np

from Audit_HeatDriveECC_NativeRefinementCase import initial_states_equal


class RefinementCaseTests(unittest.TestCase):
    def fixture(self):
        return {"test::state": dict(time=np.array([1800., 1800.001, 1800.002]),
                                  values=np.array([[0.], [1.], [2.]]), unit="K")}

    def test_keeps_multirate_state_history(self):
        base, candidate = self.fixture(), self.fixture()
        candidate["test::state"].update(time=np.array([1800., 1800.002]), values=np.array([[0.], [2.1]]))
        result = initial_states_equal(base, candidate, 1800, 1800.002)
        self.assertTrue(result["initial_state_bits_equal"])
        self.assertEqual(result["state_group_sample_counts"], {"2": 1})

    def test_changed_signed_zero_initial_state_rejected(self):
        base, candidate = self.fixture(), self.fixture()
        candidate["test::state"]["values"][0] = -0.
        with self.assertRaises(ValueError):
            initial_states_equal(base, candidate, 1800, 1800.002)

    def test_incomplete_nonfinite_or_duplicate_time_rejected(self):
        for field, values in (("time", [1800., 1800., 1800.002]), ("time", [1800., 1800.001, 1800.003]),
                              ("values", [[0.], [1.], [float("nan")]])):
            base, candidate = self.fixture(), self.fixture()
            candidate["test::state"][field] = np.asarray(values)
            with self.assertRaises(ValueError):
                initial_states_equal(base, candidate, 1800, 1800.002)


if __name__ == "__main__":
    unittest.main()
