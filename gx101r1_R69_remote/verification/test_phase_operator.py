import copy
from pathlib import Path
import unittest

from Analyze_HeatDriveECC_PhaseOperator import compare_cold, check_ablation_contract, scheduled_structure, shared_operator_source_signature
from Analyze_HeatDriveECC_CaloricCycle import read_packet


class PhaseOperatorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.old = Path("C:/tmp/se21_caloric_coupled_cold_C1_r4_20261025")
        cls.new = Path("C:/tmp/se21_two_way_phase_cold_C1_r1_20261025")
        cls.record, cls.model, cls.clock, cls.values, cls.properties = read_packet(cls.old)

    def test_actual_structural_control_is_not_numerical_noise_or_qualification(self):
        result, _, _, _ = compare_cold(self.old, self.new)
        self.assertGreater(result["maximum_selected_Tr_difference"], 1.)
        self.assertGreater(result["maximum_selected_xr_difference"], .05)
        self.assertIs(result["all_initial_coordinates_bitwise_equal"], True)
        self.assertIs(result["production_seed_allowed"], False)
        self.assertIs(result["Qian_MAS_material_identified"], False)

    def test_other_boundary_change_cannot_masquerade_as_operator_only(self):
        old = self.record["network_contract"]
        new = copy.deepcopy(read_packet(self.new)[0]["network_contract"])
        new["source_K"] += 1.
        with self.assertRaises(ValueError):
            check_ablation_contract(old, new)

    def test_same_state_witness_keeps_all_physical_coordinates_fixed(self):
        report = scheduled_structure(self.record, self.model, self.clock, self.properties)
        for material in ("SMA", "SE"):
            witness = report["materials"][material]["max_difference_witness"]
            self.assertGreater(abs(witness["scheduled_hot_rate_per_s"]-witness["scheduled_cold_rate_per_s"]), .1)
            self.assertAlmostEqual(witness["two_way_net_rate_per_s"], witness["forward_flux_per_s"]-witness["reverse_flux_per_s"])
        self.assertIs(report["both_fluxes_positive_alone_is_not_a_thermodynamic_failure"], True)

    def test_unexecuted_kernel_edit_is_not_a_false_shared_operator_failure(self):
        source = Path(__file__).with_name("Reference_HeatDriveECC_TwoWayPhase.py").read_text(encoding="utf-8")
        changed = source.replace("za = np.sqrt(a)", "za = 2*np.sqrt(a)")
        self.assertEqual(shared_operator_source_signature(source), shared_operator_source_signature(changed))
        changed = source.replace("surface = material[", "surface = 1+material[")
        self.assertNotEqual(shared_operator_source_signature(source), shared_operator_source_signature(changed))


if __name__ == "__main__":
    unittest.main()
