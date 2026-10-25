import copy
from pathlib import Path
import unittest

from Analyze_HeatDriveECC_CaloricCycle import read_packet, summarize, compare_packets, control_volumes


class CaloricReviewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path("C:/tmp/se21_caloric_coupled_cold_C1_r4_20261025")
        cls.record, cls.model, cls.clock, cls.states, cls.props = read_packet(cls.root)

    def test_reader_reconstructs_energy_without_promoting_mechanism(self):
        result = summarize(self.record, self.model, self.clock, self.states, self.props)
        self.assertLess(result["independent_selected_energy_residual_max_J"], 1e-8)
        for key in ("outer_solve_allowed", "production_recovery_allowed", "all_mechanism_gates_pass_claim",
                    "physical_first_law_validation_claim", "paired_Table4_allowed"):
            self.assertIs(result[key], False)
        self.assertEqual(len(result["before_blow_phase_observations"]), 1)
        margin = result["conditional_loading_margins"][0]
        self.assertLess(margin["full_coordinate_margin_at_observed_T_MPa"], 0.)
        self.assertIs(margin["counterfactual_state_used_for_continuation"], False)

    def test_energy_change_cannot_hide_behind_execution_success_flag(self):
        y = self.states.copy()
        y[-1, self.model.slices["solid_r"].start] += .01
        with self.assertRaises(ValueError):
            summarize(self.record, self.model, self.clock, y, self.props)

    def test_invalid_phase_cannot_hide_behind_good_energy(self):
        y = self.states.copy()
        y[-1, self.model.slices["phase_r"].start] = 1.01
        with self.assertRaises(ValueError):
            summarize(self.record, self.model, self.clock, y, self.props)

    def test_prior_integrator_producer_not_misclassified_as_bad_data(self):
        result = compare_packets(Path("C:/tmp/se21_caloric_coupled_cold_C1_r3_20261025"), self.root)
        self.assertIs(result["physical_contract_equal"], True)
        self.assertLess(result["maximum_selected_Tr_difference_K"], .001)
        self.assertLess(result["maximum_selected_xr_difference_fraction"], 1e-4)

    def test_missing_dense_second_cycle_is_not_silently_interpolated(self):
        record = copy.deepcopy(self.record)
        record["cycles"] = 2
        with self.assertRaises(ValueError):
            summarize(record, self.model, self.clock, self.states, self.props)

    def test_pump_and_pipe_wall_unknowns_are_not_zero(self):
        rows = control_volumes(self.model)
        pump = next(r for r in rows if r["volume"] == "SMA and SE pump work")
        self.assertIn("NOT zero", pump["qualification"])
        self.assertIn("unresolved", next(r for r in rows if r["volume"] == "connecting pipe walls/manifolds")["qualification"])


if __name__ == "__main__":
    unittest.main()
