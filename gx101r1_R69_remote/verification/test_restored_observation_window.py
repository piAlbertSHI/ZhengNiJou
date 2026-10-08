from pathlib import Path
import unittest

import numpy as np

from HeatDriveECC_ObservationWindow import window_indices
from Audit_HeatDriveECC_ColdPumpPressureProbes import normalized_signal
from Audit_HeatDriveECC_DistributedPressureRuntime import window_coordinates


class RestoredWindowTests(unittest.TestCase):
    def test_cold_and_restored_origins_select_identical_absolute_windows(self):
        for origin in (0, 20):
            time=origin+np.arange(round((220-origin)/.001)+1)*.001
            selected=window_indices(time,200,220)
            np.testing.assert_allclose(time[selected],200+np.arange(20001)*.001,rtol=0,atol=1e-9)
            self.assertEqual(selected[0],round((200-origin)/.001))

    def test_missing_sample_and_duplicated_sample_rejected(self):
        time=20+np.arange(200001)*.001
        for changed in (np.delete(time,100), np.insert(time,100,time[100])):
            with self.assertRaises(ValueError): window_indices(changed,200,220)

    def test_nonfinite_and_non_integer_millisecond_origins_rejected(self):
        time=20+np.arange(200001)*.001
        changed=time.copy();changed[0]=np.nan
        for bad in (changed,time+.0001):
            with self.assertRaises(ValueError): window_indices(bad,200,220)

    def test_truncated_boundary_rejected(self):
        time=200+np.arange(20000)*.001
        with self.assertRaises(ValueError): window_indices(time,200,220)

    def test_pressure_normalization_uses_restored_origin(self):
        time=20+np.arange(200001)*.001
        row={'time_s':time[None,:],'values':time[None,:]}
        t,v,trimmed=normalized_signal(row,200,220,True)
        self.assertEqual(t.size,20001);self.assertTrue(trimmed)
        np.testing.assert_array_equal(t,v)
        with self.assertRaises(ValueError): normalized_signal(row,200,220,False)

    def test_runtime_requires_final_stop_not_an_extra_future_window(self):
        time=20+np.arange(200001)*.001
        self.assertEqual(window_coordinates(time,200,220).size,20001)
        with self.assertRaises(ValueError): window_coordinates(time,200,210)

    def test_capture_and_resume_keep_intact_vendor_state_and_bounded_history(self):
        folder=Path(__file__).parent
        loader=(folder/'Load_HeatDriveECC_DiagnosticResumeSource.m').read_text()
        runner=(folder/'Run_HeatDriveECC_ColdChamberDiagnostic.m').read_text()
        self.assertIn('op=saved.diagnostic_operating_point',loader)
        self.assertNotIn('.loggedStates=',loader)
        self.assertIn('proof.rebuilt_complete_cycle_pass',loader)
        self.assertIn('input=input.setInitialState(diagnostic_initial_op)',runner)
        self.assertIn('Configure_HeatDriveECC_DiagnosticStateCapture(model,min(cycle_count,11))',runner)
        self.assertIn('simulation_stop=simulation_start+duration',runner)
