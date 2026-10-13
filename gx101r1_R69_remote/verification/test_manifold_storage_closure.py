import copy
import re
import unittest
from pathlib import Path

import numpy as np

from Analyze_HeatDriveECC_ManifoldStorageClosure import compare_configs
from Audit_HeatDriveECC_ColdChamberCycle import custom_ledger


class StorageClosureTests(unittest.TestCase):
    def configs(self):
        a = dict(diagnostic_inventory_options={'volume_factor': 1}, output_root='a',
                 diagnostic_state_options={'mode': 'off', 'command_horizon_cycles': 1},
                 cycle_count=1, duration_s=10, diagnostic_arm='native', endpoint_all_arms=True,
                 stage4_kp=-225)
        b = copy.deepcopy(a)
        b.update(output_root='b', diagnostic_inventory_options={'storage_closure': 'pressure_only_density'})
        return a, b

    def chamber(self):
        time = np.arange(3) * .001
        temp = np.array([300., 310., 320.])
        pressure = np.full(3, 1e5)
        table = dict(rho=lambda xy: 1000-(xy[:, 0]-300)+(xy[:, 1]-1e5)*1e-6,
                     u=lambda xy: 100*xy[:, 0]+.001*xy[:, 1])
        u = table['u'](np.column_stack((temp, pressure)))
        mass = np.full(3, .001)
        energy = mass*u
        values = dict(T_I=(temp, 'K'), p_I=(pressure, 'Pa'), rho_I=(mass/1e-6, 'kg/m^3'),
                      u_I=(u, 'J/kg'), stored_mass=(mass, 'kg'), stored_energy=(energy, 'J'),
                      Phi_A=(np.r_[0, np.diff(energy)/.001], 'W'), Phi_B=(np.zeros(3), 'W'),
                      Q_H=(np.zeros(3), 'W'), mdot_A=(np.zeros(3), 'kg/s'), mdot_B=(np.zeros(3), 'kg/s'))
        block = dict(block_path='model/Chamber', mask_type='Constant Volume Chamber (TL)',
                     reference_block='ecc_inventory_pressure_only.conservative_chamber',
                     mask_parameters=dict(volume=dict(value=1e-6, unit='m^3'),
                                          inventory_reference_temperature=dict(value=300, unit='K')),
                     leaf_variables=[dict(name=name, values=data, unit=unit, time_s=time)
                                     for name, (data, unit) in values.items()])
        return block, table

    def test_only_declared_density_law_changes(self):
        compare_configs(*self.configs())

    def test_geometry_gain_or_restore_change_rejected(self):
        for field, value in (('stage4_kp', -230), ('duration_s', 200),
                             ('diagnostic_state_options', {'mode': 'diagnostic_resume'})):
            with self.subTest(field=field):
                a, b = self.configs()
                b[field] = value
                with self.assertRaises(ValueError):
                    compare_configs(a, b)

    def test_declared_pressure_only_balance_passes(self):
        block, table = self.chamber()
        row, _ = custom_ledger(block, table, inventory_reference_temperature=300)
        self.assertTrue(row['local_chamber_gate']['mass_closure_pass'])
        self.assertTrue(row['local_chamber_gate']['energy_closure_pass'])
        self.assertFalse(row['real_fluid_EOS_claim'])

    def test_original_real_EOS_audit_still_rejects_new_law(self):
        with self.assertRaises(ValueError):
            custom_ledger(*self.chamber())

    def test_undeclared_reference_or_source_rejected(self):
        block, table = self.chamber()
        with self.assertRaises(ValueError):
            custom_ledger(block, table, inventory_reference_temperature=310)
        block['reference_block'] = 'ecc_inventory_endpoint.conservative_chamber'
        with self.assertRaises(ValueError):
            custom_ledger(block, table, inventory_reference_temperature=300)

    def test_energy_properties_must_remain_temperature_dependent(self):
        block, table = self.chamber()
        next(row for row in block['leaf_variables'] if row['name'] == 'u_I')['values'][:] = 30100
        with self.assertRaises(ValueError):
            custom_ledger(block, table, inventory_reference_temperature=300)

    def test_component_retains_mass_and_energy_equations(self):
        folder = Path(__file__).parent
        source = (folder/'simscape_inventory_pressure_only/+ecc_inventory_pressure_only/conservative_chamber.ssc').read_text()
        for equation in ('der(stored_mass) == mdot_A + mdot_B;',
                         'der(stored_energy) == Phi_A + Phi_B + Q_H;',
                         'A.u_TLU, T_I, p_I', 'A.rho_TLU, inventory_reference_temperature, p_I'):
            self.assertIn(equation, source)

    def test_no_other_component_equation_changes(self):
        folder = Path(__file__).parent
        normalize = lambda text: re.sub(r'\s+', '', re.sub(r'%[^\n]*', '', text))
        original = normalize((folder/'simscape_inventory_endpoint/+ecc_inventory_endpoint/conservative_chamber.ssc').read_text())
        candidate = normalize((folder/'simscape_inventory_pressure_only/+ecc_inventory_pressure_only/conservative_chamber.ssc').read_text())
        for added in ("inventory_reference_temperature={393.15,'K'};",
                      'assert(inventory_reference_temperature>=A.T_min)',
                      'assert(inventory_reference_temperature<=A.T_max)'):
            candidate = candidate.replace(added, '')
        self.assertEqual(candidate.replace('inventory_reference_temperature', 'T_I'), original)


if __name__ == '__main__':
    unittest.main()
