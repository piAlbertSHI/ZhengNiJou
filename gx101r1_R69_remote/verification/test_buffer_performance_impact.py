import unittest

from Analyze_HeatDriveECC_BufferPerformanceImpact import storage_metrics
from Audit_HeatDriveECC_NativeMappedBufferDrift import cycle_window


class BufferPerformanceImpactTests(unittest.TestCase):
    def test_windows_follow_actual_endpoint_not_hardcoded_C42(self):
        self.assertEqual(cycle_window(42,420),(320,420,33))
        self.assertEqual(cycle_window(62,620),(520,620,53))

    def test_incomplete_or_wrong_endpoint_rejected(self):
        for cycles,stop in ((42,620),(62,619),(42.5,425),(201,2010),(True,10)):
            with self.subTest(cycles=cycles),self.assertRaises(ValueError):
                cycle_window(cycles,stop)

    def test_finite_mass_and_hydrostatic_pressure(self):
        result=storage_metrics(-2.6e-7,-3.,.1,.001,9.81)
        self.assertAlmostEqual(result['relative_inventory_change'],-2.6e-6)
        self.assertAlmostEqual(result['port_hydrostatic_pressure_change_Pa'],-.0025506)
        self.assertEqual(result['stored_energy_rate_W'],-.3)

    def test_actual_period_controls_storage_rate(self):
        self.assertEqual(storage_metrics(0.,4.,.1,.001,0.,20)['stored_energy_rate_W'],.2)

    def test_invalid_quantities_rejected(self):
        for args in ((0,0,0,1,1),(0,0,1,0,1),(0,0,1,1,-1),
                     (0,float('nan'),1,1,1),(0,0,1,1,1,0)):
            with self.subTest(args=args),self.assertRaises(ValueError):
                storage_metrics(*args)

    def test_no_invented_cooling_correction(self):
        result=storage_metrics(0.,4.,.1,.001,9.81)
        self.assertNotIn('corrected_cooling_W',result)
        self.assertNotIn('periodic_pass',result)


if __name__=='__main__':
    unittest.main()
