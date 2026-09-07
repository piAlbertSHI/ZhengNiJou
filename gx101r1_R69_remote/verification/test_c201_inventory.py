import unittest

import numpy as np

from Audit_HeatDriveECC_C201Inventory import ledgers,stage_totals
from test_native_inventory_catalog import tank
from test_native_window_ledger import TABLE,pipe


class C201InventoryTests(unittest.TestCase):
    def test_pipe_retains_declared_nominal_mass(self):
        row,h=ledgers(pipe(),TABLE,.001)
        self.assertEqual(h['endpoint_energy_residual_J'][-1],0)
        self.assertEqual(h['endpoint_mass_residual_kg'][-1],0)
        self.assertFalse(row['energy_closure_verified'])

    def test_tank_work_and_mean_use_actual_duration(self):
        block=tank()
        block['leaf_variables'].append(dict(name='rho_I',time_s=[0,1],values=[1000,1000],unit='kg/m^3'))
        row,h=ledgers(block,TABLE,None)
        self.assertEqual(h['endpoint_energy_residual_J'][-1],0)
        self.assertEqual(row['mass_flow_net_mean_kg_s'],1)

    def test_chamber_endpoint_not_replaced_by_coefficient(self):
        block=pipe()
        block.update(mask_type='Constant Volume Chamber (TL)',mask_parameters={'volume':{'value':1e-6,'unit':'m^3'}})
        _,h=ledgers(block,TABLE,None)
        self.assertNotEqual(h['endpoint_energy_residual_J'][-1],h['BE_coefficient_energy_residual_J'][-1])
        self.assertAlmostEqual(h['endpoint_mass_residual_kg'][-1],1e-6)

    def test_all_intervals_and_boundary_jumps_included(self):
        h={'energy':np.arange(10001,dtype=float)**2}
        rows=stage_totals(h)
        self.assertEqual(sum(r['energy'] for r in rows),1e8)
        self.assertEqual(rows[1]['energy'],5000**2-3500**2)

    def test_heat_mass_sign_and_no_latent_double_count(self):
        block=dict(block_path='test/Mass',mask_type='Thermal Mass',reference_block='test',
                   model_modes={'mass_type':'1'},mask_parameters={'mass':{'value':2,'unit':'kg'},
                   'sp_heat':{'value':500,'unit':'J/(K*kg)'}},
                   leaf_variables=[dict(name='T',time_s=[0,1],values=[300,301],unit='K'),
                                   dict(name='Q',time_s=[0,1],values=[900,900],unit='W')])
        _,h=ledgers(block,None,None)
        self.assertEqual(h['endpoint_energy_residual_J'][-1],-100)


if __name__=='__main__':
    unittest.main()
