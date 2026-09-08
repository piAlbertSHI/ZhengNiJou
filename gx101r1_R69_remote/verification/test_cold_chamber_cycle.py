"""Cold time origin and conservative inventory ledger regression checks."""
import unittest
import numpy as np

from Audit_HeatDriveECC_C201Cycle import phase_axes
from Audit_HeatDriveECC_C201Inventory import stage_totals
from Audit_HeatDriveECC_ColdChamberCycle import custom_ledger, tank_endpoint_split


class ColdCycleTests(unittest.TestCase):
    def test_origin_preserves_historical_stages(self):
        t = np.array([0, 1, 3.5, 4, 5, 7, 8.5, 9, 10.])
        a = phase_axes(t, origin=0); b = phase_axes(t+2000)
        for x, y in zip(a, b):
            np.testing.assert_array_equal(x, y)
        np.testing.assert_array_equal(a[0], [1, 1, 2, 2, 3, 3, 4, 4, 4])

    def test_all_native_intervals_in_stage_partition(self):
        energy = np.r_[0, np.cumsum(np.arange(1, 10001)*.001)]
        rows = stage_totals({'energy': energy})
        self.assertAlmostEqual(sum(r['energy'] for r in rows), energy[-1])
        self.assertEqual([r['stop_phase_s'] for r in rows], [3.5, 5., 8.5, 10.])

    def fixture(self):
        t = np.arange(11)*.001
        values = {'rho_I': ('kg/m^3', 1000.), 'u_I': ('J/kg', 300000.),
                  'T_I': ('K', 300.), 'p_I': ('Pa', 1e6), 'stored_mass': ('kg', .001),
                  'stored_energy': ('J', 300.), 'mdot_A': ('kg/s', .01),
                  'mdot_B': ('kg/s', -.01), 'Phi_A': ('W', 12.),
                  'Phi_B': ('W', -10.), 'Q_H': ('W', -2.)}
        block = dict(block_path='test', mask_type='Constant Volume Chamber (TL)',
                     mask_parameters={'volume': {'value': 1e-6, 'unit': 'm^3'}},
                     leaf_variables=[dict(name=k, unit=u, time_s=t, values=np.full(11, v)) for k, (u, v) in values.items()])
        return block, {'rho': lambda x: np.full(len(x), 1000.), 'u': lambda x: np.full(len(x), 300000.)}

    def test_open_chamber_uses_actual_inventory(self):
        block, table = self.fixture()
        row, _ = custom_ledger(block, table)
        self.assertTrue(row['local_chamber_gate']['energy_closure_pass'])
        self.assertTrue(row['local_chamber_gate']['mass_closure_pass'])
        self.assertEqual(row['energy_start_J'], 300.)
        self.assertEqual(row['stored_energy_alias_max_error_J'], 0.)

    def test_unbalanced_heat_is_not_hidden(self):
        block, table = self.fixture()
        next(r for r in block['leaf_variables'] if r['name'] == 'Q_H')['values'] += 1
        row, _ = custom_ledger(block, table)
        self.assertFalse(row['local_chamber_gate']['energy_closure_pass'])
        self.assertAlmostEqual(row['endpoint_energy_residual_J_end'], .01)

    def test_wrong_property_domain_rejected(self):
        block, table = self.fixture()
        table['rho'] = lambda x: np.full(len(x), 999.)
        with self.assertRaisesRegex(ValueError, 'property'):
            custom_ledger(block, table)

    def test_tank_discrete_product_is_separate_from_secant(self):
        row = tank_endpoint_split([2, 3], [4, 4], [10, 12], [40, 48])
        self.assertEqual(row['cp_vs_enthalpy_secant_J'], 0)
        self.assertEqual(row['discrete_product_term_J'], 8)
        self.assertEqual(row['coefficient_minus_enthalpy_endpoint_J'], 8)
        self.assertTrue(row['decomposition_is_not_a_physical_heat_correction'])

    def test_tank_table_secant_mismatch_retained(self):
        row = tank_endpoint_split([2, 2], [4, 4], [10, 12], [40, 50])
        self.assertEqual(row['cp_vs_enthalpy_secant_J'], -4)
        self.assertEqual(row['discrete_product_term_J'], 0)

    def test_invalid_tank_inputs_rejected(self):
        with self.assertRaises(ValueError):
            tank_endpoint_split([0, 1], [4, 4], [10, 12], [40, 48])


if __name__ == '__main__':
    unittest.main()
