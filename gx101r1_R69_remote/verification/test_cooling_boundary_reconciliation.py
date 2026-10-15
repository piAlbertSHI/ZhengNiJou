import unittest
from pathlib import Path
import numpy as np

from Analyze_HeatDriveECC_CoolingBoundaryReconciliation import aligned_window_indices, flow_metric_split, integrals, reconciliation, stage_ids, summed_channels


class CoolingBoundaryReconciliationTests(unittest.TestCase):
    def test_original_absolute_schedule_and_final_horizon(self):
        time = np.array([600., 603.5, 605., 608.5, 610., 2000.])
        np.testing.assert_array_equal(stage_ids(time, 200, [0, 3.5, 5, 8.5], [3.5, 5, 8.5, 10]),
                                      [1, 2, 3, 4, 1, 4])

    def example(self, delta_storage=2.):
        t = np.arange(3.)
        # Q_H=5, net export=4, so dU=2 over two seconds.
        return reconciliation(t, np.array([False, True, True]), np.array([0., 6., 6.]),
                              np.full(3, -4.), np.full(3, 5.), np.full(3, 5.), delta_storage)

    def test_solver_quadrature_closes_independent_storage(self):
        row = self.example()['quadratures']['BE_J']
        self.assertEqual(row['independently_measured_pipe_residual_J'], 0)
        self.assertEqual(row['unexplained_after_physical_terms_J'], 0)
        self.assertEqual(row['difference_J'], 2)

    def test_real_inventory_error_cannot_be_hidden_by_decomposition(self):
        row = self.example(0.)['quadratures']['BE_J']
        self.assertEqual(row['independently_measured_pipe_residual_J'], 2)
        self.assertEqual(row['unexplained_after_physical_terms_J'], -2)
        self.assertEqual(row['bookkeeping_identity_error_J'], 0)

    def test_inactive_heat_is_retained_with_sign(self):
        row = self.example()['quadratures']['trapz_J']
        self.assertEqual(row['resolved_terms_J']['omitted_inactive_native_export_J'], -2)
        self.assertEqual(row['independently_measured_pipe_residual_J'], 0)

    def test_BE_and_trapz_are_not_interchangeable(self):
        row = integrals(np.arange(3.), np.array([0., 2., 4.]))
        self.assertEqual(row, {'BE_J': 6., 'trapz_J': 4.})

    def test_missing_values_rejected(self):
        with self.assertRaises(ValueError):
            integrals(np.arange(3.), np.array([1., np.nan, 3.]))

    def test_different_grids_rejected(self):
        with self.assertRaises(ValueError):
            integrals(np.array([0., 1., 1.]), np.ones(3))

    def test_float_activity_is_not_implicit_boolean(self):
        with self.assertRaises(ValueError):
            reconciliation(np.arange(3.), np.ones(3), *[np.ones(3)]*4, 0.)

    def test_one_ULP_does_not_create_a_different_solver_sample(self):
        time = 600+np.arange(3)*.001
        native = np.nextafter(time, np.inf)
        np.testing.assert_array_equal(aligned_window_indices(native, time), [0, 1, 2])

    def test_substep_clock_shift_is_not_interpolated(self):
        time = 600+np.arange(3)*.001
        with self.assertRaises(ValueError):
            aligned_window_indices(time+1e-7, time)

    def test_flow_location_is_separate_from_transport_metric(self):
        row = flow_metric_split(np.arange(3.), np.ones(3, dtype=bool), np.full(3, 2.),
                                np.ones(3), np.full(3, 3.), np.full(3, -2.))
        self.assertEqual(row['upstream_flow_location_difference']['BE_J'], 6.)
        self.assertEqual(row['remaining_same_native_flow_metric_minus_port_export']['BE_J'], 2.)

    def test_matched_flow_eliminates_only_the_location_term(self):
        row = flow_metric_split(np.arange(3.), np.ones(3, dtype=bool), np.ones(3),
                                np.ones(3), np.full(3, 3.), np.full(3, -2.))
        self.assertEqual(row['upstream_flow_location_difference']['BE_J'], 0.)
        self.assertNotEqual(row['remaining_same_native_flow_metric_minus_port_export']['BE_J'], 0.)

    def test_all_constitutive_nodes_are_summed_not_flattened(self):
        np.testing.assert_array_equal(summed_channels(np.array([[1., 2., 3.], [10., 20., 30.]]), 3),
                                      [11., 22., 33.])

    def test_transposed_channels_cannot_silently_change_metrics(self):
        with self.assertRaises(ValueError):
            summed_channels(np.ones((3, 21)), 3)

    def test_absent_stage4_flow_window_rejected(self):
        with self.assertRaises(ValueError):
            flow_metric_split(np.arange(3.), np.zeros(3, dtype=bool), *[np.ones(3)]*4)

    def test_COP_declaration_divides_by_mean_source_power(self):
        source = (Path(__file__).parent/'Build_HeatDriveECC_ControlVolumeContract.m').read_text(encoding='utf-8')
        self.assertIn('Qcool_mean / (integral(max(Q_SHEX_source_to_sink_W,0) dt) / Delta t)', source)


if __name__ == '__main__':
    unittest.main()
