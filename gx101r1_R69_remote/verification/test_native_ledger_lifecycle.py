import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent


class NativeLedgerLifecycleTests(unittest.TestCase):
    def test_cold_collects_native_before_second_simulation(self):
        text = (ROOT / 'Run_HeatDriveECC_ColdChamberDiagnostic.m').read_text()
        self.assertNotIn('Snapshot_HeatDriveECC_NativeLog(', text)
        export = text.index('Audit_HeatDriveECC_NativeLedgerPersistence(')
        restored = text.index('restored=Verify_HeatDriveECC_CoupledStateRestore(', export)
        self.assertLess(export, restored)

    def test_full_cycle_observes_physics_before_continuous_reference(self):
        text = (ROOT / 'Verify_HeatDriveECC_RebuiltCycleRestore.m').read_text()
        self.assertLess(text.index('physical=Extract_HeatDriveECC_PhysicalLogs('),
                        text.index('reference=sim('))
        self.assertIn('if qualify_mechanism && record.rebuilt_complete_cycle_pass', text)
        self.assertNotIn('Snapshot_HeatDriveECC_NativeLog(', text)

    def test_exact_all_series_roundtrip_is_not_a_scientific_pass(self):
        text = (ROOT / 'Audit_HeatDriveECC_NativeLedgerPersistence.m').read_text()
        self.assertIn('isequaln(persisted.native,native)', text)
        self.assertIn('isequaln(persisted.source_traces,source_traces)', text)
        self.assertIn("'scientific_ledger_pass_claimed',false", text)


if __name__ == '__main__':
    unittest.main()
