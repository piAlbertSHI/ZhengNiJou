import unittest
from pathlib import Path

import numpy as np

from Analyze_HeatDriveECC_TcPhaseRejection import phase_cycles, phase_only_failures


class TcPhaseRejectionTests(unittest.TestCase):
    def test_retired_rejected_history_cannot_resume_in_place(self):
        source = (Path(__file__).parent/'Run_HeatDriveECC_RuntimeTcPackets.m').read_text()
        self.assertIn("~isfile(fullfile(root,'HISTORICAL_RAW_RETIRED.json'))", source)
        self.assertIn('target<=2000', source)
        analysis = (Path(__file__).parent/'Analyze_HeatDriveECC_TcPhaseRejection.py').read_text()
        self.assertIn("collection/'HISTORICAL_RAW_RETIRED.json'", analysis)
        self.assertIn('use the sealed attribution', analysis)

    def test_single_or_two_phase_failures_remain_rejected_diagnostics(self):
        for names in (['SE_phase_swing'], ['qian_table4_half_cycle_phase_completion'],
                      ['SE_phase_swing', 'qian_table4_half_cycle_phase_completion']):
            self.assertEqual(phase_only_failures({name: False for name in names}), names)

    def test_other_scientific_failure_cannot_be_hidden_by_attribution(self):
        for checks in ({'SE_phase_swing': True}, {'SE_phase_swing': False, 'SE_solid_energy_balance': False}):
            with self.assertRaises(ValueError):
                phase_only_failures(checks)

    def test_cycle_minimum_does_not_substitute_for_cold_half_completion(self):
        time = 1160+np.arange(20001)*.001
        value = np.full((21, 20001), .5)
        value[:, 0] = .001
        rows = phase_cycles(time, value)
        self.assertAlmostEqual(rows[0]['mean_phase_min'], .001)
        self.assertIsNone(rows[0]['cold_half_completion_s'])
        self.assertFalse(rows[0]['original_cold_half_1_percent_completion_pass'])

    def test_original_thresholds_and_event_timing(self):
        time = 1160+np.arange(20001)*.001
        value = np.ones((21, 20001))
        value[:, 7500] = .009
        value[:, 17500] = .0101
        rows = phase_cycles(time, value)
        self.assertAlmostEqual(rows[0]['cold_half_completion_s'], 2.5)
        self.assertTrue(rows[0]['original_99_percent_swing_pass'])
        self.assertIsNone(rows[1]['cold_half_completion_s'])
        self.assertFalse(rows[1]['original_99_percent_swing_pass'])

    def test_missing_node_or_incomplete_trace_rejected(self):
        time = 1160+np.arange(20001)*.001
        with self.assertRaises(ValueError):
            phase_cycles(time, np.zeros((20, 20001)))


if __name__ == '__main__':
    unittest.main()
