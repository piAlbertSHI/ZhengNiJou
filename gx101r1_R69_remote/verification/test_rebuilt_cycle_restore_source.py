from pathlib import Path
import unittest


class RebuiltCycleRestoreSourceTests(unittest.TestCase):
    def source(self, name):
        return (Path(__file__).parent / name).read_text()

    def test_rebuild_does_not_resimulate_initial_twenty_seconds_to_make_a_source(self):
        source = self.source('Run_HeatDriveECC_ColdChamberDiagnostic.m')
        branch = source.split('if rebuilt_preflight\n')[1].split('output=sim(input);')[0]
        self.assertIn('Verify_HeatDriveECC_RebuiltCycleRestore', branch)
        self.assertIn('continue', branch)
        self.assertNotIn('Save_HeatDriveECC_DiagnosticStateCapture', branch)

    def test_intact_source_and_full_window_not_partial_state_or_tolerance_widening(self):
        source = self.source('Verify_HeatDriveECC_RebuiltCycleRestore.m')
        self.assertIn('setInitialState(saved.diagnostic_operating_point)', source)
        self.assertNotIn('.loggedStates=', source)
        self.assertIn('capture.history_sha256', source)
        self.assertIn('10001 physical samples', source)
        self.assertIn('isequaln(a.values,b.values)', source)
        self.assertIn("'production_recovery_allowed',false", source)
        self.assertIn("'all_mechanism_gates_evaluated',false", source)
        self.assertIn("'diagnostic_continuation_allowed',false", source)

    def test_rebuild_uses_original_two_cycle_configuration_and_fixed_drive(self):
        source = self.source('Run_HeatDriveECC_RebuiltCyclePreflight.m')
        self.assertIn("source_root,'.state_preflight_config.json'", source)
        self.assertIn('prior.execution_commit', source)
        self.assertIn('git -C', source)
        self.assertIn("'command_horizon_cycles',200", source)
        self.assertIn('~record.collection_pass', source)
