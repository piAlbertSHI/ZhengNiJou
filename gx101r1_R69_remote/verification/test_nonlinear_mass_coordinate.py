import unittest
import numpy as np


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


if __name__=='__main__':unittest.main()
