import copy
import unittest

from Compare_HeatDriveECC_SameTcRepeatability import compare_metrics, window_lineage


class SameTcRepeatabilityTest(unittest.TestCase):
    def test_original_precision_pass(self):
        a = dict(temperature_lift_eq9_K=30., SCP_W_per_g=.28)
        b = dict(temperature_lift_eq9_K=30.08, SCP_W_per_g=.285)
        r = compare_metrics(a, b, .1, .01)
        self.assertTrue(r['disjoint_metric_repeatability_pass'])
        self.assertFalse(r['asymptotic_error_bound_claim'])
        self.assertFalse(r['exact_internal_periodicity_claim'])
        self.assertFalse(r['new_physical_threshold_imposed'])

    def test_failure_does_not_change_tolerance(self):
        a = dict(temperature_lift_eq9_K=30., SCP_W_per_g=.28)
        for key, value in (('temperature_lift_eq9_K', 30.11), ('SCP_W_per_g', .291)):
            b = dict(a); b[key] = value
            self.assertFalse(compare_metrics(a, b, .1, .01)['disjoint_metric_repeatability_pass'])

    def test_modified_or_nonfinite_precision_rejected(self):
        a = dict(temperature_lift_eq9_K=30., SCP_W_per_g=.28)
        with self.assertRaises(ValueError):
            compare_metrics(a, a, .2, .01)
        b = dict(a); b['SCP_W_per_g'] = float('nan')
        with self.assertRaises(ValueError):
            compare_metrics(a, b, .1, .01)

    def pair(self):
        a = dict(current_window_s=[880, 980], temperature_K=274.85,
            same_Tc_continuation=True, source_state_edited=False,
            all_four_memories_bitwise_preserved=True,
            all_original_packet_mechanism_flow_phase_energy_gates_pass=True,
            original_public_thermal_periodic_pass=True,
            current_target_window_stability=dict(precision_pass=True))
        b = copy.deepcopy(a); b['current_window_s'] = [980, 1080]
        return a, b

    def test_actual_disjoint_windows_pass(self):
        a, b = self.pair()
        self.assertEqual(window_lineage(a, b), ([880, 980], [980, 1080]))

    def test_overlapping_windows_do_not_prove_repetition(self):
        a, b = self.pair(); b['current_window_s'] = [900, 1000]
        with self.assertRaises(ValueError):
            window_lineage(a, b)

    def test_wrong_temperature_or_unqualified_point_rejected(self):
        a, b = self.pair(); b['temperature_K'] += .1
        with self.assertRaises(ValueError):
            window_lineage(a, b)
        for field in ('all_original_packet_mechanism_flow_phase_energy_gates_pass',
                      'all_four_memories_bitwise_preserved', 'original_public_thermal_periodic_pass'):
            a, b = self.pair(); b[field] = False
            with self.assertRaises(ValueError):
                window_lineage(a, b)


if __name__ == '__main__':
    unittest.main()
