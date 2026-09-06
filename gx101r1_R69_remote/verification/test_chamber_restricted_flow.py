import unittest

import numpy as np

from Audit_HeatDriveECC_ChamberRestrictedFlow import port_identities, pump_power_contract


class RestrictedFlowTests(unittest.TestCase):
    def test_nonzero_pump_power_uses_port_density_and_signed_head(self):
        source = dict(rho_A=np.array([900.,1000.]),rho_B=np.array([1100.,1000.]),
                      mdot_A=np.array([.0002,-.0002]),power=np.array([.02,.02]))
        error = pump_power_contract(source,np.array([2e6,2e6]),np.array([2.1e6,1.9e6]))
        self.assertLess(error,1e-15)
        source['power'] *= -1
        self.assertGreater(pump_power_contract(source,np.array([2e6,2e6]),np.array([2.1e6,1.9e6])),.03)

    def test_nonfinite_density_rejected(self):
        source = dict(rho_A=np.array([np.nan]),rho_B=np.array([1000.]))
        with self.assertRaises(ValueError):
            pump_power_contract(source,np.array([1]),np.array([1]))

    def test_restriction_port_leak_not_hidden_by_external_totals(self):
        c = dict(mdot_A=np.array([2.]),mdot_B=np.array([-2.]),Phi_A=np.array([10.]),Phi_B=np.array([-10.]))
        s = dict(mdot_A=np.array([2.]),mdot_B=np.array([-2.]),Phi_A=np.array([9.]),Phi_B=np.array([-10.]),power=np.array([1.]))
        h = dict(mdot_A=np.array([-2.]),Phi_A=np.array([-9.]))
        cold = dict(mdot_A=np.array([2.]),Phi_A=np.array([10.]))
        r = dict(mdot_A=np.array([2.]),mdot_B=np.array([-2.]),Phi_A=np.array([10.]),Phi_B=np.array([-10.]))
        self.assertEqual(port_identities(c,s,h,cold,r),(0,0))
        r['Phi_A'] += 1
        self.assertEqual(port_identities(c,s,h,cold,r),(0,1))


if __name__ == '__main__':
    unittest.main()
