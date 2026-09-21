import unittest
from pathlib import Path


class Stage2TransitionConfoundingTests(unittest.TestCase):
    def test_analysis_is_diagnostic_only_and_requires_three_cases(self):
        source = (Path(__file__).parent / "Analyze_HeatDriveECC_Stage2TransitionConfounding.py").read_text(encoding="utf-8")
        self.assertIn('"heatdrive_ecc_stage2_transition_confounding_v1"', source)
        self.assertIn('v17_one_cycle_transition_0_10', source)
        self.assertIn('v19_twenty_cycle_final_window', source)
        self.assertIn('v21_two_cycle_transition_10_20', source)
        self.assertIn('"production_recovery_allowed": False', source)
        self.assertIn('"confounded_by_stage4_transition"', source)


if __name__ == "__main__":
    unittest.main()
