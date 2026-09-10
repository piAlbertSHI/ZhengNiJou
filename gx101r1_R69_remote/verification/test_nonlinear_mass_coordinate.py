import unittest
import numpy as np
from Audit_HeatDriveECC_NonlinearMassProbe import scalar_state_match


class NonlinearMassCoordinateTests(unittest.TestCase):
    def test_bijective_increment_near_origin(self):
        increment=np.array([-1e-6,-1e-15,0.,1e-15,1e-6])
        scale=.1
        z=np.arcsinh(increment/scale)
        np.testing.assert_allclose(scale*np.sinh(z),increment,rtol=3e-16,atol=0)

    def test_exact_chain_rule_for_constant_mass_flux(self):
        t=np.linspace(0,.04,161);flow=1e-6;scale=.0016
        z=np.arcsinh(flow*t/scale)
        dz=(flow/scale)/np.sqrt(1+(flow*t/scale)**2)
        np.testing.assert_allclose(scale*np.cosh(z)*dz,flow,rtol=5e-16,atol=0)

    def test_finite_positive_jacobian(self):
        z=np.linspace(-3,3,101)
        self.assertTrue(np.all(.1*np.cosh(z)>=.1))

    def test_saved_coordinate_must_match_physical_values(self):
        row=dict(name='ecc_shifted_inventory_probe.Inventory.mass_coordinate',label='CSTATE',
                 data=[0.,1e-7],time_s=[0.,.04],unit='')
        c=dict(state_values=[row]);traces=dict(mass_coordinate=dict(values=[0.,1e-7],time_s=[0.,.04]))
        self.assertTrue(scalar_state_match(c,traces,'mass_coordinate')['numeric_identity_verified'])
        row['data']=[.1,.1000001]
        with self.assertRaises(ValueError):scalar_state_match(c,traces,'mass_coordinate')

    def test_discrete_label_is_not_continuous_coordinate_evidence(self):
        row=dict(name='ecc_shifted_inventory_probe.Inventory.mass_coordinate',label='DSTATE')
        with self.assertRaises(ValueError):scalar_state_match(dict(state_values=[row]),{},'mass_coordinate')


if __name__=='__main__':unittest.main()
