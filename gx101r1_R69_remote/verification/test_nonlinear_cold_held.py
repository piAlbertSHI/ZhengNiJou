import unittest
from copy import deepcopy
from unittest.mock import patch
import numpy as np
from Audit_HeatDriveECC_NonlinearColdHeld import coordinate_identity,check_callbacks


class NonlinearHeldTests(unittest.TestCase):
    def test_normalized_saved_coordinate(self):
        saved=dict(time_s=[0,.01,.04],data=[0,1e-8,3e-8],label='CSTATE')
        self.assertEqual(coordinate_identity(np.array(saved['time_s']),saved,np.array(saved['data'])*10,10),0)

    def test_wrong_nominal_rejected(self):
        saved=dict(time_s=[0,.01,.04],data=[0,1e-8,3e-8],label='CSTATE')
        with self.assertRaises(ValueError):coordinate_identity(np.array(saved['time_s']),saved,np.array(saved['data'])*10,1)

    def test_wrong_time_or_label_rejected(self):
        saved=dict(time_s=[0,.02,.04],data=[0,1,2],label='CSTATE')
        with self.assertRaises(ValueError):coordinate_identity(np.array([0,.01,.04]),saved,[0,1,2],1)
        saved['label']='DSTATE'
        with self.assertRaises(ValueError):coordinate_identity(np.array(saved['time_s']),saved,[0,1,2],1)

    def test_callbacks_preserve_all_nonwindow_fields(self):
        digest='8598BB08D314EA1B052C5B4CCE9A9DD7F0E30BE6842E668A038306F58E298C13'
        held=dict(allowed_stop_time_s=.04,constant_interval_end_exclusive_s=.05,
            derivative_source='heatdrive_ecc_coupled_se21/ColdHeldPressureDerivative',first_derivative_MPa_s=0,
            feedback_enable=0,reset_held=1,full_cycle_derivative_verified=False,production_recovery_allowed=False,
            state_imported=False,qualification_path='proof.json',qualification_sha256=digest,
            commands=[dict(time_s=[0,.05],values=[v,v],interpolate=m) for v,m in [(-1e-6,'on'),(0,'off'),(1,'off')]])
        prior=[dict(pressure_converter=dict(StopTime='0',derivative_source='initial'),controller_gain=1) for _ in range(3)]
        current=deepcopy(prior)
        for c in current:
            c['pressure_converter']=dict(StopTime='0.04',derivative_source=held['derivative_source'])
            c['held_interval_contract']={k:v for k,v in held.items() if k not in ('state_imported','qualification_path','qualification_sha256')}
        with patch('Audit_HeatDriveECC_NonlinearColdHeld.sha256',return_value=digest):
            check_callbacks(current,prior,held)
            current[-1]['controller_gain']=2
            with self.assertRaises(ValueError):check_callbacks(current,prior,held)


if __name__=='__main__':unittest.main()
