from pathlib import Path
import unittest


class SensitivityPrefixRetirementTests(unittest.TestCase):
    def test_obsolete_arm_retirement_is_exact_and_not_a_duplicate_claim(self):
        source = (Path(__file__).parent / 'Retire_HeatDriveECC_ObsoleteStage4Arms.ps1').read_text(encoding='utf-8')
        for text in ('conservative\\observations.mat', 'arrays_claimed_identical=$false',
                     'full_historical_dual_arm_raw_reverification_available=$false',
                     'native_raw_retained=$true', 'checkpoint_saved=false',
                     'Check-Records $plan.protected_files', 'Separately reviewed exact plan SHA required',
                     'Reparse points forbidden', 'Target outside immutable allowlist'):
            self.assertIn(text, source)
        self.assertNotIn('Remove-Item -Recurse', source)
        self.assertEqual(source.count('Remove-Item -LiteralPath'), 1)

    def test_case_two_requires_its_own_sealed_sources_and_no_ambiguous_selector(self):
        source = (Path(__file__).parent / 'Retire_HeatDriveECC_ColdControlPrefix.ps1').read_text(encoding='utf-8')
        for text in ('[switch]$L8CaseTwo', '$L8CaseOne -and $L8CaseTwo', '$cold.case_index -ne 2',
                     '$latest.case_index -ne 2', '$decision.case_index -ne 2',
                     'BDE1CA5CF871255C1DCB86FA2E24EA022C2A31764C2C380375FD439D24D6FB01',
                     'AF40ABDE7B8FA1FFF529859164290C555D5195386E2F5269CF74DA8FF0EE00E8'):
            self.assertIn(text, source)

    def test_case_one_requires_exact_sealed_sources_and_case(self):
        source = (Path(__file__).parent / 'Retire_HeatDriveECC_ColdControlPrefix.ps1').read_text(encoding='utf-8')
        for text in ('[switch]$L8CaseOne', '$cold.case_index -ne 1', '$latest.case_index -ne 1',
                     '$decision.case_index -ne 1', 'finite_precision_case_response_qualified',
                     'F4F0D244DC5192A450CAABE253C104CE38686C7477FD41A2651EE497E4E35532',
                     '0BC0D026D675C492371FFE084D2F7C4B6D90F3C56EAD06F70AD082BB3F4398E1'):
            self.assertIn(text, source)

    def test_only_exact_eight_old_arrays_are_deleted(self):
        source = (Path(__file__).parent / 'Retire_HeatDriveECC_ColdControlPrefix.ps1').read_text(encoding='utf-8')
        self.assertIn('foreach($cycle in 4,6,8,10)', source)
        self.assertIn("'native\\observations.mat','observed_states.mat'", source)
        self.assertIn('Check-Records $plan.protected_files', source)
        self.assertIn('Exact separately reviewed plan SHA required', source)
        self.assertIn('Remove-Item -LiteralPath $row.path -ErrorAction Stop', source)
        self.assertNotIn('Remove-Item -Recurse', source)


if __name__ == '__main__':
    unittest.main()
