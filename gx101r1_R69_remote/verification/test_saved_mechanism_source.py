import unittest
from pathlib import Path


class SavedMechanismSourceTests(unittest.TestCase):
    def test_same_production_validator_and_no_simulation_or_state_load(self):
        source = Path(__file__).with_name('Audit_HeatDriveECC_SavedMechanism.m').read_text()
        self.assertIn('Validate_HeatDriveECC_EighthRound_Physics(view)', source)
        self.assertIn('Extract_HeatDriveECC_PhysicalLogs(observation, options', source)
        self.assertIn('completion.observation_sha256, file_hash(source_file)', source)
        self.assertNotIn('output=sim(', source)
        self.assertNotIn('diagnostic_operating_point', source)
        self.assertIn("'production_recovery_allowed', false", source)

    def test_no_extrapolation_or_synthetic_clock_in_slice(self):
        source = Path(__file__).with_name('Slice_HeatDriveECC_SavedMechanismObservation.m').read_text()
        self.assertNotIn('interp1', source)
        self.assertIn('all(diff(t) > 0)', source)
        self.assertIn('all(abs(diff(t)-dt) <= tolerance)', source)
        self.assertIn('isequal(row.time_s(:), reference)', source)

    def test_every_physical_guard_names_a_tracked_file(self):
        import re
        import subprocess
        root = Path(__file__).parent.parent.parent
        source = Path(__file__).with_name('Run_HeatDriveECC_ResumedDiagnosticSegment.m').read_text()
        scope = source.split('physical={', 1)[1].split('};', 1)[0]
        paths = re.findall(r"'([^']+)'", scope)
        self.assertEqual(len(paths), 10)
        for path in paths:
            subprocess.run(['git', 'ls-files', '--error-unmatch', '--',
                            'gx101r1_R69_remote/' + path], cwd=root,
                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, check=True)
        self.assertIn('ls-files --error-unmatch', source)


if __name__ == '__main__':
    unittest.main()
