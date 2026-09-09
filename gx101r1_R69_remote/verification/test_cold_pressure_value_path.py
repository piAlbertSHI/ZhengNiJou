import copy
import unittest
from Audit_HeatDriveECC_ColdPressureValuePath import check_value_edge


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


class ColdPressureValueTests(unittest.TestCase):
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
