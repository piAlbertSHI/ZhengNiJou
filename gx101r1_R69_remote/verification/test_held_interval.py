import unittest
from pathlib import Path
import numpy as np
from Audit_HeatDriveECC_HeldIntervalBalance import balance, check_held_contract


class HeldIntervalTests(unittest.TestCase):
    def test_nonuniform_grid_linear_flux_is_integrated(self):
        t=np.array([0,.001,.004,.018,.04]);r=balance(t,1+t*t,2+3*t*t,2*t,6*t)
        self.assertTrue(r['mass_closure_pass']);self.assertTrue(r['energy_closure_pass'])
        self.assertFalse(r['quadrature_convergence_verified'])

    def test_unexplained_inventory_change_fails(self):
        t=np.linspace(0,.04,41);r=balance(t,1+t,2+t,np.zeros_like(t),np.zeros_like(t))
        self.assertFalse(r['mass_closure_pass']);self.assertFalse(r['energy_closure_pass'])

    def test_truncated_duplicate_or_nonfinite_history_rejected(self):
        for mode in ('end','duplicate','nan'):
            t=np.linspace(0,.04,41);m=np.ones_like(t)
            if mode=='end':t[-1]=.039
            elif mode=='duplicate':t[1]=t[0]
            else:m[0]=np.nan
            with self.assertRaises(ValueError):balance(t,m,m,m,m)

    def fixture(self):
        return dict(allowed_stop_time_s=.04,constant_interval_end_exclusive_s=.05,
                    derivative_source='heatdrive_ecc_coupled_se21/ColdHeldPressureDerivative',
                    first_derivative_MPa_s=0,feedback_enable=0,reset_held=1,
                    full_cycle_derivative_verified=False,production_recovery_allowed=False,
                    commands=[dict(time_s=[0,.05],values=[v,v],interpolate=m) for v,m in zip([-1e-6,0,1],['on','off','off'])])

    def test_held_boundaries_and_false_full_cycle_claims_rejected(self):
        check_held_contract(self.fixture())
        for key,value in [('allowed_stop_time_s',.05),('feedback_enable',1),('reset_held',0),('full_cycle_derivative_verified',True)]:
            c=self.fixture();c[key]=value
            with self.assertRaises(ValueError):check_held_contract(c)

    def test_original_initial_only_guard_is_retained(self):
        p=Path(__file__).parent
        original=(p/'Configure_HeatDriveECC_ColdInitialPressureDerivative.m').read_text(encoding='utf-8')
        self.assertIn("strcmp(get_param(model,'StopTime'),'0')",original)
        held=(p/'Configure_HeatDriveECC_HybridHeldInterval.m').read_text(encoding='utf-8')
        self.assertIn('seconds==.04',held)
        self.assertIn('8598BB08D314EA1B052C5B4CCE9A9DD7F0E30BE6842E668A038306F58E298C13',held)
