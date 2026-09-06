import unittest
import json
import tempfile
from pathlib import Path

import h5py
import numpy as np
from scipy.interpolate import RegularGridInterpolator

from Audit_HeatDriveECC_ChamberOpenFlowResult import balance, command, read_case, temperature_coordinate_balance


class OpenFlowTests(unittest.TestCase):
    def test_native_packet_reader_has_no_analysis_side_effects(self):
        groups = dict(chamber=dict(T_I='K',p_I='Pa',rho_I='kg/m^3',u_I='J/kg',mdot_A='kg/s',mdot_B='kg/s',
                                  Phi_A='W',Phi_B='W',Q_H='W',stored_mass='kg',stored_energy='J'),
                      flow_source=dict(mdot_A='kg/s',mdot_B='kg/s',Phi_A='W',Phi_B='W',power='W'),
                      hot_reservoir=dict(mdot_A='kg/s',Phi_A='W',p_I='Pa',T_I='K'),
                      cold_reservoir=dict(mdot_A='kg/s',Phi_A='W',p_I='Pa',T_I='K'))
        def chars(parent, name, text):
            parent.create_dataset(name, data=np.array([ord(c) for c in text],dtype=np.uint16))
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)/'packet.mat'
            with h5py.File(path,'w') as f:
                chars(f,'record_json',json.dumps(dict(formulation='conservative',local_step_s=1)))
                packets = f.create_dataset('packets',(4,),dtype=h5py.ref_dtype)
                for index,(role,units) in enumerate(groups.items()):
                    block=f.create_group(role)
                    chars(block,'role',role)
                    refs=block.create_dataset('traces',(len(units),),dtype=h5py.ref_dtype)
                    for k,(name,unit) in enumerate(units.items()):
                        trace=block.create_group(name)
                        chars(trace,'name',name)
                        chars(trace,'unit',unit)
                        trace.create_dataset('time_s',data=[0,1])
                        trace.create_dataset('values',data=[1,1])
                        refs[k]=trace.ref
                    packets[index]=block.ref
            meta,time,packets=read_case(path)
            self.assertEqual(meta['formulation'],'conservative')
            np.testing.assert_array_equal(time,[0,1])
            self.assertEqual(len(packets['chamber']),11)

    def test_backward_euler_uses_signed_right_endpoint_flux(self):
        row = balance([0, 1, 2], [1, 3, 2], [100, 110, 105], [999, 2, -1], [999, 10, -5])
        self.assertTrue(row['mass_closure_pass'])
        self.assertTrue(row['energy_closure_pass'])
        self.assertEqual(row['integrated_mass_kg'], 1)

    def test_event_interval_is_not_omitted(self):
        row = balance([0, .5, 1], [1, 1, 1], [100, 110, 100], [0, 0, 0], [0, 0, 0])
        self.assertEqual(row['energy_final_residual_J'], 0)
        self.assertFalse(row['energy_closure_pass'])
        self.assertEqual(row['energy_max_abs_residual_J'], 10)

    def test_flux_sign_and_mass_leak_fail(self):
        row = balance([0, 1], [1, 2], [100, 110], [-1, -1], [-10, -10])
        self.assertFalse(row['mass_closure_pass'])
        self.assertFalse(row['energy_closure_pass'])

    def test_shape_time_and_nonfinite_rejected(self):
        for t,m in (([0,0], [1,1]), ([0,1], [1,np.nan]), ([0,1], [1]), ([0,1], [1,-1])):
            with self.assertRaises(ValueError):
                balance(t,m,[1,1],[0,0],[0,0])

    def test_reversal_includes_new_command_at_event(self):
        np.testing.assert_array_equal(command([0,.499,.5,.501,1], 'reversal', .001), [.0002,.0002,-.0002,-.0002,-.0002])
        np.testing.assert_array_equal(command([0,1], 'reverse', .001), [-.0002,-.0002])
        np.testing.assert_array_equal(command([0,1], 'forward', .001), [.0002,.0002])

    def test_unsupported_command_rejected(self):
        with self.assertRaises(ValueError):
            command([0,1], 'unknown', .001)

    def test_product_chain_rule_error_has_analytic_value(self):
        t, p = np.array([299.,301.,303.]), np.array([1e6,3e6])
        rho = np.repeat((1000-2*(t-300))[:,None], 2, axis=1)
        u = np.repeat((100000+4000*(t-300))[:,None], 2, axis=1)
        table = {k:RegularGridInterpolator((t,p),v) for k,v in dict(rho=rho,u=u).items()}
        row = temperature_coordinate_balance([0,1],[300,301],[2e6]*2,1e-6,[0,-2e-6],[0,3.784],table)
        self.assertAlmostEqual(row['endpoint_minus_temperature_coordinate_energy_J'], .008, places=12)
        self.assertLess(row['coefficient_energy_interval_max_residual_J'], 1e-12)
        self.assertFalse(row['compiler_state_selection_directly_observed'])

    def test_cell_crossing_mass_defect_is_retained(self):
        t, p = np.array([300.,301.,302.]), np.array([1e6,3e6])
        rho = np.repeat(np.array([1000.,998.,995.])[:,None], 2, axis=1)
        u = np.full_like(rho, 100000)
        table = {k:RegularGridInterpolator((t,p),v) for k,v in dict(rho=rho,u=u).items()}
        row = temperature_coordinate_balance([0,1],[300,302],[2e6]*2,1e-6,[0,-6e-6],[0,-.6],table)
        self.assertAlmostEqual(row['endpoint_minus_temperature_coordinate_mass_kg'], 1e-6, places=16)
        self.assertEqual(row['temperature_cell_change_count'], 1)
        self.assertEqual(row['temperature_cell_change_right_times_s'], [1])


if __name__ == '__main__':
    unittest.main()
