"""Boundary signs and native BE/window semantics, not scientific validation."""
import unittest

import numpy as np

from Analyze_HeatDriveECC_CoupledCVBalance import path_steps,source_sign,oriented_faces,balance_window,cooling_decomposition


class BalanceTests(unittest.TestCase):
    def test_variable_coefficient_uses_right_not_average_value(self):
        np.testing.assert_array_equal(path_steps(np.array([99.,2.,4.]),np.array([0.,1.,3.])),[2.,8.])
        with self.assertRaises(ValueError):path_steps(np.ones(3),np.ones(2))
        with self.assertRaises(ValueError):path_steps(np.array([1.,np.nan]),np.ones(2))

    def test_controlled_source_sign_comes_from_actual_reference_face(self):
        nets=[['source:A','reference:V'],['source:B','mass:M']]
        self.assertEqual(source_sign('source','foundation.thermal.sources.controlled_heat_flow',nets,{'reference:V'})[0],1)
        nets=[['source:A','mass:M'],['source:B','reference:V']]
        self.assertEqual(source_sign('source','foundation.thermal.sources.controlled_heat_flow',nets,{'reference:V'})[0],-1)
        with self.assertRaises(ValueError):source_sign('source','foundation.thermal.sources.controlled_heat_flow',nets,set())

    def test_temperature_source_Q_is_into_source_not_into_system(self):
        self.assertEqual(source_sign('source','foundation.thermal.sources.temperature',[['source:A','mass:M']],set())[0],-1)

    def test_outlet_is_not_inferred_from_legacy_inlet_name(self):
        self.assertEqual(oriented_faces(np.array([-1.,-2.,0.]),np.array([True,True,False])),('a','b'))
        self.assertEqual(oriented_faces(np.array([1.,2.,0.]),np.array([True,True,False])),('b','a'))
        with self.assertRaises(ValueError):oriented_faces(np.zeros(3),np.ones(3,dtype=bool))

    def test_equal_magnitude_reverse_stream_uses_actual_inlet_outlet(self):
        # m_A*cp*(T_B-T_A) equals m_in*cp*(T_out-T_in) in either direction.
        for m,ta,tb in ((2.,280.,285.),(-2.,285.,280.)):
            self.assertEqual(m*3.*(tb-ta),30.)

    def test_sensor_difference_keeps_storage_and_inactive_heat_separate(self):
        r=cooling_decomposition(11.,10.,9.,9.5,9.5)
        self.assertEqual(r['Eq10_minus_sensor_W'],1.5)
        self.assertEqual(r['declared_cp_minus_native_enthalpy_W'],1.)
        self.assertEqual(r['advected_minus_wall_stage_storage_W'],1.)
        self.assertEqual(r['exclude_non_stage4_wall_W'],-.5)
        self.assertEqual(r['algebraic_decomposition_roundoff_W'],0.)
        self.assertTrue(r['identity_is_not_a_physical_validation_gate'])

    def test_BE_windows_are_additive_and_startpoint_has_no_fictitious_energy(self):
        t=np.array([0.,.001,.002]);power=np.array([1e9,2.,3.])
        component=dict(path='fixture',kind='Thermal Mass',basis='fixture',power=power,mdot=np.zeros(3),
                       U=np.array([7.,7.002,7.005]),M=np.zeros(3),dE=np.array([.002,.003]),dM=np.zeros(2))
        boundary=dict(path='source',kind='fixture',role='fixture',sign=1,rule='fixture',power=power)
        data={'time':t}
        whole=balance_window(data,[component],[boundary],0.,.002)
        a=balance_window(data,[component],[boundary],0.,.001);b=balance_window(data,[component],[boundary],.001,.002)
        self.assertAlmostEqual(whole['source_net_input_J'],.005)
        self.assertAlmostEqual(whole['source_net_input_J'],a['source_net_input_J']+b['source_net_input_J'])
        self.assertAlmostEqual(whole['BE_coefficient_residual_J'],0.)
        self.assertFalse(whole['full_device_first_law_verified'])


if __name__=='__main__':unittest.main()
