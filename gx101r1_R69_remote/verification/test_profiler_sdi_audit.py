import unittest
from copy import deepcopy
import numpy as np
from Audit_HeatDriveECC_ProfilerSDI import select_signal,resolve_namespace,kelvin_difference_alias,check_run_ownership,check_history,MODEL


class SDIAuditTests(unittest.TestCase):
    def test_full_path_required_and_ambiguity_rejected(self):
        row=dict(full_block_path='model/A',name='model.A.mass')
        self.assertEqual(select_signal([row],'model/A','mass'),row)
        with self.assertRaises(ValueError):select_signal([row],'model/B','mass')
        with self.assertRaises(ValueError):select_signal([row,dict(row,name='model.A.inner.mass')],'model/A','mass')

    def test_no_old_or_foreign_run_export(self):
        run=dict(run_id='2',model=MODEL,ownership_verified=True,exported=True,unreadable_signals=[],
            signal_count=1,scalar_count=1,non_scalar_or_empty_count=0,signal_metadata=[dict(model=MODEL)])
        sdi=dict(prior_run_ids=['1'],after_run_ids=['1','2'],prior_runs_preserved=True,export_pass=True,
            runs=[run],owned_run_count=1,scalar_signal_count=1)
        self.assertEqual(len(check_run_ownership(sdi)),1)
        for field,value in [('run_id','1'),('model','foreign'),('ownership_verified',False),('scalar_count',0)]:
            modified=deepcopy(sdi);modified['runs'][0][field]=value
            with self.assertRaises(ValueError):check_run_ownership(modified)

    def test_complete_block_namespace_disambiguates_port_temperature(self):
        catalog=[dict(full_block_path='model/A',name='model.A.'+state) for state in ('T','M.T','Q')]
        namespace=resolve_namespace(catalog,'model/A',{'T','Q'})
        self.assertEqual(namespace,'model.A')
        self.assertEqual(select_signal(catalog,'model/A','T',namespace)['name'],'model.A.T')
        with self.assertRaises(ValueError):resolve_namespace(catalog,'model/A',{'T'})
        with self.assertRaises(ValueError):resolve_namespace(catalog,'model/A',{'T','absent'})

    def test_no_incomplete_or_nonfinite_physics(self):
        check_history(dict(time_s=np.array([0,.04]),values=np.array([1,2])))
        for t,v in [([0],[1]),([0,.03],[1,2]),([0,.04],[1,np.nan]),([0,.04,.04],[1,2,3])]:
            with self.assertRaises(ValueError):check_history(dict(time_s=np.array(t),values=np.array(v)))

    def test_kelvin_alias_only_for_declared_difference_variable(self):
        source='foundation.thermal.sources.controlled_heat_flow'
        self.assertTrue(kelvin_difference_alias('deltaK','K',source,'T'))
        self.assertFalse(kelvin_difference_alias('K','K','','T'))
        for unit,kind,name in [('degC',source,'T'),('K','thermal_mass','T'),('K',source,'A.T')]:
            with self.assertRaises(ValueError):kelvin_difference_alias('deltaK',unit,kind,name)
