import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parent


class GateReasonablenessSourceTests(unittest.TestCase):
    def test_monotonic_startup_is_not_a_physical_acceptance_requirement(self):
        source=(ROOT.parent/'Validate_HeatDriveECC_EighthRound_Physics.m').read_text(encoding='utf-8')
        self.assertNotIn('checks.cold_start_phase_swing_progression',source)
        self.assertIn('diagnostics.cold_start_phase_swing_progression =',source)
        for text in ('checks.SMA_phase_swing =','checks.SE_phase_swing =',
                     'checks.SMA_solid_energy_balance ='):
            self.assertIn(text,source)

    def test_native_timing_retains_exact_api_and_units(self):
        source=(ROOT/'Read_HeatDriveECC_NativeSeries.m').read_text(encoding='utf-8')
        for text in ('double(time(series))','double(values(series))','unit=series.unit',
                     'series_access_s','points_access_s','values_access_s','time_access_s'):
            self.assertIn(text,source)
        self.assertNotIn('interp1',source)
