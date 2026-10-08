import copy
import json
from pathlib import Path
import tempfile
import unittest

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from HeatDriveECC_DiagnosticAnalysisScope import diagnostic_arms


class DiagnosticResumeScopeTests(unittest.TestCase):
    def fixture(self,root):
        source=root/'source/native';verified=root/'proof/native'
        source.mkdir(parents=True);verified.mkdir(parents=True)
        for path in (source/'diagnostic_complete_operating_point.mat',source/'diagnostic_state_observation.mat',
                     verified/'rebuilt_cycle_comparison.mat'):
            path.write_bytes(b'fixture bytes, not a physical state')
        op=sha256(source/'diagnostic_complete_operating_point.mat')
        history=sha256(source/'diagnostic_state_observation.mat')
        proof=dict(rebuilt_complete_cycle_pass=True,production_recovery_allowed=False,
                   source_operating_point_sha256=op,source_history_sha256=history)
        receipt=verified/'rebuilt_cycle_restore.json';receipt.write_text(json.dumps(proof))
        contract=dict(schema='heatdrive_ecc_state_qualified_diagnostic_resume_v1',
                      source_root=str(source.parent),verification_root=str(verified.parent),snapshot_time_s=20,
                      full_cycle_state_restore_verified=True,diagnostic_trial_only=True,
                      failed_state_propagated=False,source_state_edited=False,partial_state_restore_used=False,
                      production_recovery_allowed=False,operating_point_sha256=op,history_sha256=history,
                      restore_receipt_sha256=sha256(receipt),comparison_sha256=sha256(verified/'rebuilt_cycle_comparison.mat'))
        return dict(diagnostic_state_options=dict(mode='diagnostic_resume'),
                    requested_arm_collection_pass=True,collection_pass=False,requested_arms=['native'],
                    start_time_s=20,stop_time_s=220,segment_cycle_count=20,cycle_count=22,checkpoint_saved=True,
                    c200_state_imported=False,production_recovery_allowed=False,error_message='',
                    diagnostic_resume_contract=contract)

    def test_explicit_single_arm_trial_does_not_fake_paired_collection(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);execution=self.fixture(root)
            self.assertEqual(diagnostic_arms(root,execution),('native',))
            self.assertFalse(execution['collection_pass'])

    def test_changed_source_or_comparison_rejected(self):
        for file in ('source/native/diagnostic_complete_operating_point.mat','proof/native/rebuilt_cycle_comparison.mat'):
            with tempfile.TemporaryDirectory() as temporary:
                root=Path(temporary);execution=self.fixture(root)
                (root/file).write_bytes(b'tampered')
                with self.assertRaises(ValueError): diagnostic_arms(root,execution)

    def test_scope_cannot_promote_state_test_to_production_or_rewrite_time(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);execution=self.fixture(root)
            for key,value in (('production_recovery_allowed',True),('start_time_s',0),('collection_pass',True),
                              ('requested_arm_collection_pass',False),('c200_state_imported',True),('error_message','failure')):
                bad=copy.deepcopy(execution);bad[key]=value
                with self.assertRaises(ValueError): diagnostic_arms(root,bad)

    def test_unmodified_cold_analysis_keeps_two_arms(self):
        self.assertEqual(diagnostic_arms(Path('.'),{}),('native','conservative'))
