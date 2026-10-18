import json
from pathlib import Path
import tempfile
import unittest

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Close_HeatDriveECC_KernelComparisons import close


class KernelCloseoutTests(unittest.TestCase):
    def fixture(self, root):
        proof = root / 'offline.json'
        proof.write_text(json.dumps(dict(schema='heatdrive_ecc_stable_kernel_candidate_comparison_v1',
            all_captured_samples_bitwise_equal=True,all_original_L8_option_cases_bitwise_equal=True,
            error_message='',coupled_acceleration_qualified=False,
            candidate_source_sha256=sha256(Path(__file__).parent/'HeatDriveECC_StableKernelCandidate.m'))),encoding='utf-8')
        preflight = root / 'preflight'
        preflight.mkdir()
        (preflight/'preflight_tests.json').write_text(json.dumps(dict(positive_requests=2,
            negative_requests_rejected=9,operating_point_loaded=False)),encoding='utf-8')
        output = Path(__file__).parent.parent / 'outputs_storage_audit/__unused_kernel_closeout_test'
        self.assertFalse(output.exists())
        return proof, preflight, output

    def test_missing_actual_comparisons_cannot_be_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            proof, preflight, output = self.fixture(root)
            with self.assertRaisesRegex(ValueError, 'original nominal and row one'):
                close([],proof,preflight,root/'launcher',output)
            self.assertFalse(output.exists())

    def test_changed_candidate_source_rejected_before_copy(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            proof, preflight, output = self.fixture(root)
            record = json.loads(proof.read_text())
            record['candidate_source_sha256'] = '0' * 64
            proof.write_text(json.dumps(record),encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'Changed or failed offline'):
                close([],proof,preflight,root/'launcher',output)
            self.assertFalse(output.exists())


if __name__ == '__main__':
    unittest.main()
