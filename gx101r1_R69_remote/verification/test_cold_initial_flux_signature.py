import unittest
import numpy as np
from Audit_HeatDriveECC_ColdInitialFluxSignature import signature, quantity


class InitialFluxSignatureTests(unittest.TestCase):
    def test_signed_energy_transfer(self):
        r=signature([2e-5,-2e-5,0],[1,-1,0])
        self.assertEqual(r['maximum_abs_residual'],0)
        self.assertAlmostEqual(r['least_squares_step_s'],2e-5)

    def test_zero_rate_has_no_inferred_step(self):
        self.assertIsNone(signature([0],[0])['least_squares_step_s'])
        self.assertGreater(signature([1],[0])['maximum_abs_residual'],0)

    def test_other_step_not_silently_fitted_away(self):
        r=signature([1e-3],[1])
        self.assertEqual(r['least_squares_step_s'],1e-3)
        self.assertGreater(r['maximum_abs_residual'],1e-4)

    def test_invalid_inputs(self):
        for a,b in [([],[]),([1],[1,2]),([np.nan],[1]),([[1]],[[1]])]:
            with self.assertRaises(ValueError): signature(a,b)

    def test_numeric_geometry_and_energy_units(self):
        self.assertEqual(quantity(.001,'m^2','m^2'),.001)
        self.assertEqual(quantity(500,'J/(K*kg)','J/(K*kg)'),500)
        self.assertEqual(quantity(1,'kJ/kg','J/kg'),1000)
        with self.assertRaises(ValueError): quantity(np.nan,'m','m')


if __name__=='__main__':unittest.main()
