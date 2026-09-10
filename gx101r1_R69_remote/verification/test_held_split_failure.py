import unittest
from copy import deepcopy
from decimal import Decimal
import numpy as np
from unittest.mock import patch
from Audit_HeatDriveECC_HeldSplitFailure import (local_settings, effective_consistency, failed_history,
    check_configuration, POLICY, TOL)


class HeldSplitFailureTests(unittest.TestCase):
    def setUp(self):
        self.old = dict(ConsistencyTolSource='GLOBAL', ConsistencyAbsTol='.001',
            ConsistencyRelTol='.001', ConsistencyTolFactor='0.001', ResidualTolerance='.001', UseLocalSolver='off')

    def test_effective_consistency_preserved_with_tighter_global_tolerances(self):
        before = deepcopy(self.old); local = local_settings(self.old)
        old = effective_consistency(self.old, dict(AbsTol='1e-8', RelTol='1e-6'))
        self.assertEqual(old, (Decimal('1e-11'), Decimal('1e-9')))
        self.assertEqual(old, effective_consistency(local, dict(AbsTol='1e-12', RelTol='1e-10')))
        self.assertEqual(self.old, before)
        self.assertEqual({k for k in local if local[k] != before[k]},
                         {'ConsistencyTolSource', 'ConsistencyAbsTol', 'ConsistencyRelTol'})

    def test_unexpected_baseline_rejected(self):
        for key, value in [('ConsistencyTolSource', 'LOCAL'), ('ConsistencyTolFactor', '1')]:
            with self.assertRaises(ValueError): local_settings(dict(self.old, **{key:value}))

    def test_unknown_source_rejected(self):
        with self.assertRaises(ValueError):
            effective_consistency(dict(self.old, ConsistencyTolSource='unknown'), {})

    def test_failed_window_not_confused_with_full_window(self):
        def row(t, v): return dict(time_s=np.array(t), values=np.array(v))
        failed_history(row([0, 1e-301], [1, 1]))
        for r in (row([0, .04], [1, 1]), row([0, 1e-301], [1, np.nan]),
                  row([0, 2e-301, 1e-301], [1, 1, 1]), row([], [])):
            with self.assertRaises(ValueError): failed_history(r)

    def configuration_pair(self):
        cb = dict(solver_settings=deepcopy(self.old), passive_observer_solver=dict(settings=deepcopy(self.old)),
                  targets=[dict(value=1, priority='High')], RelTol='1e-6', AbsTol='1e-8')
        b = dict(consistency_settings_after=deepcopy(self.old), global_tolerances_after=dict(RelTol='1e-6', AbsTol='1e-8'),
            passive_ps_observer_contract=dict(observer_solver_contract=dict(settings=deepcopy(self.old))),
            runtime_callbacks=[deepcopy(cb) for _ in range(3)])
        for k in ('global_solver_configuration', 'global_tolerances', 'runtime_solver_options_after',
                  'source_native_sha256', 'inventory_formulation', 'output_sampling_settings',
                  'ps_initial_actuation_contract', 'held_interval_contract', 'held_max_step_override_s',
                  'consistency_settings_before', 'model_nominal_value_table', 'buffer_nominal_changes',
                  'initial_pressure_derivative_contract', 'pressure_value_path_contract',
                  'inactive_controller_removal_contract', 'solver_iteration_options'):
            b[k] = dict(unchanged=True)
        r = deepcopy(b); r['global_tolerances_after'] = TOL
        r['solver_failure_policy_before'] = dict(POLICY, MinStepSizeMsg='warning')
        r['solver_failure_policy_after'] = POLICY
        r['consistency_settings_after'] = local_settings(self.old)
        r['passive_ps_observer_contract']['observer_solver_contract']['settings'] = local_settings(self.old)
        for c in r['runtime_callbacks']:
            c.update(TOL); c['solver_settings'] = local_settings(self.old)
            c['passive_observer_solver']['settings'] = local_settings(self.old)
        return r, b

    @patch('Audit_HeatDriveECC_HeldSplitFailure.check_held_contract')
    @patch('Audit_HeatDriveECC_HeldSplitFailure.check_discrete_constitutive_blocks')
    def test_only_declared_nested_configuration_changes_allowed(self, discrete, held):
        r, b = self.configuration_pair(); before = deepcopy(b)
        check_configuration(r, b)
        self.assertEqual(b, before); self.assertEqual(discrete.call_count, 3); held.assert_called_once()
        for location, key, value in (
                ('callback', 'targets', []), ('callback', 'new_undeclared_field', True),
                ('observer', 'ResidualTolerance', '1'), ('observer', 'ConsistencyTolFactor', '1'),
                ('top', 'source_native_sha256', 'other'), ('top', 'model_nominal_value_table', [])):
            changed = deepcopy(r)
            target = (changed['runtime_callbacks'][0] if location == 'callback' else
                changed['passive_ps_observer_contract']['observer_solver_contract']['settings']
                if location == 'observer' else changed)
            target[key] = value
            with self.subTest(location=location, key=key), self.assertRaises(ValueError):
                check_configuration(changed, b)
