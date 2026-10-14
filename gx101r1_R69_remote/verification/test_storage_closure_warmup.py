import copy
import unittest

from Audit_HeatDriveECC_StorageClosureWarmup import validate_resume_config


class StorageWarmupConfigTests(unittest.TestCase):
    def setUp(self):
        self.old = dict(output_root='source', duration_s=20, cycle_count=2, gain=-225,
            diagnostic_state_options=dict(mode='restore_preflight', command_horizon_cycles=200),
            diagnostic_inventory_options=dict(storage_closure='pressure_only_density', cold_followup_audit_path='c1'),
            diagnostic_se_reference_options=dict(mode='coherent_envelope', cold_followup_audit_path='reference'))
        self.new = copy.deepcopy(self.old)
        self.new.update(output_root='new', duration_s=200, cycle_count=20,
            diagnostic_state_options=dict(mode='diagnostic_resume', command_horizon_cycles=200,
                restore_source_root='source', restore_verification_root='proof',
                storage_state_audit_path='state', storage_complete_cycle_audit_path='cycle'))
        for key in ('diagnostic_inventory_options', 'diagnostic_se_reference_options'):
            self.new[key].update(rebuilt_state_audit_path='state', warmup_restore_audit_path='cycle')

    def test_unchanged_model_accepted_without_mutating_input(self):
        original = copy.deepcopy(self.new)
        self.assertEqual(validate_resume_config(self.old, self.new)['restore_source_root'], 'source')
        self.assertEqual(self.new, original)

    def test_changed_gain_rejected(self):
        self.new['gain'] = -226
        with self.assertRaises(ValueError):
            validate_resume_config(self.old, self.new)

    def test_changed_state_source_rejected(self):
        self.new['diagnostic_state_options']['restore_source_root'] = 'failed'
        with self.assertRaises(ValueError):
            validate_resume_config(self.old, self.new)

    def test_different_intervention_authority_rejected(self):
        self.new['diagnostic_inventory_options']['warmup_restore_audit_path'] = 'different'
        with self.assertRaises(ValueError):
            validate_resume_config(self.old, self.new)

    def test_geometry_change_rejected(self):
        self.new['volume_factor'] = .1
        with self.assertRaises(ValueError):
            validate_resume_config(self.old, self.new)

    def test_short_segment_rejected(self):
        self.new['duration_s'] = 10
        with self.assertRaises(ValueError):
            validate_resume_config(self.old, self.new)

    def latest_pair(self):
        old = copy.deepcopy(self.new)
        new = copy.deepcopy(old)
        new['output_root'] = 'next'
        new['diagnostic_state_options'].update(restore_source_root='new', restore_verification_root='latest_proof')
        return old, new

    def test_latest_segment_preserves_physics_and_ancestor_authorities(self):
        old, new = self.latest_pair()
        before = copy.deepcopy((old, new))
        self.assertEqual(validate_resume_config(old, new)['restore_source_root'], 'new')
        self.assertEqual((old, new), before)

    def test_latest_changed_gain_rejected(self):
        old, new = self.latest_pair()
        new['gain'] = -230
        with self.assertRaises(ValueError):
            validate_resume_config(old, new)

    def test_latest_changed_ancestor_rejected(self):
        old, new = self.latest_pair()
        old['diagnostic_inventory_options']['warmup_restore_audit_path'] = 'other'
        with self.assertRaises(ValueError):
            validate_resume_config(old, new)

    def test_ten_cycle_native_logging_does_not_change_physical_recipe(self):
        old, new = self.latest_pair()
        new['diagnostic_state_options']['native_inventory_window_cycles'] = 10
        self.assertEqual(validate_resume_config(old, new)['native_inventory_window_cycles'], 10)

    def test_arbitrary_native_window_rejected(self):
        old, new = self.latest_pair()
        new['diagnostic_state_options']['native_inventory_window_cycles'] = 9
        with self.assertRaises(ValueError):
            validate_resume_config(old, new)


if __name__ == '__main__':
    unittest.main()
