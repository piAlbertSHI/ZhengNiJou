import copy
import unittest

import numpy as np
from scipy.interpolate import RegularGridInterpolator

from Audit_HeatDriveECC_DiscreteSystemLedger import be_flow, component_balance, mass_path_integrals, mass_table_bridge
from test_native_window_ledger import pipe, TABLE


def path_tables():
    temperature = np.array([290., 300., 301., 310.])
    pressure = np.array([1e5, 1e6, 2e6])
    rho = np.repeat((1000 - 2 * (temperature - 300))[:, None], len(pressure), axis=1)
    return {name: RegularGridInterpolator((temperature, pressure), values)
            for name, values in dict(rho=rho, alpha=np.full_like(rho, .001), beta=np.full_like(rho, 1e9)).items()}


class DiscreteSystemLedgerTests(unittest.TestCase):
    def test_BE_preserves_right_endpoint_sign(self):
        np.testing.assert_array_equal(be_flow([10, -2, 3], [0, 1, 3]), [-2, 6])
        for flow, time in (([1, 2], [0, 0]), ([1], [0, 1]), ([1, np.nan], [0, 1])):
            with self.assertRaises(ValueError):
                be_flow(flow, time)

    def test_pipe_endpoint_is_discrete_energy_not_native_density_mass(self):
        row, terms, _, _ = component_balance(pipe(), TABLE, .001)
        self.assertTrue(row['discrete_energy_equation_match'])
        self.assertEqual(row['endpoint_fluid_mass_change_kg'], 0)
        self.assertEqual(row['discrete_accumulation_J'], 4)
        self.assertEqual(row['coefficient_vs_endpoint_plus_pV_J'], 0)
        self.assertEqual(terms['head_transport_J'].sum(), 0)
        self.assertFalse(row['physical_mass_closure_verified'])

    def test_wrong_energy_flow_does_not_pass(self):
        block = pipe()
        next(r for r in block['leaf_variables'] if r['name'] == 'Q_H')['values'] = [5, 5]
        row, _, _, _ = component_balance(block, TABLE, .001)
        self.assertFalse(row['discrete_energy_equation_match'])
        self.assertEqual(row['energy_residual_J'], 1)

    def test_tank_requires_geometry(self):
        block = pipe()
        block.update(mask_type='Tank (TL)')
        block['leaf_variables'] += [dict(name='mass', unit='kg', time_s=[0, 1], values=[1, 1]),
                                    dict(name='volume', unit='m^3', time_s=[0, 1], values=[.001, .001])]
        with self.assertRaises(ValueError):
            component_balance(block, TABLE)

    def test_path_quadrature_across_knots_is_analytic(self):
        table = path_tables()
        for order in (3, 5):
            t, p = mass_path_integrals([299., 302.], [1e6, 1e6], 1e-6, table, order)
            self.assertAlmostEqual(t[0], -1e-6 * .001 * 3 * 999, places=17)
            self.assertEqual(p[0], 0)

    def test_closed_path_integral_is_not_closed_BE_sum(self):
        table = path_tables()
        t, p = mass_path_integrals([300., 302., 300.], [1e6]*3, 1e-6, table, 3)
        self.assertAlmostEqual(t.sum() + p.sum(), 0, places=18)
        rho = np.array([1000., 996., 1000.])
        backward_euler = (-1e-6 * .001 * rho[1:] * np.diff([300., 302., 300.])).sum()
        self.assertAlmostEqual(backward_euler, 8e-9, places=17)

    def test_pressure_path_and_stationary_interval(self):
        t, p = mass_path_integrals([300., 300., 300.], [1e6, 2e6, 2e6], 1e-6, path_tables(), 5)
        np.testing.assert_array_equal(t, [0, 0])
        np.testing.assert_allclose(p, [1e-6, 0], atol=1e-20)

    def test_invalid_or_variable_beta_rejected(self):
        for volume, order in ((-1, 3), (1e-6, 2)):
            with self.assertRaises(ValueError):
                mass_path_integrals([300, 301], [1e6]*2, volume, path_tables(), order)
        table = path_tables()
        table['beta'].values[0, 0] = 2e9
        with self.assertRaises(ValueError):
            mass_path_integrals([300, 301], [1e6]*2, 1e-6, table, 3)

    def test_chamber_mass_bridge_retains_two_distinct_defects(self):
        block = copy.deepcopy(pipe())
        block.update(mask_type='Constant Volume Chamber (TL)', mask_parameters={'volume': {'value': 1e-6, 'unit': 'm^3'}})
        table = path_tables()
        for row in block['leaf_variables']:
            if row['name'] == 'rho_I':
                row['values'] = [1000, 998]
        bridge = mass_table_bridge(block, table)
        self.assertAlmostEqual(bridge['BE_minus_path_integral_mass_kg'], 1e-9, places=17)
        self.assertNotEqual(bridge['path_integral_minus_endpoint_mass_kg'], 0)
        self.assertLess(bridge['path_quadrature_3_vs_5_max_difference_kg'], 1e-18)

    def test_energy_cell_quadrature_has_independent_analytic_case(self):
        table = path_tables()
        grid = table['rho'].grid
        table['rho'].values[:] = 1000
        table['alpha'].values[:] = 0
        table['cp'] = RegularGridInterpolator(grid, np.full_like(table['rho'].values, 4000))
        table['u'] = RegularGridInterpolator(grid, np.repeat((100000 + 4000*(grid[0]-300))[:, None], 3, axis=1))
        for order in (4, 5):
            values = mass_path_integrals([299, 302], [1e6, 1e6], 1e-6, table, order, True)
            self.assertAlmostEqual(values[2].sum(), 12, places=12)
            self.assertEqual(values[3].sum(), 0)
        with self.assertRaises(ValueError):
            mass_path_integrals([299, 302], [1e6, 1e6], 1e-6, table, 3, True)


if __name__ == '__main__':
    unittest.main()
