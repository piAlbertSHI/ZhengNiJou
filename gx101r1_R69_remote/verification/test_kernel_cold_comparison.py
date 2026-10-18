from pathlib import Path
import unittest


class KernelColdComparisonScopeTests(unittest.TestCase):
    def source(self, name):
        return (Path(__file__).parent / name).read_text(encoding='utf-8')

    def test_comparison_states_rejected_before_op_or_manifest_load(self):
        source = self.source('Load_HeatDriveECC_GatedObservationPacket.m')
        self.assertLess(source.index('COMPARISON_ONLY_DO_NOT_RESUME.json'), source.index('manifest_file='))
        compare = self.source('Verify_HeatDriveECC_KernelColdComparison.m')
        self.assertLess(compare.index('COMPARISON_ONLY_DO_NOT_RESUME.json'), compare.index('Compare_HeatDriveECC_ObservationPackets('))
        self.assertIn("'twenty_cycle_seed_qualified',false", compare)

    def test_backend_is_explicit_and_original_wrapper_unchanged(self):
        run = self.source('Run_HeatDriveECC_KernelColdComparison.m')
        self.assertIn('HeatDriveECC_ConstitutiveStateVectorStep21_KernelCandidate', run)
        self.assertIn("'probe_only',true", run)
        self.assertNotIn('setInitialState(', run)
        root = Path(__file__).parent.parent
        self.assertNotIn('KernelCandidate', (root / 'HeatDriveECC_ConstitutiveStateVectorStep21_StableDiagnostic.m').read_text())

    def test_no_invented_steady_claim_or_old_op_import(self):
        run = self.source('Verify_HeatDriveECC_KernelColdComparison.m')
        self.assertIn("'source_OP_imported',false", run)
        self.assertIn("'complete_state_restore_equivalence_evaluated',false", run)
        self.assertIn("'runtime_sensitivity_cold',''", run)
        self.assertNotIn('setInitialState(', run)


if __name__ == '__main__':
    unittest.main()
