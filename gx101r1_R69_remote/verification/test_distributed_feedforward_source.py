import unittest
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent


class DistributedFeedforwardSourceTests(unittest.TestCase):
    def test_probe_uses_native_fluid_not_solid_or_future_replay(self):
        source = (ROOT/'Configure_HeatDriveECC_DistributedPressureFeedforward.m').read_text(encoding='utf-8')
        self.assertIn("table('T_I').Unit = 'K'", source)
        self.assertIn('simscape.probe.setBoundBlock(probe, pipe)', source)
        self.assertIn("'simulink/Discrete/Unit Delay'", source)
        self.assertNotIn('load(', source)
        self.assertNotIn('save_system', source)
        self.assertNotIn('SE_Tx21_internal', source)

    def test_reference_multiplier_is_removed_not_retuned(self):
        source = (ROOT/'Configure_HeatDriveECC_DistributedPressureFeedforward.m').read_text(encoding='utf-8')
        self.assertIn("get_param(settings, 'nu_TLU_2')", source)
        self.assertIn('32 * lengths / (area * diameter^2) / 1e6', source)
        self.assertNotIn('se_bed_dp_MPa', source)
        self.assertNotIn('se_stage4_pressure_pi_kp', source)

    def test_feature_is_opt_in_only_on_cold_path(self):
        launcher = (ROOT/'Start_HeatDriveECC_IndependentColdDiagnostic.ps1').read_text(encoding='utf-8')
        self.assertIn('[bool]$DistributedPressureFeedforwardDiagnostic = $false', launcher)
        main_driver = (ROOT.parent/'Run_HeatDriveECC_EighthRound_Simulink_Cycles.m').read_text(encoding='utf-8')
        self.assertNotIn('Configure_HeatDriveECC_DistributedPressureFeedforward', main_driver)

    @unittest.skipUnless(shutil.which('pwsh'), 'PowerShell 7 is required')
    def test_executed_launcher_serializes_both_controller_modes(self):
        # Exercise the real parameter-to-JSON path without launching MATLAB.
        outputs = ROOT.parent/'outputs'
        outputs.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='config_test_', dir=outputs) as temp:
            fixture = Path(temp)
            source = fixture/'source'
            (source/'native').mkdir(parents=True)
            (source/'native/observations.mat').write_bytes(b'configuration-test-only')
            (source/'cold_chamber_execution.json').write_text(json.dumps({
                'collection_pass': True, 'stop_time_s': 10,
                'conservative_buffers': True, 'buffer_mass_formulation': 'zero_based_offset',
                'initial_flux_compensation': True, 'production_recovery_allowed': False,
            }), encoding='utf-8')
            for flag in (True, False):
                with self.subTest(flag=flag):
                    destination = fixture/str(flag)
                    quote = lambda p: str(p).replace("'", "''")
                    command = (f"& '{quote(ROOT/'Start_HeatDriveECC_IndependentColdDiagnostic.ps1')}' "
                               f"-OutputRoot '{quote(destination)}' "
                               f"-InitialObservationRoot '{quote(source)}' -PrepareOnly "
                               f"-DistributedPressureFeedforwardDiagnostic ${str(flag).lower()}")
                    result = subprocess.run(['pwsh', '-NoProfile', '-Command', command],
                                            capture_output=True, text=True, encoding='utf-8', timeout=30)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    config = json.loads(Path(str(destination)+'.launcher_config.json').read_text(encoding='utf-8-sig'))
                    self.assertIs(config['distributed_pressure_feedforward_diagnostic'], flag)
                    receipt = json.loads(result.stdout)
                    self.assertEqual(receipt['lifecycle_state'], 'prepared_not_executed')
                    self.assertFalse(receipt['simulation_run'])
                    self.assertFalse(destination.exists())

    def test_runtime_requested_wiring_is_fail_closed(self):
        runner = (ROOT/'Run_HeatDriveECC_ColdChamberDiagnostic.m').read_text(encoding='utf-8')
        self.assertIn('HeatDriveECC:LostControllerOverride', runner)
        self.assertIn('HeatDriveECC:MissingControllerWiring', runner)
        launcher = (ROOT/'Start_HeatDriveECC_IndependentColdDiagnostic.ps1').read_text(encoding='utf-8')
        self.assertIn('requested_controller_executed = $requestedControllerExecuted', launcher)
        self.assertIn('$exitCode = 9007', launcher)

    def test_scoped_arm_never_claims_pair_or_imports_missing_current_native(self):
        runner = (ROOT/'Run_HeatDriveECC_ColdChamberDiagnostic.m').read_text(encoding='utf-8')
        self.assertIn('record.collection_pass=numel(record.cases)==2;', runner)
        self.assertIn("strcmp(name,'conservative') && strcmp(diagnostic_arm,'both')", runner)
        self.assertIn('Scoped arms require an explicit endpoint or state experiment.', runner)
        self.assertIn("diagnostic_resume && cycle_count==20 && strcmp(diagnostic_arm,'native')",runner)

    @unittest.skipUnless(shutil.which('pwsh'), 'PowerShell 7 is required')
    def test_twenty_cycle_distributed_run_rejects_missing_audit_before_matlab(self):
        outputs=ROOT.parent/'outputs'; outputs.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='gate_test_',dir=outputs) as temp:
            root=Path(temp); source=root/'source'; (source/'native').mkdir(parents=True)
            (source/'native/observations.mat').write_bytes(b'configuration-test-only')
            (source/'cold_chamber_execution.json').write_text(json.dumps(dict(
                collection_pass=True,stop_time_s=10,conservative_buffers=True,
                buffer_mass_formulation='zero_based_offset',initial_flux_compensation=True,
                production_recovery_allowed=False)),encoding='utf-8')
            quote=lambda p:str(p).replace("'","''")
            destination=root/'blocked_config'
            command=(f"& '{quote(ROOT/'Start_HeatDriveECC_IndependentColdDiagnostic.ps1')}' "
                     f"-OutputRoot '{quote(destination)}' -InitialObservationRoot '{quote(source)}' "
                     '-PrepareOnly -DiagnosticCycleCount 20 -DistributedPressureFeedforwardDiagnostic $true')
            result=subprocess.run(['pwsh','-NoProfile','-Command',command],capture_output=True,
                                  text=True,encoding='utf-8',timeout=30)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('requires a completed cold-arm audit',result.stderr)
            self.assertFalse(destination.exists())
