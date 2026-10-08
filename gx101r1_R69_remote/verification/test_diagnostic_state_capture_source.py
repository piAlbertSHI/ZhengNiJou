from pathlib import Path
import unittest


class DiagnosticStateCaptureSourceTests(unittest.TestCase):
    def source(self, name):
        return (Path(__file__).parent/name).read_text()

    def test_capture_preserves_full_op_not_dataset_reconstruction(self):
        source = self.source('Save_HeatDriveECC_DiagnosticStateCapture.m')
        self.assertIn('diagnostic_operating_point=output.diagnostic_final_op', source)
        self.assertNotIn('.loggedStates=', source)
        self.assertIn('assert(isempty(output.ErrorMessage)', source)
        self.assertIn("'current_model_roundtrip_verified',false", source)
        self.assertIn("'diagnostic_continuation_allowed',false", source)

    def test_history_bounded_without_decimation_or_relaxed_restore(self):
        source = self.source('Configure_HeatDriveECC_DiagnosticStateCapture.m')
        for token in ("'SaveOperatingPoint','on'", "'LimitDataPoints','on'",
                      "'Decimation','1'", "'OperatingPointContentsChecksumMismatchMsg','error'",
                      "'OperatingPointInterfaceChecksumMismatchMsg','error'"):
            self.assertIn(token, source)

    def test_fixture_compares_actual_continuation_with_continuous_reference(self):
        source = self.source('Verify_HeatDriveECC_DiagnosticStateCapture.m')
        self.assertIn('setInitialState(saved.diagnostic_operating_point)', source)
        self.assertIn('isequaln(a.values,b.values(selected,:))', source)
        self.assertIn("'current_coupled_model_restore_verified',false", source)
        self.assertIn("'Stage2Memory'", source)
        self.assertIn("'Stage4Memory'", source)

    def test_coupled_preflight_does_not_fake_a_complete_package(self):
        source = self.source('Run_HeatDriveECC_DiagnosticStatePreflight.m')
        self.assertIn('~record.collection_pass', source)
        self.assertIn('~record.requested_arm_collection_pass', source)
        self.assertIn('command_horizon_cycles\',200', source)
        self.assertIn('Build_HeatDriveECC_IndependentColdBranchOverrides(config)', source)

    def test_restore_uses_intact_op_and_keeps_exact_comparison(self):
        source = self.source('Verify_HeatDriveECC_CoupledStateRestore.m')
        self.assertIn('setInitialState(saved.diagnostic_operating_point)', source)
        self.assertNotIn('.loggedStates=', source)
        self.assertIn('isequaln(a.values,b.values(selected,:))', source)
        self.assertIn("'diagnostic_continuation_allowed',false", source)
        self.assertIn("'complete_cycle_resume_verified',false", source)
