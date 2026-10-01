import unittest

from Audit_HeatDriveECC_Stage4ControlContract import (
    STRICT_WINDOW,
    summarize_window,
)


class Stage4ControlContractAuditTest(unittest.TestCase):
    def test_strict_window_is_explicit(self):
        self.assertEqual(STRICT_WINDOW, (9.84, 9.85))

    def test_window_summary_keeps_raw_signal_statistics(self):
        import numpy as np

        time = np.arange(0.0, 10.001, 0.001)
        result = summarize_window(
            time, {"signal": np.ones(time.size)}, *STRICT_WINDOW
        )
        self.assertEqual(result["samples"], 11)
        self.assertEqual(result["signal"]["nonzero_fraction"], 1.0)


if __name__ == "__main__":
    unittest.main()
