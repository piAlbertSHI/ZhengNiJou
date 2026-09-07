import unittest

import numpy as np

from Audit_HeatDriveECC_ConverterEvidence import audit_trace, ticks


class ConverterEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.t = np.array([2000.,2000.001,2000.002])
        self.q = np.array([0.,5.,-3.])
        self.trace = dict(time_s=self.t, converter_time_s=self.t,
                          source_Q_W=self.q.copy(), mass_Q_W=-self.q,
                          temperature_K=np.array([340.,339.999995,339.999998]),
                          converter_values=np.array([[0,1,1],self.q]))

    def check(self):
        return audit_trace(self.trace,self.t,self.q,1000,.001)

    def test_physical_delivery(self):
        result = self.check()
        self.assertTrue(result['input_delivery_pass'])
        self.assertTrue(result['port_sign_pass'])
        self.assertTrue(result['backward_euler_energy_pass'])

    def test_equal_but_wrong_input_is_rejected(self):
        self.trace['source_Q_W'][:] = 0
        self.assertFalse(self.check()['input_delivery_pass'])

    def test_wrong_sign_is_rejected(self):
        self.trace['mass_Q_W'] = self.q
        self.assertFalse(self.check()['port_sign_pass'])

    def test_missing_energy_is_rejected(self):
        self.trace['temperature_K'][:] = 340
        self.assertFalse(self.check()['backward_euler_energy_pass'])

    def test_sub_tick_shift_is_rejected(self):
        with self.assertRaises(ValueError):
            ticks(self.t+.0001,.001)

    def test_one_ulp_grid_not_equated_to_bitwise_identity(self):
        other = np.nextafter(self.t,np.inf)
        self.assertFalse(np.array_equal(self.t,other))
        np.testing.assert_array_equal(ticks(self.t,.001),ticks(other,.001))

    def test_nan_rejected(self):
        self.trace['temperature_K'][1] = np.nan
        with self.assertRaises(ValueError):
            self.check()

    def test_missing_sample_rejected(self):
        self.trace['time_s'] = np.array([2000.,2000.002,2000.003])
        with self.assertRaises(ValueError):
            self.check()


if __name__ == '__main__':
    unittest.main()
