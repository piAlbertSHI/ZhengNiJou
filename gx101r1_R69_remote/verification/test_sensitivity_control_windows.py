import unittest

from Analyze_HeatDriveECC_SensitivityControlWindows import window_metrics


class ControlWindowMetricsTests(unittest.TestCase):
    def rows(self):
        return [dict(cycle=k+1,window_s=[k*10,(k+1)*10],temperature_lift_eq9_K=20+k,
            cooling_power_eq10_W=10+k,SCP_W_per_g=.1+.01*k,CHEX_sensor_mean_W=9+k,
            positive_SHEX_heat_mean_W=100+10*k) for k in range(10)]

    def test_equal_duration_mean_and_ratio_of_total_heat(self):
        r=window_metrics(self.rows())
        self.assertEqual(r['temperature_lift_eq9_K'],24.5)
        self.assertEqual(r['cooling_power_eq10_W'],14.5)
        self.assertEqual(r['heat_driven_COP'],.1)

    def test_missing_cycle_rejected(self):
        with self.assertRaises(ValueError):window_metrics(self.rows()[:-1])

    def test_unequal_duration_cannot_use_unweighted_mean(self):
        r=self.rows();r[0]['window_s']=[0,9]
        with self.assertRaises(ValueError):window_metrics(r)


if __name__=='__main__':unittest.main()
