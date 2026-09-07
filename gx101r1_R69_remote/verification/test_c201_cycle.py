import unittest
import numpy as np
from Audit_HeatDriveECC_C201Cycle import phase_axes,metrics


class C201CycleTests(unittest.TestCase):
    def test_exact_stage_boundaries(self):
        stage,elapsed=phase_axes(np.array([2000,2003.5,2005,2008.5,2010]))
        np.testing.assert_array_equal(stage,[1,2,3,4,4])
        np.testing.assert_array_equal(elapsed,[0,0,0,0,1.5])

    def test_solid_balance_and_missing_source_not_hidden(self):
        t=2000+np.arange(10001)*.001
        o={key:np.array([[value]]) for key,value in {
            'system/cp_fluid_J_per_kgK':3638,'equilibrium/m_r_kg':.04,'equilibrium/m_a_kg':.1,
            'material/SMA/cp_J_per_kgK':500,'material/SE/cp_J_per_kgK':500,
            'validation/max_energy_residual_fraction':.05,'branch/stage_command_ramp_s':.15,
            'branch/m_dot_sma_shex_kg_per_s':.05,'branch/m_dot_sma_the_kg_per_s':.05,
            'validation/max_sma_settled_flow_relative_error':.15,'validation/se_settled_guard_s':.3,
            'branch/m_dot_se_the_kg_per_s':.0032,'branch/m_dot_se_chex_kg_per_s':.0032,
            'validation/max_se_settled_flow_relative_error':.15,'validation/max_se_settled_flow_rms_relative_error':.05}.items()}
        signals={}
        for name in ('hot_hx_inlet_fluid_temp_out','cold_hx_inlet_fluid_temp_out','cold_hx_outlet_fluid_temp_out'):
            signals[name]=np.full((1,len(t)),300.)
        signals['Qdot_cold_sink_mass_to_hx_pipe_W']=np.zeros((1,len(t)))
        for name in ('mass_flow_v4_hot_inlet_kgps','mass_flow_v1_cold_inlet_kgps'):
            signals[name]=np.full((1,len(t)),.0032)
        signals['mass_flow_sma_stage13_kgps']=np.full((1,len(t)),.05)
        signals['ECC_constitutive21_output']=np.zeros((252,len(t)))
        for name in ('SMA','SE'):
            signals[name+'_Tx21_internal']=np.full((21,len(t)),300.)
            signals['ECC_Q_'+name+'_constitutive_W']=np.zeros((21,len(t)))
            for route in (['hold','cooldown'] if name=='SMA' else ['hold']):
                for n in range(1,22):
                    signals[f'{name.lower()}_{route}_node{n:02d}_heatflow_W']=np.zeros((1,len(t)))
        _,solids,_=metrics(signals,o,t)
        self.assertEqual(solids['SMA']['residual_J'],0)
        signals['ECC_Q_SMA_constitutive_W'][0]=1
        _,solids,_=metrics(signals,o,t)
        self.assertAlmostEqual(solids['SMA']['residual_J'],-10)
        self.assertFalse(solids['SMA']['selected_solid_energy_gate'])


if __name__=='__main__':
    unittest.main()
