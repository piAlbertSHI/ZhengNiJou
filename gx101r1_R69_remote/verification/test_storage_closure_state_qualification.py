import copy
import unittest

from Audit_HeatDriveECC_StorageClosureStateQualification import compare_c2_configs, verify_restore_record


class StorageStateQualificationTests(unittest.TestCase):
    def configs(self):
        a = dict(output_root='old', duration_s=20, cycle_count=2,
                 diagnostic_state_options={'mode': 'restore_preflight', 'command_horizon_cycles': 200},
                 stage4_kp=-225, pressure_datum=.85)
        b = copy.deepcopy(a)
        b.update(output_root='new', diagnostic_inventory_options={
            'storage_closure': 'pressure_only_density', 'cold_followup_audit_path': 'qualified.json'})
        return a, b

    def restore(self):
        return dict(same_model_restore_preflight_pass=True, checksum_policy='error/error',
                    source_state_edited=False, partial_state_restore_used=False,
                    complete_cycle_resume_verified=False, snapshot_time_s=20, comparison_stop_s=20.001,
                    state_comparisons=[dict(values_exact=True, clock_pass=True) for _ in range(74)],
                    signal_comparisons=[dict(values_exact=True) for _ in range(201)])

    def test_matched_configuration(self):
        compare_c2_configs(*self.configs())

    def test_undeclared_control_or_datum_change_rejected(self):
        for field, value in (('stage4_kp', -230), ('pressure_datum', .75), ('cycle_count', 20)):
            a, b = self.configs()
            b[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                compare_c2_configs(a, b)

    def test_combined_volume_intervention_rejected(self):
        a, b = self.configs()
        b['diagnostic_inventory_options']['volume_factor'] = .1
        with self.assertRaises(ValueError):
            compare_c2_configs(a, b)

    def test_exact_same_model_restore(self):
        verify_restore_record(self.restore())

    def test_same_model_proof_cannot_claim_complete_cycle(self):
        r = self.restore()
        r['complete_cycle_resume_verified'] = True
        with self.assertRaises(ValueError):
            verify_restore_record(r)

    def test_missing_state_or_changed_signal_rejected(self):
        for target in ('state', 'signal'):
            r = self.restore()
            if target == 'state':
                r['state_comparisons'].pop()
            else:
                r['signal_comparisons'][0]['values_exact'] = False
            with self.subTest(target=target), self.assertRaises(ValueError):
                verify_restore_record(r)

    def test_checksum_or_partial_restore_rejected(self):
        for field, value in (('checksum_policy', 'warning/warning'), ('partial_state_restore_used', True),
                             ('source_state_edited', True), ('comparison_stop_s', 30)):
            r = self.restore()
            r[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                verify_restore_record(r)


if __name__ == '__main__':
    unittest.main()
