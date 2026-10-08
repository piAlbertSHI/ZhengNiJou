import unittest

from Analyze_HeatDriveECC_DiagnosticSteadiness import core_periodicity


class DiagnosticSteadinessTests(unittest.TestCase):
    def fixture(self):
        metrics=dict(endpoint_max=0,same_phase_p99=0,same_phase_rms=0,same_phase_max=100)
        limits={key:1 for key in ('max_periodic_endpoint_drift_K',
            'max_periodic_same_phase_temperature_p99_drift_K','max_periodic_same_phase_temperature_rms_drift_K',
            'max_periodic_phase_drift','max_periodic_same_phase_phase_p99_drift','max_periodic_same_phase_phase_rms_drift')}
        return dict(solid_temperature_drift_K=metrics.copy(),solid_phase_fraction_drift=metrics.copy()),limits

    def test_peak_does_not_replace_original_robust_production_predicates(self):
        arm,limits=self.fixture();result=core_periodicity(arm,limits)
        self.assertTrue(result['last_pair_core_predicates_pass'])
        self.assertTrue(result['same_phase_maxima_are_nonblocking_diagnostics'])

    def test_each_original_predicate_can_independently_fail(self):
        for group in ('solid_temperature_drift_K','solid_phase_fraction_drift'):
            for key in ('endpoint_max','same_phase_p99','same_phase_rms'):
                arm,limits=self.fixture();arm[group][key]=2
                self.assertFalse(core_periodicity(arm,limits)['last_pair_core_predicates_pass'])
