import json
import unittest

import numpy as np
from scipy.interpolate import RegularGridInterpolator

from Audit_HeatDriveECC_DualChamberSwitchResult import audit_case,spatial_identities


class DualRampTests(unittest.TestCase):
    def fixture(self):
        t=np.arange(1001)*.001
        full=lambda x: np.full(t.shape,x,dtype=float)
        meta=dict(formulation='conservative',power_mode='none',volume_each_m3=1.6084954386379741e-6,
                  area_m2=8.04247719318987e-6,initial_temperature_K=340,initial_pressure_Pa=2.5e6,
                  hot_reservoir_K=380,cold_reservoir_K=300,reservoir_pressure_Pa=2.5e6,pressure_step_time_s=.01,
                  command_pressure_Pa=260,route_switch_time_s=.5,stop_s=1,local_solver='NE_BACKWARD_EULER_ADVANCER',
                  global_solver='ode3',local_step_s=.001,global_step_s=.001,boundary_mode='separate_supply_return',valve_transition_s=.01)
        grid=(np.array([300.,400.]),np.array([2e6,3e6]))
        table=dict(rho=RegularGridInterpolator(grid,np.full((2,2),1000.)),
                   u=RegularGridInterpolator(grid,np.array([[100000.,100000.],[500000.,500000.]])))
        p={}
        for role in ('inlet','outlet'):
            temp=np.where(t<.5,340+4*t,342-8*(t-.5))
            u=100000+4000*(temp-300)
            m=full(meta['volume_each_m3']*1000)
            p[role]=dict(T_I=temp,p_I=full(2.5e6)+(np.where(t>=.01,260,0) if role=='outlet' else 0),
                         rho_I=full(1000),u_I=u,stored_mass=m,stored_energy=m*u,Q_H=full(0),
                         mdot_A=full(0),mdot_B=full(0),Phi_A=full(0),Phi_B=full(0))
        p['pump']=dict(mdot_A=full(0),mdot_B=full(0),Phi_A=full(0),Phi_B=full(0),power=full(0),rho_A=full(1000),rho_B=full(1000))
        for role,temp in [('inlet_reservoir',380),('outlet_reservoir',300),('hot_return',380),('cold_return',300)]:
            p[role]=dict(mdot_A=full(0),Phi_A=full(0),p_I=full(2.5e6),T_I=full(temp))
        for i in range(1,5):
            fraction=np.clip((t-.5)/.01,0,1)
            p[f'v{i}']=dict(mdot_A=full(0),mdot_B=full(0),Phi_A=full(0),Phi_B=full(0),L=1-fraction if i%2 else fraction,
                            **{'A.T':full(340),'B.T':full(340),'A.p':full(2.5e6),'B.p':full(2.5e6)})
        return meta,t,p,table

    def test_finite_audit_serializes_and_keeps_missing_energy_failure(self):
        meta,t,p,table=self.fixture()
        row=audit_case(meta,t,p,table,finite_transition=True)
        json.dumps(row,allow_nan=False)
        self.assertTrue(row['valve_command_pass'])
        self.assertTrue(row['thermal_excitation_observed'])
        self.assertFalse(row['dual_inventory_closure_pass'])
        self.assertFalse(row['ledgers']['external_table_total']['energy_closure_pass'])

    def test_table_mismatch_is_failed_gate_not_relaxed(self):
        meta,t,p,table=self.fixture()
        p['inlet']['rho_I'][501] += 1e-6
        row=audit_case(meta,t,p,table,finite_transition=True)
        self.assertFalse(row['property_table_identity_pass'])
        self.assertFalse(row['dual_inventory_closure_pass'])

    def test_separate_return_port_leak_is_observed(self):
        _,_,p,_=self.fixture()
        self.assertEqual(spatial_identities(p,'Phi',separate=True),0)
        p['hot_return']['Phi_A'][501]=1
        self.assertEqual(spatial_identities(p,'Phi',separate=True),1)


if __name__=='__main__':
    unittest.main()
