import unittest
import numpy as np
from Audit_HeatDriveECC_InitialFluxPressure import flux_constraints


class InitialFluxTests(unittest.TestCase):
    def fixture(self):
        return [dict(mdot_B=-.1, Phi_B=-2., pdot=5.), dict(mdot_A=.1, Phi_A=2., pdot=5.)], dict(mdot_A=.1, mdot_B=-.1, Phi_A=2., Phi_B=-2., power=0.)

    def test_equal_nonzero_pressure_rates_are_allowed(self):
        a, p = self.fixture(); self.assertTrue(flux_constraints(a, p)['initial_flux_pressure_consistency_pass'])

    def test_pressure_mismatch_is_not_hidden_by_energy_pass(self):
        a, p = self.fixture(); a[1]['pdot'] += 1.
        self.assertFalse(flux_constraints(a, p)['initial_flux_pressure_consistency_pass'])

    def test_pump_energy_and_nonfinite_rejected(self):
        a, p = self.fixture(); p['power'] = 1.
        self.assertFalse(flux_constraints(a, p)['initial_flux_pressure_consistency_pass'])
        a[0]['pdot'] = np.nan
        with self.assertRaises(ValueError):
            flux_constraints(a, p)


if __name__ == '__main__':
    unittest.main()
