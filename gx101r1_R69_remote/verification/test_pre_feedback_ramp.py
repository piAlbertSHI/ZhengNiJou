import unittest
from Audit_HeatDriveECC_PreFeedbackRamp import metrics


class RampTests(unittest.TestCase):
    def fixture(self):
        c=dict(stop_time_s=.14,integral_held_zero=True,feedback_disabled=True,new_filter_added=False,
            full_feedback_derivative_verified=False,production_recovery_allowed=False,
            feedback_event_s=.15,reset_release_s=.15,time_s=[0,.1,.15],bias_MPa=[-1e-6,-1e-6,-.250001],
            ramp_start_s=.1,ramp_slope_MPa_s=-5,pressure_min_MPa=-.35,pressure_max_MPa=.02)
        return dict(contract=c,time_s=[0,.1,.14],slope_time_s=[0,.1,.14],integral_time_s=[0,.1,.14],
                    bias_MPa=[-1e-6,-1e-6,-.200001],slope_MPa_s=[0,-5,-5],integral_MPa=[-1e-6,-1e-6,-.200001])

    def test_valid_sources_do_not_claim_integral_qualification(self):
        r=metrics(self.fixture());self.assertTrue(r['source_value_and_slope_pass'])
        self.assertFalse(r['auxiliary_integration_precision_qualified'])

    def test_fake_zero_slope_rejected(self):
        r=self.fixture();r['slope_MPa_s']=[0,0,0]
        with self.assertRaises(ValueError):metrics(r)

    def test_feedback_boundary_not_crossed(self):
        r=self.fixture();r['contract']['feedback_event_s']=.14
        with self.assertRaises(ValueError):metrics(r)


if __name__=='__main__':unittest.main()
