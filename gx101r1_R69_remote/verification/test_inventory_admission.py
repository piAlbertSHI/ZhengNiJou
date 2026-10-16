import unittest
import numpy as np

from Analyze_HeatDriveECC_InventoryAdmission import grouped_components, return_drift, signed_trend, storage_scales


class InventoryAdmissionTest(unittest.TestCase):
    def test_growth_is_not_decay(self):
        r = signed_trend(range(1, 11))
        self.assertTrue(r['magnitude_monotonically_increasing'])
        self.assertFalse(r['magnitude_monotonically_decreasing'])
        self.assertFalse(r['asymptotic_limit_or_error_bound_claim'])

    def test_signed_loss_is_not_growth_of_mass(self):
        r = signed_trend(range(-10, 0))
        self.assertTrue(r['same_nonzero_sign'])
        self.assertTrue(r['magnitude_monotonically_decreasing'])
        self.assertEqual(r['last_to_first_magnitude_ratio'], .1)

    def test_zero_initial_increment_has_no_ratio(self):
        self.assertIsNone(signed_trend(range(10))['last_to_first_magnitude_ratio'])

    def test_incomplete_or_nonfinite_trend_rejected(self):
        for values in ([1]*9, [1]*11, [1]*9+[float('nan')]):
            with self.assertRaises(ValueError):
                signed_trend(values)

    def components(self):
        return [dict(block_path='a', mask_type='buffer', energy_endpoint_change_J=-10,
                     pressure_volume_work_J=0),
                dict(block_path='b', mask_type='pipe', energy_endpoint_change_J=8,
                     pressure_volume_work_J=1)]

    def test_latent_once_pdv_once_and_units(self):
        r = storage_scales(self.components(), 3, 10, .04, .01)
        self.assertEqual(r['native_storage_plus_pdv_J'], -1)
        self.assertEqual(r['modeled_storage_including_latent_plus_pdv_J'], 2)
        self.assertEqual(r['equivalent_existing_metric_tolerance_W'], .4)
        self.assertEqual(r['sum_absolute_component_storage_rate_W'], 2.2)
        self.assertEqual(r['net_storage_scale_over_metric_tolerance'], .5)
        self.assertTrue(r['global_inventory_change_is_not_an_Eq10_error_bound'])
        self.assertTrue(r['rates_are_diagnostics_not_Eq10_corrections'])
        self.assertFalse(r['new_inventory_threshold_imposed'])

    def test_cancellation_does_not_prove_periodicity(self):
        rows = self.components(); rows[1]['energy_endpoint_change_J'] = 9
        r = storage_scales(rows, 0, 10, .04, .01)
        self.assertEqual(r['modeled_storage_mean_rate_W'], 0)
        self.assertEqual(r['sum_absolute_component_storage_rate_W'], 2)
        self.assertNotIn('periodic_pass', r)

    def test_bad_budget_inputs_rejected(self):
        for mass, tolerance, duration in ((0, .01, 10), (.04, 0, 10), (.04, .01, 30),
                                         (.04, float('inf'), 10)):
            with self.assertRaises(ValueError):
                storage_scales(self.components(), 0, duration, mass, tolerance)

    def test_intact_two_cycle_packet_rate(self):
        r = storage_scales(self.components(), 3, 20, .04, .01)
        self.assertEqual(r['modeled_storage_mean_rate_W'], .1)
        self.assertEqual(r['sum_absolute_component_storage_rate_W'], 1.1)

    def test_duplicate_component_rejected(self):
        rows = self.components(); rows[1]['block_path'] = 'a'
        with self.assertRaises(ValueError):
            storage_scales(rows, 0, 10, .04, .01)

    def test_nonfinite_component_rejected(self):
        rows = self.components(); rows[0]['energy_endpoint_change_J'] = float('nan')
        with self.assertRaises(ValueError):
            storage_scales(rows, 0, 10, .04, .01)

    def test_group_sums_preserve_sign_and_pdv(self):
        r = grouped_components(self.components())
        self.assertEqual(r['buffer']['energy_change_J'], -10)
        self.assertEqual(r['pipe']['pdv_J'], 1)
        self.assertEqual(sum(v['count'] for v in r.values()), 2)

    def test_PI_return_drift_is_not_restart_bitwise_test(self):
        time = np.arange(20001)*.001+880
        values = (time-880).reshape(1, -1)
        r = return_drift(time, values)
        np.testing.assert_allclose(r['cycle_increments'], [10, 10])
        self.assertAlmostEqual(r['same_phase_rms'], 10)
        self.assertFalse(r['tolerance_imposed'])

    def test_PI_return_rejects_missing_cycle(self):
        with self.assertRaises(ValueError):
            return_drift(np.arange(10001)*.001, np.zeros((1, 10001)))


if __name__ == '__main__':
    unittest.main()
