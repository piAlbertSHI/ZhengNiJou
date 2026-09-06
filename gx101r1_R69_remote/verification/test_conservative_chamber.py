import unittest
from pathlib import Path

import numpy as np
from scipy.interpolate import RegularGridInterpolator

from Audit_HeatDriveECC_ConservativeChamberResult import closed_balance, independent_endpoint
from Audit_HeatDriveECC_NativeInventoryCatalog import convert


class ConservativeChamberTests(unittest.TestCase):
    def test_total_energy_unit_remains_distinct_from_power(self):
        np.testing.assert_array_equal(convert([1, -2], 'J', 'J'), [1, -2])
        for native in ('W', 'J/kg'):
            with self.assertRaises(ValueError):
                convert([1], native, 'J')

    def test_signed_heat_and_inventory_alias(self):
        for heat in (-5, 5):
            row = closed_balance([0, 1], [1000, 1000], [100000, 100000+heat/.001], 1e-6, heat)
            self.assertTrue(row['mass_closure_pass'])
            self.assertTrue(row['energy_closure_pass'])

    def test_interior_violation_not_hidden_by_closed_endpoints(self):
        row = closed_balance([0, .5, 1], [1000, 1001, 1000], [100000]*3, 1e-6, 0)
        self.assertFalse(row['mass_closure_pass'])
        self.assertFalse(row['energy_closure_pass'])

    def test_heat_sign_error_rejected(self):
        row = closed_balance([0, 1], [1000, 1000], [100000, 105000], 1e-6, -5)
        self.assertFalse(row['energy_closure_pass'])

    def test_invalid_physical_inputs(self):
        for time, rho, volume in (([0, 0], [1, 1], 1), ([0, 1], [-1, -1], 1),
                                  ([0, 1], [1, np.nan], 1), ([0, 1], [1, 1], 0)):
            with self.assertRaises(ValueError):
                closed_balance(time, rho, [1, 1], volume, 0)

    def test_independent_endpoint_for_analytic_tables(self):
        t, p = np.array([280., 300., 320.]), np.array([1e6, 3e6, 5e6])
        temp, pressure = np.meshgrid(t, p, indexing='ij')
        fields = dict(rho=1000+.001*(pressure/1e6-3)-.01*(temp-300),
                      u=100000+4000*(temp-300), cp=np.full_like(temp, 4000),
                      beta=np.full_like(temp, 1e12), alpha=np.full_like(temp, 1e-5))
        tables = {k:RegularGridInterpolator((t, p), v) for k,v in fields.items()}
        result = independent_endpoint(tables, 300, 3e6, 1e-6, .4)
        np.testing.assert_allclose(result, [300.1, 4e6], atol=.001, rtol=0)

    def test_component_differentiates_inventory_not_table_coefficients(self):
        source = (Path(__file__).parent/'simscape_inventory/+ecc_inventory/conservative_chamber.ssc').read_text()
        self.assertIn('der(stored_mass) == mdot_A + mdot_B;', source)
        self.assertIn('der(stored_energy) == Phi_A + Phi_B + Q_H;', source)
        self.assertIn('stored_energy == stored_mass * u_I;', source)
        self.assertNotIn('der(p_I)', source)
        self.assertNotIn('der(T_I)', source)


if __name__ == '__main__':
    unittest.main()
