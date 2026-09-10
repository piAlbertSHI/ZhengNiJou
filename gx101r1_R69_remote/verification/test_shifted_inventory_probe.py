import unittest
import numpy as np
from Audit_HeatDriveECC_ShiftedInventoryProbe import balance,undo_translation
from Audit_HeatDriveECC_ResetCoordinatePackage import fine_step_evidence
from Audit_HeatDriveECC_AnalyticResetProbe import exact_solution


class ShiftedProbeTests(unittest.TestCase):
    def fixture(self):
        t=np.linspace(0,.04,161)
        data={'stored_mass':.1+1e-6*t,'stored_energy':100+2*t,
              'mdot_A':np.full_like(t,1e-6),'Phi_A':np.ones_like(t),'Q_H':np.ones_like(t)}
        return {k:dict(time_s=t,values=v) for k,v in data.items()}

    def test_conservation(self):
        b,_,_=balance(self.fixture())
        self.assertTrue(all(v['passed'] for v in b.values()))

    def test_drift_fails_original_gate(self):
        rows=self.fixture();rows['stored_mass']['values'][-1]+=1e-12
        b,_,_=balance(rows);self.assertFalse(b['stored_mass']['passed'])

    def test_sampling_and_nan_rejected(self):
        rows=self.fixture();rows['Phi_A']['values'][0]=np.nan
        with self.assertRaises(ValueError):balance(rows)

    def test_missing_transform_rejected(self):
        with self.assertRaises(ValueError):undo_translation('der(mass_delta) == flow;')

    def test_event_side_failure_is_not_promoted_to_pass(self):
        t=np.array([0.,.013999999999999756,.014,.04]);y=exact_solution(t,True)
        f=1+2*t+.001*np.floor(t/.001+1e-12);f[1]-=.001
        case=dict(time_s=t,inventory=y,logged_flux=f,forcing='sampled',analytic_inventory=y,
                  max_abs_analytic_error=0.,reset_method='Fast',initial_step_setting='auto')
        audit=fine_step_evidence(case)
        self.assertFalse(audit['evidence_audit_pass'])
        self.assertFalse(audit['coupled_fine_step_trial_qualified'])
        self.assertEqual(len(audit['mismatches']),1)


if __name__=='__main__':unittest.main()
