import unittest
from Audit_HeatDriveECC_ColdPassivePSObserver import check_topology, check_initial


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
