import json
from pathlib import Path
import tempfile
import unittest

from Analyze_HeatDriveECC_WarmupOutcome import diagnostic_capture_hashes
from Audit_HeatDriveECC_SegmentedEvidence import sha256


class DiagnosticCaptureScopeTests(unittest.TestCase):
    def fixture(self, root):
        execution = dict(checkpoint_saved=True, stop_time_s=200, production_recovery_allowed=False,
                         diagnostic_state_options=dict(mode='capture'))
        for arm in ('native', 'conservative'):
            folder = root/arm
            folder.mkdir()
            op = folder/'diagnostic_complete_operating_point.mat'
            history = folder/'diagnostic_state_observation.mat'
            op.write_bytes(b'unit test candidate, not an actual OP')
            history.write_bytes(b'unit test bounded history')
            receipt = dict(schema='heatdrive_ecc_diagnostic_state_capture_v1', snapshot_time_s=200,
                           production_recovery_allowed=False, diagnostic_continuation_allowed=False,
                           source_op_edited=False, state_reconstruction_used=False,
                           operating_point_sha256=sha256(op), history_sha256=sha256(history))
            (folder/'diagnostic_state_capture.json').write_text(json.dumps(receipt))
        return execution

    def test_legacy_no_checkpoint_unchanged(self):
        self.assertEqual(diagnostic_capture_hashes(Path('.'), dict(checkpoint_saved=False)), {})

    def test_candidates_hash_bound_without_promoting_authority(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            hashes = diagnostic_capture_hashes(root, self.fixture(root))
            self.assertEqual(len(hashes), 6)

    def test_changed_candidate_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            execution = self.fixture(root)
            (root/'native/diagnostic_complete_operating_point.mat').write_bytes(b'changed')
            with self.assertRaises(ValueError):
                diagnostic_capture_hashes(root, execution)

    def test_production_or_preflight_not_a_complete_warmup(self):
        for execution in (
                dict(checkpoint_saved=True, production_recovery_allowed=True,
                     diagnostic_state_options=dict(mode='capture')),
                dict(checkpoint_saved=True, production_recovery_allowed=False,
                     diagnostic_state_options=dict(mode='restore_preflight'))):
            with self.assertRaises(ValueError):
                diagnostic_capture_hashes(Path('.'), execution)
