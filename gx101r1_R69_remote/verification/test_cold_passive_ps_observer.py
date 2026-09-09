import unittest
from Audit_HeatDriveECC_ColdPassivePSObserver import check_topology, check_initial, check_live_input, check_actuation, summarize_coordinates


def topology(separate):
    p = 'heatdrive_ecc_coupled_se21/'
    c = dict(observer_path=p+'ColdSMAPassiveObserver', pressure_converter=p+'SMAPressurePI_SimulinkPS',
             pressure_value_source=p+'SMAPressureBiasFromWorkspace', pressure_derivative_source=p+'ColdInitialPressureDerivativeOnly',
             pressure_destinations_before=[p+'SMA Pressure Source (TL)'],
             pressure_destinations_after=[p+'SMA Pressure Source (TL)']+([] if separate else [p+'ColdSMAPassiveObserver']),
             observer_drives_pump=False, separate_solver_added=separate, allowed_stop_time_s=0,
             production_recovery_allowed=False, c200_state_imported=False)
    if separate:
        c.update(observer_bias_driver=p+'ColdObserver_bias_PS', observer_solver_contract=dict(
            copied_settings_identical=True, observer_path=p+'ColdObserver_Solver',
            settings=dict(UseLocalSolver='off', IndexReductionMethod='Projection')))
    return c


class PassiveObserverTests(unittest.TestCase):
    def test_live_bridge_cannot_fabricate_zero_derivative(self):
        p = 'heatdrive_ecc_coupled_se21/'
        c = dict(flow_input_mode='live_simulink_bridge', provided_flow_derivatives='0', flow_value_source=p+'FlowSensor_SMA_stage13_loop_PS')
        actual = dict(path=p+'ColdObserver_mdot_PS', Unit='kg/s', FilteringAndDerivatives='provide',
                      UdotUserProvided='0', input_count=1, value_source=c['flow_value_source'])
        self.assertTrue(check_live_input(c, actual))
        actual['UdotUserProvided'] = '1'; actual['input_count'] = 2
        with self.assertRaises(ValueError):
            check_live_input(c, actual)

    def actuation_fixture(self):
        c = topology(True); p = 'heatdrive_ecc_coupled_se21/'; driver = p+'ColdObserver_pressure_Output'
        a = dict(changed_inputs=[dict(destination=x, input=1, before=c['pressure_value_source'], after=driver)
                 for x in (c['pressure_converter'], p+'SMAPressurePI_Saturation')], pressure_driver=driver,
                 pressure_converter=c['pressure_converter'], pressure_derivative_source=c['pressure_derivative_source'],
                 observer_drives_pump=True, initial_feedback_enable=0, initial_reset=1, first_derivative_MPa_s=0,
                 allowed_stop_time_s=0, full_cycle_derivative_verified=False, c200_state_imported=False, production_recovery_allowed=False)
        return a, c

    def test_actuation_is_initial_only(self):
        a, c = self.actuation_fixture(); self.assertTrue(check_actuation(a, c))
        a['allowed_stop_time_s'] = .1
        with self.assertRaises(ValueError):
            check_actuation(a, c)

    def test_actuation_must_update_logging(self):
        a, c = self.actuation_fixture(); a['changed_inputs'].pop()
        with self.assertRaises(ValueError):
            check_actuation(a, c)

    def test_small_high_priority_failure_not_promoted(self):
        rows = [dict(within_strict_comparison=True, priority='Low', abs_error=0., limit=1e-9),
                dict(within_strict_comparison=False, priority='High', abs_error=2e-7, limit=7.7e-9)]
        summary = summarize_coordinates(rows)
        self.assertFalse(summary['strict_initial_coordinate_gate'])
        self.assertEqual(summary['matching_initial_coordinates'], 1)
        self.assertEqual(summary['failed_high_priority'], 1)

    def test_two_declared_topologies(self):
        for separate in (False, True):
            self.assertTrue(check_topology(topology(separate), separate))

    def test_accidental_actuation_rejected(self):
        c = topology(True); c['observer_drives_pump'] = True
        with self.assertRaises(ValueError):
            check_topology(c, True)

    def test_merged_branch_not_independent(self):
        c = topology(True); c['pressure_destinations_after'].append(c['observer_path'])
        with self.assertRaises(ValueError):
            check_topology(c, True)

    def test_altered_solver_rejected(self):
        c = topology(True); c['observer_solver_contract']['settings']['UseLocalSolver'] = 'on'
        with self.assertRaises(ValueError):
            check_topology(c, True)

    def test_initial_values_and_nonfinite(self):
        c = dict(commands=[dict(values=[-1e-6]), dict(values=[0.])], frozen_mdot_kg_s=-6e-10)
        values = [('mdot', 'kg/s', -6e-10), ('target', 'kg/s', 0), ('bias', 'MPa', -1e-6),
                  ('enable', '1', 0), ('reset', '1', 1), ('pressure', 'MPa', -1e-6), ('lag', '1', 0), ('integral', 'MPa', 0)]
        rows = [dict(name=n, unit=u, actual=v, source_time_s=0) for n, u, v in values]
        self.assertTrue(check_initial(rows, c))
        rows[-1]['actual'] = float('nan')
        with self.assertRaises(ValueError):
            check_initial(rows, c)


if __name__ == '__main__':
    unittest.main()
