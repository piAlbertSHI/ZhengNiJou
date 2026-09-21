import unittest
from pathlib import Path


class ColdPreflightGateTests(unittest.TestCase):
    def test_preflight_is_two_cycle_and_diagnostic_only(self):
        source = (Path(__file__).parent / "Audit_HeatDriveECC_ColdPreflightGate.py").read_text(encoding="utf-8")
        self.assertIn('"heatdrive_ecc_cold_preflight_gate_v1"', source)
        self.assertIn('flow.get("cycle_count") == 2', source)
        self.assertIn('flow.get("logged_window_start_s") == 10', source)
        self.assertIn('flow.get("logged_window_stop_s") == 20', source)
        self.assertIn('execution.get("stop_time_s") == 20', source)
        self.assertIn('"production_recovery_allowed": False', source)
        self.assertIn('"outer_solve_eligible": False', source)
        self.assertIn('"paired_table4_eligible": False', source)


if __name__ == "__main__":
    unittest.main()
