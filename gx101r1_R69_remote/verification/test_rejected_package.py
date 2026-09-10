import unittest
from pathlib import Path
from Audit_HeatDriveECC_RejectedDiagnosticPackage import REQUIRED_FALSE


class RejectedPackageTests(unittest.TestCase):
    def test_required_fields(self):
        self.assertEqual(len(REQUIRED_FALSE),5)
        self.assertIn('production_recovery_allowed',REQUIRED_FALSE)

    def test_repo_exists(self):
        self.assertTrue(Path(__file__).resolve().parents[1].is_dir())
