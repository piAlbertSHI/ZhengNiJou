import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parent


@unittest.skipUnless(shutil.which('pwsh'),'PowerShell 7 is required')
class CompletionTests(unittest.TestCase):
    def run_case(self,names,tamper=False):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); cases=[]
            for name in names:
                folder=root/name; folder.mkdir()
                raw=b'observations-fixture-only'
                (folder/'observations.mat').write_bytes(raw)
                digest=hashlib.sha256(raw).hexdigest().upper()
                completion=dict(arm=name,observation_sha256=digest)
                (folder/'arm_completion.json').write_text(json.dumps(completion),encoding='utf-8')
                (folder/'distributed_pressure_ff_contract.json').write_text(json.dumps(dict(
                    simulation_run=True,sources=[{}]*21,legacy_reference_multiplier_used=False)),encoding='utf-8')
                cases.append(dict(arm=name,observation_sha256=('BAD' if tamper else digest)))
            execution=dict(cases=cases,requested_arm_collection_pass=True,
                collection_pass=len(names)==2,c200_state_imported=False,checkpoint_saved=False,
                production_recovery_allowed=False)
            (root/'execution.json').write_text(json.dumps(execution),encoding='utf-8')
            quote=lambda p:str(p).replace("'","''")
            arms=','.join("'"+n+"'" for n in names)
            command=(f"Set-StrictMode -Version Latest; . '{quote(ROOT/'Test_HeatDriveECC_DiagnosticCompletion.ps1')}'; "
                     f"$r=Get-Content -LiteralPath '{quote(root/'execution.json')}' -Raw | ConvertFrom-Json; "
                     f"Test-HeatDriveECCDiagnosticCompletion -Execution $r -OutputRoot '{quote(root)}' "
                     f"-RequestedArms @({arms}) -DistributedController $true | ConvertTo-Json")
            result=subprocess.run(['pwsh','-NoProfile','-Command',command],capture_output=True,
                                  text=True,encoding='utf-8',timeout=30)
            self.assertEqual(result.returncode,0,result.stderr)
            return json.loads(result.stdout)

    def test_single_arm_is_valid_subset_not_pair(self):
        result=self.run_case(['conservative'])
        self.assertTrue(result['requested_arm_collection_pass'])
        self.assertTrue(result['requested_controller_executed'])
        self.assertFalse(result['physical_collection_pass'])
        self.assertFalse(result['production_recovery_allowed'])

    def test_two_arms_pass_collection_not_recovery(self):
        result=self.run_case(['native','conservative'])
        self.assertTrue(result['requested_arm_collection_pass'])
        self.assertTrue(result['physical_collection_pass'])
        self.assertFalse(result['production_recovery_allowed'])

    def test_hash_mismatch_does_not_pass(self):
        result=self.run_case(['conservative'],tamper=True)
        self.assertFalse(result['requested_arm_collection_pass'])
