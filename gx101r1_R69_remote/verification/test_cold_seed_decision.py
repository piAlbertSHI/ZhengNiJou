"""Cold seed classification must fail closed on missing mechanism gates."""
import unittest

from Classify_HeatDriveECC_ColdSeedAudit import classify


class ColdSeedDecisionTests(unittest.TestCase):
    def records(self):
        solid = {'selected_solid_energy_gate': True, 'all_node_phase_min': 0.0,
                 'all_node_phase_max': 1.0}
        arm = dict(arm='native', selected_flow_gates=[dict(component='SE', stage=2,
                   max_abs_relative_error=.01, rms_relative_error=.01, selected_flow_gate=True)],
                   selected_solid_balances={'SMA': solid, 'SE': solid})
        audit = dict(schema='heatdrive_ecc_cold_buffer_coupled_audit_v2', execution_commit='exact',
                     cycle_count=1, evidence_audit_pass=True, declared_window_numerical_gates_pass=True,
                     trajectory_compiled_inventory_gate=True, local_inventory_conservation_pass=True,
                     strict_initial_coordinate_match=True, all_mechanism_gates_evaluated=False,
                     full_device_first_law_verified=False, arms=[arm, dict(arm, arm='conservative')])
        execution = dict(execution_commit='exact', production_recovery_allowed=False,
                         checkpoint_saved=False, c200_state_imported=False,
                         cases=[{'arm': 'native'}, {'arm': 'conservative'}])
        return audit, execution

    def test_incomplete_mechanism_and_pressure_gates_reject_seed(self):
        audit, execution = self.records()
        result = classify(audit, execution)
        self.assertFalse(result['diagnostic_20cycle_seed_eligible'])
        self.assertFalse(result['independent_pressure_gate_evaluated'])

    def test_failed_flow_is_reported(self):
        audit, execution = self.records()
        audit['arms'][0]['selected_flow_gates'][0]['selected_flow_gate'] = False
        result = classify(audit, execution)
        self.assertFalse(result['selected_flow_gates_pass'])
        self.assertEqual(result['failed_selected_flow_gates'][0]['stage'], 2)

    def test_recovery_boundary_is_mandatory(self):
        audit, execution = self.records()
        execution['checkpoint_saved'] = True
        with self.assertRaises(ValueError):
            classify(audit, execution)


if __name__ == '__main__':
    unittest.main()
