import copy
import json
from pathlib import Path
import tempfile
import unittest

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from HeatDriveECC_DiagnosticAnalysisScope import diagnostic_arms
from Qualify_HeatDriveECC_DiagnosticEndpoint import SCHEMA, LOCAL_FILES, AUDIT_ROLES, validate_qualification


class LatestEndpointTests(unittest.TestCase):
    def fixture(self, root):
        source=root/'source';proof=root/'proof';source.mkdir();proof.mkdir()
        files=[]
        for role,relative in {**LOCAL_FILES,**{role:role+'.json' for role in AUDIT_ROLES}}.items():
            path=source/relative;path.parent.mkdir(parents=True,exist_ok=True)
            path.write_bytes(b'contract fixture, not numerical physics evidence')
            files.append(dict(role=role,path=str(path),sha256=sha256(path)))
        receipt=dict(schema=SCHEMA,source_root=str(source),snapshot_time_s=220,total_cycles=22,
            command_horizon_cycles=200,qualification_pass=True,warmup_continuation_allowed=True,
            full_mechanism_count=73,local_inventory_pass=True,complete_logged_state_coverage=True,
            ancestor_complete_cycle_restore_verified=True,ancestor_complete_cycle_proof={'fixture':True},
            production_recovery_allowed=False,steady_outer_solve_allowed=False,table4_reproduction_claim=False,
            source_state_edited=False,partial_state_restore_used=False,
            latest_endpoint_complete_cycle_reference_compared=False,files=files)
        path=proof/'diagnostic_resume_qualification.json';path.write_text(json.dumps(receipt))
        rows={row['role']:row for row in files}
        contract=dict(schema='heatdrive_ecc_latest_qualified_diagnostic_resume_v2',
            source_root=str(source),verification_root=str(proof),snapshot_time_s=220,
            operating_point_sha256=rows['operating_point']['sha256'],history_sha256=rows['history']['sha256'],
            qualification_sha256=sha256(path),ancestor_complete_cycle_restore_verified=True,
            ancestor_complete_cycle_proof=receipt['ancestor_complete_cycle_proof'],
            latest_endpoint_complete_cycle_reference_compared=False,source_physical_gates_evaluated=True,
            failed_state_propagated=False,source_state_edited=False,partial_state_restore_used=False,
            production_recovery_allowed=False,diagnostic_trial_only=True)
        execution=dict(diagnostic_state_options=dict(mode='diagnostic_resume',command_horizon_cycles=200),
            requested_arm_collection_pass=True,collection_pass=False,requested_arms=['native'],
            start_time_s=220,stop_time_s=420,segment_cycle_count=20,cycle_count=42,checkpoint_saved=True,
            c200_state_imported=False,production_recovery_allowed=False,error_message='',
            diagnostic_resume_contract=contract)
        return receipt,execution,source,path

    def test_latest_checkpoint_continues_absolute_clock_without_steady_claim(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);receipt,execution,source,path=self.fixture(root)
            self.assertEqual(len(validate_qualification(receipt,source)),10)
            self.assertEqual(diagnostic_arms(root,execution),('native',))
            self.assertFalse(receipt['steady_outer_solve_allowed'])

    def test_promotions_and_missing_or_duplicate_evidence_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            receipt,execution,source,path=self.fixture(Path(tmp))
            for key,value in (('production_recovery_allowed',True),('steady_outer_solve_allowed',True),
                              ('source_state_edited',True),('local_inventory_pass',False),
                              ('full_mechanism_count',72),('snapshot_time_s',20),
                              ('latest_endpoint_complete_cycle_reference_compared',True)):
                bad=copy.deepcopy(receipt);bad[key]=value
                with self.assertRaises(ValueError):validate_qualification(bad,source)
            for rows in (receipt['files'][:-1],receipt['files'][:-1]+receipt['files'][:1]):
                bad=copy.deepcopy(receipt);bad['files']=rows
                with self.assertRaises(ValueError):validate_qualification(bad,source)

    def test_every_bound_file_tamper_rejected(self):
        for role in set(LOCAL_FILES)|AUDIT_ROLES:
            with tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);receipt,execution,source,path=self.fixture(root)
                row=next(row for row in receipt['files'] if row['role']==role)
                Path(row['path']).write_bytes(b'changed')
                with self.assertRaises(ValueError):diagnostic_arms(root,execution)

    def test_rejected_or_incomplete_markers_and_clock_changes_rejected(self):
        for marker in ('INCOMPLETE_DO_NOT_RESUME.json','REJECTED_DO_NOT_RESUME.json','REJECTED_DO_NOT_RESUME.txt'):
            with tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);receipt,execution,source,path=self.fixture(root)
                (source/marker).write_text('rejected')
                with self.assertRaises(ValueError):diagnostic_arms(root,execution)
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);receipt,execution,source,path=self.fixture(root)
            for key,value in (('start_time_s',20),('stop_time_s',220),('cycle_count',22),
                              ('production_recovery_allowed',True),('error_message','failed')):
                bad=copy.deepcopy(execution);bad[key]=value
                with self.assertRaises(ValueError):diagnostic_arms(root,bad)

    def test_matlab_loader_does_not_edit_or_reconstruct_vendor_state(self):
        text=Path(__file__).with_name('Load_HeatDriveECC_LatestDiagnosticEndpoint.m').read_text(encoding='utf-8')
        self.assertIn('op=saved.diagnostic_operating_point;',text)
        self.assertIn("'latest_endpoint_complete_cycle_reference_compared',false",text)
        self.assertIn('execution.stop_time_s-execution.start_time_s==200',text)
        self.assertNotIn('snapshotTime=',text)
        self.assertNotIn('copy_state',text)

    def test_saved_mechanism_uses_actual_final_pair_and_original_predicates(self):
        text=Path(__file__).with_name('Audit_HeatDriveECC_SavedMechanism.m').read_text(encoding='utf-8')
        self.assertIn('execution.stop_time_s-20, execution.stop_time_s',text)
        self.assertIn('Validate_HeatDriveECC_EighthRound_Physics(view)',text)
        self.assertIn('~contract.failed_state_propagated',text)
        self.assertIn('~contract.partial_state_restore_used',text)
        self.assertIn('contract.qualification_sha256',text)
