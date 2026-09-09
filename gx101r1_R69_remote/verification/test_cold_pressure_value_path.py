import copy
import unittest
from Audit_HeatDriveECC_ColdPressureValuePath import check_value_edge, check_inactive_removal


def fixture():
    p = 'heatdrive_ecc_coupled_se21/'
    sat, bias, converter, derivative = [p+x for x in ('SMAPressurePI_Saturation', 'SMAPressureBiasFromWorkspace',
                                                    'SMAPressurePI_SimulinkPS', 'ColdInitialPressureDerivativeOnly')]
    before = [dict(path=p+str(k), sources=[]) for k in range(14)]+[dict(path=converter, sources=[sat, derivative])]
    after = copy.deepcopy(before); after[-1]['sources'][0] = bias
    return dict(inputs_before=before, inputs_after=after, original_controller_block_count=15, converter=converter,
                value_source_before=sat, value_source_after=bias, derivative_source=derivative,
                model_block_set_unchanged=True, converter_physical_line_unchanged=True, original_controller_retained=True,
                allowed_stop_time_s=0, c200_state_imported=False, production_recovery_allowed=False,
                saturation_limits_MPa=[-.35, .02], initial_bias_MPa=-1e-6)


def removal_fixture():
    value = fixture(); p = 'heatdrive_ecc_coupled_se21/'
    removed = [p+x for x in ('SMAPressurePI_ErrorSum', 'SMAPressurePI_ErrorNormalizer', 'SMAPressurePI_ErrorLag',
               'SMAPressurePI_Kp', 'SMAPressurePI_Ki', 'SMAPressurePEnableProduct', 'SMAPressurePI_Integrator', 'SMAPressurePI_BiasSum')]
    before = [dict(path=x, sources=[]) for x in removed]+[dict(path=p+str(k), sources=[]) for k in range(5)]
    sat = dict(path=p+'SMAPressurePI_Saturation', sources=[p+'SMAPressurePI_BiasSum'])
    before += [sat, dict(path=value['converter'], sources=[value['value_source_after'], value['derivative_source']])]
    value['inputs_after'] = copy.deepcopy(before)
    retained = copy.deepcopy(before[8:]); retained[-2]['sources'] = [value['value_source_after']]
    c = dict(removed_paths=removed, inputs_before=before, retained_inputs_after=retained,
             pressure_converter=value['converter'], pressure_value_source=value['value_source_after'],
             pressure_derivative_source=value['derivative_source'], logger_saturation=sat['path'],
             logger_value_source_after=value['value_source_after'], converter_physical_line_unchanged=True,
             only_expected_blocks_removed=True, candidate_ps_added=False, allowed_stop_time_s=0,
             c200_state_imported=False, production_recovery_allowed=False)
    return c, value


class ColdPressureValueTests(unittest.TestCase):
    def test_exact_inactive_removal(self):
        c, value = removal_fixture(); self.assertTrue(check_inactive_removal(c, value))

    def test_missing_or_extra_removed_block(self):
        c, value = removal_fixture(); c['removed_paths'].pop()
        with self.assertRaises(ValueError):
            check_inactive_removal(c, value)

    def test_pressure_derivative_must_survive_removal(self):
        c, value = removal_fixture(); c['retained_inputs_after'][-1]['sources'][1] = 'other'
        with self.assertRaises(ValueError):
            check_inactive_removal(c, value)

    def test_logger_must_track_bias(self):
        c, value = removal_fixture(); c['retained_inputs_after'][-2]['sources'] = []
        with self.assertRaises(ValueError):
            check_inactive_removal(c, value)

    def test_only_declared_edge_allowed(self):
        self.assertTrue(check_value_edge(fixture()))

    def test_second_input_change_rejected(self):
        c = fixture(); c['inputs_after'][-1]['sources'][1] = 'different_derivative'
        with self.assertRaises(ValueError):
            check_value_edge(c)

    def test_controller_removal_rejected(self):
        c = fixture(); c['inputs_after'].pop(0)
        with self.assertRaises(ValueError):
            check_value_edge(c)

    def test_unbounded_duration_and_bias_rejected(self):
        for change in (dict(allowed_stop_time_s=.1), dict(initial_bias_MPa=float('nan')), dict(initial_bias_MPa=1.)):
            c = fixture(); c.update(change)
            with self.assertRaises(ValueError):
                check_value_edge(c)


if __name__ == '__main__':
    unittest.main()
