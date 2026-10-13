import copy
import unittest

from Audit_HeatDriveECC_RebootRecoveryCloseout import require_exact_cycle


class ExactRecoveryTests(unittest.TestCase):
    def setUp(self):
        row = dict(samples=10001, clock_pass=True, values_exact=True, max_absolute_difference=0)
        self.proof = dict(state_comparisons=[dict(row) for _ in range(74)],
                          signal_comparisons=[dict(row) for _ in range(201)],
                          rebuilt_complete_cycle_pass=True, strict_restore_completed=True,
                          continuous_reference_pass=True, checksum_policy='error/error',
                          source_state_edited=False, partial_state_restore_used=False,
                          error_message='', start_time_s=20, stop_time_s=30,
                          bounded_restored_cycle_mechanism_pass=True,
                          bounded_restored_cycle_mechanism_checks={str(k): True for k in range(73)})

    def test_complete_pass(self):
        require_exact_cycle(self.proof)

    def test_reject_incomplete_or_relaxed_restore(self):
        for field, value in (('checksum_policy', 'warning/warning'), ('source_state_edited', True),
                             ('partial_state_restore_used', True), ('strict_restore_completed', False),
                             ('continuous_reference_pass', False), ('stop_time_s', 20.001),
                             ('bounded_restored_cycle_mechanism_pass', False)):
            with self.subTest(field=field):
                proof = copy.deepcopy(self.proof)
                proof[field] = value
                with self.assertRaises(ValueError):
                    require_exact_cycle(proof)

    def test_reject_missing_state(self):
        self.proof['state_comparisons'].pop()
        with self.assertRaises(ValueError):
            require_exact_cycle(self.proof)

    def test_reject_short_signal_or_difference(self):
        for field, value in (('samples', 2), ('clock_pass', False), ('max_absolute_difference', 1e-16)):
            with self.subTest(field=field):
                proof = copy.deepcopy(self.proof)
                proof['signal_comparisons'][0][field] = value
                with self.assertRaises(ValueError):
                    require_exact_cycle(proof)

    def test_reject_missing_mechanism_check(self):
        self.proof['bounded_restored_cycle_mechanism_checks'].pop('0')
        with self.assertRaises(ValueError):
            require_exact_cycle(self.proof)


if __name__ == '__main__':
    unittest.main()
