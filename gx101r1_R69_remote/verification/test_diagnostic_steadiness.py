import unittest
from pathlib import Path
from unittest.mock import patch

from Analyze_HeatDriveECC_DiagnosticSteadiness import core_periodicity, completed_mechanism, production_periodicity


class DiagnosticSteadinessTests(unittest.TestCase):
    def fixture(self):
        metrics=dict(endpoint_max=0,same_phase_p99=0,same_phase_rms=0,same_phase_max=100)
        limits={key:1 for key in ('max_periodic_endpoint_drift_K',
            'max_periodic_same_phase_temperature_p99_drift_K','max_periodic_same_phase_temperature_rms_drift_K',
            'max_periodic_phase_drift','max_periodic_same_phase_phase_p99_drift','max_periodic_same_phase_phase_rms_drift')}
        return dict(solid_temperature_drift_K=metrics.copy(),solid_phase_fraction_drift=metrics.copy()),limits

    def test_peak_does_not_replace_solid_only_robust_predicates(self):
        arm,limits=self.fixture();result=core_periodicity(arm,limits)
        self.assertTrue(result['last_pair_core_predicates_pass'])
        self.assertTrue(result['same_phase_maxima_are_nonblocking_diagnostics'])
        self.assertFalse(result['equivalent_to_original_production_predicates'])

    def test_each_solid_only_predicate_can_independently_fail(self):
        for group in ('solid_temperature_drift_K','solid_phase_fraction_drift'):
            for key in ('endpoint_max','same_phase_p99','same_phase_rms'):
                arm,limits=self.fixture();arm[group][key]=2
                self.assertFalse(core_periodicity(arm,limits)['last_pair_core_predicates_pass'])

    def mechanism_fixture(self):
        physics={'input_sha256':{'native\\observations.mat':'observation',
                                  'native\\configuration.mat':'configuration'}}
        execution=dict(execution_commit='producer',stop_time_s=220)
        receipt=dict(schema='heatdrive_ecc_saved_production_mechanism_audit_v1',
            source_execution_commit='producer',source_execution_sha256='execution',
            source_observation_sha256='observation',source_configuration_sha256='configuration',
            original_production_predicates_evaluated=True,exact_saved_window_pass=True,
            simulation_executed=False,operating_point_loaded=False,
            checks={str(idx):True for idx in range(73)},
            analysis_window=dict(absolute_start_s=200,absolute_stop_s=220))
        return physics,execution,receipt

    @patch('Analyze_HeatDriveECC_DiagnosticSteadiness.sha256',return_value='execution')
    def test_full_mechanism_pass_is_separate_from_periodicity(self,unused):
        physics,execution,receipt=self.mechanism_fixture()
        result=completed_mechanism(Path('.'),physics,execution,receipt)
        self.assertTrue(result['pass_gate'])
        receipt['checks']['0']=False
        result=completed_mechanism(Path('.'),physics,execution,receipt)
        self.assertFalse(result['pass_gate'])
        self.assertEqual(result['failed_checks'],['0'])

    @patch('Analyze_HeatDriveECC_DiagnosticSteadiness.sha256',return_value='execution')
    def test_wrong_source_window_or_nonboolean_check_rejected(self,unused):
        for mutation in ('source_execution_commit','source_observation_sha256','source_configuration_sha256',
                         'window','nonboolean','missing'):
            physics,execution,receipt=self.mechanism_fixture()
            if mutation=='window':receipt['analysis_window']['absolute_stop_s']=210
            elif mutation=='nonboolean':receipt['checks']['0']=1
            elif mutation=='missing':del receipt['checks']['0']
            else:receipt[mutation]='wrong'
            with self.assertRaises(ValueError):completed_mechanism(Path('.'),physics,execution,receipt)

    @patch('Analyze_HeatDriveECC_DiagnosticSteadiness.sha256',return_value='bound')
    def test_exact_original_receipt_cannot_promote_a_last_pair(self,unused):
        execution=dict(execution_commit='producer',stop_time_s=620)
        receipt=dict(schema='heatdrive_ecc_saved_production_periodicity_v1',
            source_execution_commit='producer',source_execution_sha256='bound',
            source_observation_sha256='bound',source_configuration_sha256='bound',
            original_summarizer_used=True,physical_tolerances_changed=False,
            simulation_executed=False,operating_point_loaded=False,periodic_window_cycles=2,
            ten_cycle_production_window_verified=False,periodic_steady_state_verified=False,
            production_recovery_allowed=False,analysis_window=dict(absolute_start_s=600,absolute_stop_s=620))
        self.assertIs(production_periodicity(Path('.'),execution,receipt),receipt)
        for key in ('ten_cycle_production_window_verified','periodic_steady_state_verified',
                    'production_recovery_allowed','physical_tolerances_changed','simulation_executed'):
            with self.subTest(key=key):
                changed=dict(receipt);changed[key]=True
                with self.assertRaises(ValueError):production_periodicity(Path('.'),execution,changed)

    def test_saved_periodicity_uses_original_summarizer_without_inflating_window(self):
        source=Path(__file__).with_name('Audit_HeatDriveECC_SavedPeriodicity.m').read_text()
        self.assertIn('Summarize_HeatDriveECC_EighthRound_Output(view.physical, view.options)',source)
        self.assertIn('view.options.cycle_count == 2',source)
        self.assertNotIn('cycle_count = 10',source)
        self.assertNotIn('sim(',source)
