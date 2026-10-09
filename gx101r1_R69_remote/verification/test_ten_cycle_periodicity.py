import unittest
from pathlib import Path
from unittest.mock import patch

from Analyze_HeatDriveECC_DiagnosticSteadiness import ten_cycle_periodicity


class TenCyclePeriodicityTests(unittest.TestCase):
    def fixture(self):
        execution=dict(execution_commit='producer',cycle_count=82,stop_time_s=820)
        receipt=dict(schema='heatdrive_ecc_saved_ten_cycle_thermal_periodicity_v1',
            source_execution_commit='producer',total_cycles=82,source_execution_sha256='bound',
            source_observation_sha256='bound',source_configuration_sha256='bound',
            absolute_window_s=[720,820],periodic_window_cycles=10,exact_grid_sample_count=100001)
        for key in ('pre_refactor_pair_exactly_equal','full_summary_before_after_exactly_equal',
                    'public_material_fields_exactly_equal','original_periodic_predicates_used'):
            receipt[key]=True
        for key in ('simulation_executed','operating_point_loaded','physical_tolerances_changed',
                    'production_recovery_allowed','outer_solve_eligible','table4_reproduction_claim',
                    'complete_internal_state_periodicity_verified','full_device_first_law_verified'):
            receipt[key]=False
        return execution,receipt

    @patch('Analyze_HeatDriveECC_DiagnosticSteadiness.sha256',return_value='bound')
    def test_ten_cycle_observation_does_not_require_opaque_solver_mapping(self,unused):
        execution,receipt=self.fixture()
        self.assertIs(ten_cycle_periodicity(Path('.'),execution,receipt),receipt)

    @patch('Analyze_HeatDriveECC_DiagnosticSteadiness.sha256',return_value='bound')
    def test_window_equivalence_and_scope_must_be_explicit(self,unused):
        execution,receipt=self.fixture()
        for key in ('absolute_window_s','source_observation_sha256','exact_grid_sample_count',
                    'full_summary_before_after_exactly_equal','production_recovery_allowed',
                    'complete_internal_state_periodicity_verified'):
            changed=dict(receipt);changed[key]=None
            with self.subTest(key=key),self.assertRaises(ValueError):
                ten_cycle_periodicity(Path('.'),execution,changed)

    def test_production_delegates_and_preserves_nearest_rank_and_window_guard(self):
        root=Path(__file__).resolve().parents[1]
        caller=(root/'Summarize_HeatDriveECC_EighthRound_Output.m').read_text()
        helper=(root/'Evaluate_HeatDriveECC_Periodicity.m').read_text()
        self.assertIn('Evaluate_HeatDriveECC_Periodicity(physical, options)',caller)
        self.assertIn('ceil(0.99 * numel(differences))',helper)
        self.assertIn('options.cycle_count >= 10',helper)
        self.assertIn("'SHEX_T_K','HHEX_T_K','CHEX_T_K'",helper)
        self.assertNotIn('same_phase_drift_statistics(',caller)
