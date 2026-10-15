from pathlib import Path
import unittest

import numpy as np

from Analyze_HeatDriveECC_RecordedTenCycles import join_measured, native_statistics


class RecordedTenCycleTests(unittest.TestCase):
    def test_join_keeps_exact_measured_grid_and_single_endpoint(self):
        t=np.arange(2001)*.001
        clock,values=join_measured([(t[:1001],t[None,:1001]),(t[1000:],t[None,1000:])])
        np.testing.assert_array_equal(clock,t)
        np.testing.assert_array_equal(values,t[None,:])

    def test_jump_not_averaged(self):
        t=np.arange(2001)*.001
        with self.assertRaises(ValueError):join_measured([(t[:1001],t[None,:1001]),(t[1000:],t[None,1000:]+1e-12)])

    def test_gap_not_interpolated(self):
        t=np.arange(2001)*.001
        with self.assertRaises(ValueError):join_measured([(t[:1001],t[None,:1001]),(t[1001:],t[None,1001:])])

    def test_inventory_drift_is_not_tested_against_conservation_precision(self):
        t=np.arange(100001)*.001+620
        r=native_statistics(t,(2+.003*(t-620))[None,:])
        self.assertAlmostEqual(r['net_change'],.3)
        self.assertAlmostEqual(r['same_phase_rms'],.03)
        self.assertFalse(r['tolerance_imposed'])
        self.assertNotIn('pass',r)

    def test_original_production_statistics_called(self):
        source=(Path(__file__).parent/'Analyze_HeatDriveECC_RecordedThermalPeriodicity.m').read_text()
        self.assertIn('p=Evaluate_HeatDriveECC_Periodicity(physical,options)',source)
        self.assertNotIn('options.validation.',source)
        self.assertNotIn('sim(',source)

    def test_fixed_native_pipe_does_not_use_transport_density_for_storage(self):
        source=(Path(__file__).parent/'Analyze_HeatDriveECC_RecordedTenCycles.py').read_text()
        self.assertIn("mode['dynamic_compressibility'] != 'false'",source)
        self.assertIn('mass*np.asarray(specific_energy)',source)
        self.assertNotIn("volume*n('rho_I')*n('u_I')",source)

    def test_clock_alignment_reuses_existing_ulp_rule_without_resampling(self):
        source=(Path(__file__).parent/'Analyze_HeatDriveECC_RecordedTenCycles.py').read_text()
        self.assertIn('aligned_window_indices(clock, time)',source)
        self.assertNotIn('np.interp(',source)

    def test_closeout_does_not_promote_public_pass_to_complete_state_authority(self):
        source=(Path(__file__).parent/'Close_HeatDriveECC_RecordedTenCycles.py').read_text()
        self.assertIn('complete_internal_state_periodicity_verified=False',source)
        self.assertIn('production_recovery_allowed=False,outer_solve_eligible=False',source)
        self.assertIn("output=output.resolve()",source)
        self.assertIn("boundary[key]['bitwise_values_equal']",source)


if __name__=='__main__':unittest.main()
