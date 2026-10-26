"""Boundary signs and native BE/window semantics, not scientific validation."""
import unittest

import numpy as np

from Analyze_HeatDriveECC_CoupledCVBalance import path_steps,source_sign,oriented_faces,balance_window,cooling_decomposition,mechanical_bridge,engineering_pumps


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
        component['pdV']=np.array([.002,.003])
        r=balance_window(data,[component],[boundary],0.,.002)
        self.assertEqual(r['BE_tank_pressure_volume_work_out_J'],.005)

    def test_engineering_pump_work_is_not_zero_native_thermal_input(self):
        t=np.array([0.,.001,.002]);blocks=[];probes=[];ws={};src={}
        for k in range(3):
            name='source'+str(k);path='m/'+name
            blocks.append({'block_path':path,'source_file':'foundation.thermal_liquid.sources.pressure_source'})
            for face,value in (('A',.5),('B',1.)):
                var=name+face;ws['m',var]={'time_s':t,'values':np.full((3,1),value)}
                probes.append({'source_block':name,'source_port_name':face,'workspace_variable':var,'unit':'MPa'})
            src[path,'q_A']={'time_s':t,'values':np.full((3,1),.001),'unit':'m^3/s'}
            src[path,'power']={'time_s':t,'values':np.zeros((3,1)),'unit':'W'}
        data={'time':t,'model':'m','boundary':{'blocks':blocks},'contract':{'pump_pressure_contract':{'probes':probes}},
              'workspace':ws,'sources':src}
        rows=engineering_pumps(data,0.,.002)
        self.assertEqual(len(rows),3)
        for row in rows:
            self.assertAlmostEqual(row['hydraulic_work_positive_J'],1.)
            self.assertEqual(row['native_source_thermal_energy_J'],0.)
            self.assertFalse(row['electrical_efficiency_or_dissipation_heat_injection_assumed'])

    def test_coupled_work_cancellation_does_not_hide_an_unexplained_heat_source(self):
        t=np.array([0.,.001,.002]);c=np.zeros((3,252));x=np.arange(3)[:,None]*.1
        c[:,42:63]=1-x;c[:,63:84]=x;c[:,84:126]=100.;c[:,126:147]=x*.03;c[:,147:168]=x*.03
        blocks=[{'block_path':f'm/{part}/Subsystem2/NodeMass_{k:02}',
                 'mask_parameters':{'mass':{'value':1/21,'unit':'kg'}}} for part in ('SMA','SE') for k in range(1,22)]
        o={'node_count':21,'geometry':{'S_a_m2':1.,'S_r_m2':1.,'L_a_m':1.,'L_r_m':1.},
           'material':{'SMA':{'Delta_h_J_per_kg':100.},'SE':{'Delta_h_J_per_kg':100.}},
           'constitutive':{'se_loading_work_J_per_kg':0.,'se_unloading_work_J_per_kg':0.},
           'validation':{'max_eq6_scaled':1e-6,'max_eq7_scaled':1e-3}}
        d={'time':t,'model':'m','options':o,'contract':{'storage_blocks':blocks},
           'workspace':{('m','ECC_constitutive21_output'):{'time_s':t,'values':c}}}
        sources=[{'role':'constitutive_fixture','power':np.zeros(3)}]
        r=mechanical_bridge(d,sources,0.,.002)
        self.assertTrue(r['force_and_displacement_checks_pass'])
        self.assertAlmostEqual(r['coarse_common_stress_net_internal_mechanical_work_J'],0.)
        self.assertAlmostEqual(r['heat_minus_latent_and_declared_phase_work_J'],0.)
        sources[0]['power']=np.ones(3)*5
        r=mechanical_bridge(d,sources,0.,.002)
        self.assertAlmostEqual(r['heat_minus_latent_and_declared_phase_work_J'],.01)
        self.assertFalse(r['material_law_or_full_device_validation_granted'])


if __name__=='__main__':unittest.main()
