import unittest
import numpy as np
from Audit_HeatDriveECC_ColdPumpPressureProbes import source_port_balance_W


class PressurePowerUnitsTests(unittest.TestCase):
    def test_mixed_power_units_close_in_watts(self):
        result=source_port_balance_W(np.array([.2]),'kW',np.array([-150.]),'W',np.array([-.05]),'kW')
        np.testing.assert_allclose(result,0,rtol=0,atol=1e-12)

    def test_kw_residual_is_not_mislabeled_watts(self):
        result=source_port_balance_W(np.array([1e-9]),'kW',np.array([0.]),'kW',np.array([0.]),'kW')
        np.testing.assert_allclose(result,1e-6,rtol=0,atol=1e-20)

    def test_wrong_quantity_rejected(self):
        with self.assertRaises(ValueError):
            source_port_balance_W(np.array([0.]),'K',np.array([0.]),'W',np.array([0.]),'W')
