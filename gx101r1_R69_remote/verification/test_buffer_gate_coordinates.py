import unittest
import numpy as np

from Review_HeatDriveECC_BufferGateCoordinates import corrected_checks


class BufferGateCoordinateTests(unittest.TestCase):
    def base(self):
        return [np.array([1,2,3,4]),np.full(4,303.15),np.full(4,393.15),
                np.array([390.,303.15,350.,303.15]),np.full(4,360.),np.array([1e-7,0.,.05,0.]),
                303.15,393.15,.0000508,5.,3.]

    def test_dead_port_hot_temperature_is_not_a_flowing_front(self):
        checks,details=corrected_checks(*self.base())
        self.assertTrue(all(checks.values()))
        self.assertEqual(details['inactive_hot_front_samples'],1)

    def test_real_buffer_inventory_heating_fails(self):
        values=self.base();values[1]=np.array([303.15,309.15,309.15,309.15])
        self.assertFalse(corrected_checks(*values)[0]['SMA_buffer_cross_contamination'])

    def test_real_internal_shex_above_source_fails(self):
        values=self.base();values[2][2]=397.
        self.assertFalse(corrected_checks(*values)[0]['SMA_buffer_cross_contamination'])

    def test_non_negligible_out_of_stage_hot_front_fails(self):
        values=self.base();values[5][0]=.05
        self.assertFalse(corrected_checks(*values)[0]['SMA_stage3_HHEX_hot_front_physical'])

    def test_intermediate_leak_below_active_target_is_still_counted(self):
        values=self.base();values[5][0]=.001
        self.assertFalse(corrected_checks(*values)[0]['SMA_stage3_HHEX_hot_front_physical'])

    def test_flowing_front_above_current_solid_bound_fails(self):
        values=self.base();values[3][2]=363.
        self.assertFalse(corrected_checks(*values)[0]['SMA_stage3_HHEX_hot_front_physical'])

    def test_absent_flowing_front_is_not_a_pass(self):
        values=self.base();values[5][:]=0.
        self.assertFalse(corrected_checks(*values)[0]['SMA_stage3_HHEX_hot_front_physical'])

    def test_no_new_invalid_or_loose_threshold(self):
        values=self.base();values[8]=0.
        with self.assertRaises(ValueError):corrected_checks(*values)


if __name__=='__main__':unittest.main()
