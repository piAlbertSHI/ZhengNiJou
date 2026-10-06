import unittest
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
