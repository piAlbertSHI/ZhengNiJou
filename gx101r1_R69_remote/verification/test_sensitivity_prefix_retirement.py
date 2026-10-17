from pathlib import Path
import unittest


class SensitivityPrefixRetirementTests(unittest.TestCase):
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
