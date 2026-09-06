import unittest

import numpy as np

from Audit_HeatDriveECC_DualPipeResult import momentum_audit
from Audit_HeatDriveECC_DualChamberSwitchResult import audit_case
import test_dual_chamber_ramp as ramp_tests


class DualPipeTests(unittest.TestCase):
    def fixture(self):
        meta,t,p,table=ramp_tests.DualRampTests().fixture()
        meta['pipe_contract']={'diagnostic_test_fixture':True}
        for role in ('inlet','outlet'):
            v=p[role]
            for side,loss in [('A',50.),('B',-50.)]:
                v[f'{side}.p']=v['p_I']+loss
                v[f'{side}.T']=v['T_I'].copy()
                v[f'pressure_loss_{side}']=np.full(t.shape,loss)
        # The source pressure is between pipe ports, not pipe centers.
        p['outlet']['A.p']=p['inlet']['B.p']+np.where(t>=.01,260.,0.)
        p['outlet']['pressure_loss_A']=p['outlet']['A.p']-p['outlet']['p_I']
        for i in (1,2):
            p[f'v{i}']['B.p']=p['inlet']['A.p'].copy()
        for i in (3,4):
            p[f'v{i}']['A.p']=p['outlet']['B.p'].copy()
        return meta,t,p,table

    def test_pressure_losses_and_connections_detect_tampering(self):
        _,_,p,_=self.fixture()
        self.assertTrue(momentum_audit(p)['momentum_pressure_pass'])
        p['inlet']['pressure_loss_A'][500]+=1
        self.assertFalse(momentum_audit(p)['momentum_pressure_pass'])

    def test_port_pressure_not_internal_pressure_drives_source_contract(self):
        meta,t,p,table=self.fixture()
        p['outlet']['p_I'][10:]-=30
        row=audit_case(meta,t,p,table,finite_transition=True,pipe_model=True)
        self.assertTrue(row['pump_mode_formula_pass'])
        p['outlet']['A.p'][500]+=1
        with self.assertRaises(ValueError):
            audit_case(meta,t,p,table,finite_transition=True,pipe_model=True)

    def test_hard_switch_is_not_accepted_as_ramp(self):
        meta,t,p,table=self.fixture()
        meta['valve_transition_s']=0
        row=audit_case(meta,t,p,table,finite_transition=True,pipe_model=True)
        self.assertFalse(row['valve_command_pass'])
        for i in range(1,5):
            f=(t>=.5).astype(float)
            p[f'v{i}']['L']=1-f if i%2 else f
        row=audit_case(meta,t,p,table,finite_transition=True,pipe_model=True)
        self.assertTrue(row['valve_command_pass'])
        self.assertFalse(row['dual_inventory_closure_pass'])

    def test_pipe_domain_remains_strict(self):
        _,_,p,_=self.fixture()
        p['inlet']['A.T'][500]=270
        with self.assertRaises(ValueError):
            momentum_audit(p)


if __name__=='__main__':
    unittest.main()
