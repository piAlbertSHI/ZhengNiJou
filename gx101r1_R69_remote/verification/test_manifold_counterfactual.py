import copy
import unittest

import numpy as np

from Analyze_HeatDriveECC_ManifoldCounterfactual import compare_configs, compare_metadata, mass_budget
from Audit_HeatDriveECC_CoupledEnergyInventory import BUFFER_NAMES, CHAMBER_NAMES, ROOT


class CounterfactualContractTests(unittest.TestCase):
    def configs(self):
        base = dict(diagnostic_state_options={'mode': 'off', 'command_horizon_cycles': 1},
            cycle_count=1, duration_s=10, diagnostic_arm='native', endpoint_all_arms=True,
            stage4_kp=-225, output_root='baseline', diagnostic_inventory_options={'volume_factor': 1})
        candidate = copy.deepcopy(base)
        candidate.update(output_root='candidate', diagnostic_inventory_options={'volume_factor': .1})
        return base, candidate

    def metadata(self):
        a = dict(settings_tables=[{'rho': [1000, 950]}], storage_blocks=[dict(
            block_path=ROOT+name, mask_parameters={'volume': {'unit': 'm^3', 'value': 1e-6}},
            initialization_parameters={'stored_mass': '.001', 'stored_energy': '100', 'T_I': '300'})
            for name in CHAMBER_NAMES])
        b = copy.deepcopy(a)
        for row in b['storage_blocks']:
            row['mask_parameters']['volume']['value'] *= .1
            row['initialization_parameters'].update(stored_mass='.0001', stored_energy='10')
        return a, b

    def test_only_declared_config_changes(self):
        a, b = self.configs()
        compare_configs(a, b)
        self.assertEqual(a['diagnostic_inventory_options']['volume_factor'], 1)

    def test_other_gain_change_rejected(self):
        a, b = self.configs(); b['stage4_kp'] = -245
        with self.assertRaises(ValueError): compare_configs(a, b)

    def test_state_loading_rejected(self):
        a, b = self.configs(); b['diagnostic_state_options']['mode'] = 'diagnostic_resume'
        with self.assertRaises(ValueError): compare_configs(a, b)

    def test_wrong_factor_rejected(self):
        a, b = self.configs(); b['diagnostic_inventory_options']['volume_factor'] = .2
        with self.assertRaises(ValueError): compare_configs(a, b)

    def test_volume_and_extensive_targets_scale(self):
        a, b = self.metadata(); compare_metadata(a, b)
        self.assertEqual(b['storage_blocks'][0]['initialization_parameters']['stored_energy'], '10')

    def test_temperature_change_rejected(self):
        a, b = self.metadata(); b['storage_blocks'][0]['initialization_parameters']['T_I'] = '301'
        with self.assertRaises(ValueError): compare_metadata(a, b)

    def test_unscaled_energy_target_rejected(self):
        a, b = self.metadata(); b['storage_blocks'][0]['initialization_parameters']['stored_energy'] = '100'
        with self.assertRaises(ValueError): compare_metadata(a, b)

    def test_property_table_change_rejected(self):
        a, b = self.metadata(); b['settings_tables'][0]['rho'][1] = 949
        with self.assertRaises(ValueError): compare_metadata(a, b)

    def test_missing_chamber_rejected(self):
        a, b = self.metadata(); b['storage_blocks'].pop()
        with self.assertRaises(ValueError): compare_metadata(a, b)

    def mass_data(self):
        time = np.arange(10001)*.001
        buffers = {name: dict(mass=np.ones_like(time)*.1, mass_flow=np.zeros_like(time)) for name in BUFFER_NAMES}
        chambers = {name: dict(volume=1e-6, mass=np.ones_like(time)*.001,
            density=np.ones_like(time)*1000, temperature=np.ones_like(time)*300,
            pressure=np.ones_like(time)*1e6, density_table=lambda points: np.ones(len(points))*1000)
            for name in CHAMBER_NAMES}
        return time, buffers, chambers

    def test_constant_inventory_closes(self):
        result = mass_budget(*self.mass_data())
        self.assertTrue(result['buffer_mass_equations_pass'])
        self.assertTrue(result['buffer_plus_chamber_stage_closure_pass'])

    def test_nonconserved_buffer_detected(self):
        time, buffers, chambers = self.mass_data()
        buffers[BUFFER_NAMES[0]]['mass'] += time*1e-6
        result = mass_budget(time, buffers, chambers)
        self.assertFalse(result['buffer_mass_equations_pass'])
        self.assertFalse(result['buffer_plus_chamber_stage_closure_pass'])

    def test_wrong_volume_mass_identity_rejected(self):
        time, buffers, chambers = self.mass_data(); chambers[CHAMBER_NAMES[0]]['volume'] *= .1
        with self.assertRaises(ValueError): mass_budget(time, buffers, chambers)

    def test_missing_trace_rejected(self):
        time, buffers, chambers = self.mass_data(); chambers.pop(CHAMBER_NAMES[0])
        with self.assertRaises(ValueError): mass_budget(time, buffers, chambers)

    def test_nan_buffer_rejected(self):
        time, buffers, chambers = self.mass_data(); buffers[BUFFER_NAMES[0]]['mass'][10] = np.nan
        with self.assertRaises(ValueError): mass_budget(time, buffers, chambers)


if __name__ == '__main__':
    unittest.main()
