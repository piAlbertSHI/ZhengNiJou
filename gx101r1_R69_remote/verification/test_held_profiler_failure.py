import unittest
from copy import deepcopy
from Audit_HeatDriveECC_HeldProfilerFailure import check_callbacks, check_profiler, OPTIONS, SETTINGS


class HeldProfilerFailureTests(unittest.TestCase):
    def test_read_only_callback_addition(self):
        previous=[dict(stage=s,targets=[1,2]) for s in ('InitFcn','StartFcn','StopFcn')]
        current=[dict(c,AutoScaleAbsTol='on') for c in previous]
        saved=deepcopy(current);check_callbacks(current,previous);self.assertEqual(saved,current)
        for key,value in [('AutoScaleAbsTol','off'),('targets',[]),('unexpected',True)]:
            changed=deepcopy(current);changed[0][key]=value
            with self.assertRaises(ValueError):check_callbacks(changed,previous)

    def test_missing_capture_cannot_be_passed(self):
        p=dict(capture_pass=False,api_returned=False,data_file_exists=False,science_gate_pass=False,
            full_jacobian_analyzed=False,production_recovery_allowed=False,requested_options=OPTIONS,
            expected_settings=SETTINGS,settings_after=SETTINGS,AutoScaleAbsTol_before='on',AutoScaleAbsTol_after='on',
            error_message='1.584348158130581e-301',error_report='\u5947\u5f02\u8fed\u4ee3\u77e9\u9635')
        check_profiler(p)
        for flag in ('capture_pass','api_returned','data_file_exists','science_gate_pass','full_jacobian_analyzed'):
            with self.assertRaises(ValueError):check_profiler(dict(p,**{flag:True}))
