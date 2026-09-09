import unittest
from Audit_HeatDriveECC_HeldErrorControl import check_error_policy, POLICY, TOL


class HeldErrorControlTests(unittest.TestCase):
    def test_only_action_changes_and_tolerances_are_exact(self):
        before=dict(POLICY,MinStepSizeMsg='warning')
        check_error_policy(before,POLICY,TOL)
        self.assertEqual(before['MinStepSizeMsg'],'warning')

    def test_no_warning_continuation_or_increased_violation_allowance(self):
        for policy in (dict(POLICY,MinStepSizeMsg='warning'),
                       dict(POLICY,MaxConsecutiveMinStep='100'),dict(POLICY,MinStep='1e-9')):
            with self.assertRaises(ValueError):
                check_error_policy(dict(POLICY,MinStepSizeMsg='warning'),policy,TOL)

    def test_undeclared_tolerances_are_rejected(self):
        for tolerances in (dict(TOL,RelTol='1e-6'),dict(TOL,AbsTol='1e-8')):
            with self.assertRaises(ValueError):
                check_error_policy(dict(POLICY,MinStepSizeMsg='warning'),POLICY,tolerances)
