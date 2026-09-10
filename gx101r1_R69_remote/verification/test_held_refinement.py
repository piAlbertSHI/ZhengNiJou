import unittest
from Audit_HeatDriveECC_HeldRefinement import endpoint_comparison


class HeldRefinementTests(unittest.TestCase):
    def test_limits_remain_physical_and_separate(self):
        c=dict(mass_endpoint_change_kg=0,integrated_mass_input_kg=0,energy_endpoint_change_J=0,integrated_energy_input_J=0)
        f=dict(c);f['mass_endpoint_change_kg']=2e-16;f['energy_endpoint_change_J']=2e-10
        self.assertTrue(endpoint_comparison(c,f)['within_limits'])
        f['integrated_mass_input_kg']=2e-15
        self.assertFalse(endpoint_comparison(c,f)['within_limits'])

    def test_nonfinite_rejected(self):
        c=dict(mass_endpoint_change_kg=0,integrated_mass_input_kg=0,energy_endpoint_change_J=0,integrated_energy_input_J=0)
        f=dict(c);f['energy_endpoint_change_J']=float('nan')
        with self.assertRaises(ValueError):endpoint_comparison(c,f)


if __name__=='__main__':unittest.main()
