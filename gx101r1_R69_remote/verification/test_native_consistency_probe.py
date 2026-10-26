import copy
from pathlib import Path
import unittest

import numpy as np

from Analyze_HeatDriveECC_NativeConsistencyProbe import require_equal,require_numerical_change,same_cycle_schedule,active_materials_finite


class ConsistencyProbeTests(unittest.TestCase):
    def contract(self):
        before={'ConsistencyTolSource':'GLOBAL','ConsistencyAbsTol':'1e-3','ConsistencyRelTol':'1e-3',
                'ResidualTolerance':'1e-9','LocalSolverSampleTime':'.001','global_RelTol':'1e-2'}
        after=dict(before,ConsistencyTolSource='LOCAL',ConsistencyAbsTol='1e-12',ConsistencyRelTol='1e-9',ResidualTolerance='1e-12')
        return dict(profile='local_tight',old_OP_loaded=False,production_recovery_allowed=False,before=before,after=after)

    def test_only_consistency_changes_are_admitted(self):
        self.assertEqual(len(require_numerical_change(self.contract())),4)
        for key in ('LocalSolverSampleTime','global_RelTol'):
            c=self.contract();c['after'][key]='changed'
            with self.assertRaises(ValueError):require_numerical_change(c)

    def test_a_profile_name_cannot_hide_no_change_or_wrong_tolerance(self):
        c=self.contract();c['after']=copy.deepcopy(c['before'])
        with self.assertRaises(ValueError):require_numerical_change(c)
        c=self.contract();c['after']['ConsistencyRelTol']='1e-3'
        with self.assertRaises(ValueError):require_numerical_change(c)

    def test_physical_equality_is_exact_and_checks_field_coverage(self):
        a={'cp':np.array([1.,2.]),'material':{'rho':6500.}}
        require_equal(a,copy.deepcopy(a),'fixture')
        b=copy.deepcopy(a);b['cp'][1]=np.nextafter(2.,3.)
        with self.assertRaises(ValueError):require_equal(a,b,'fixture')
        with self.assertRaises(ValueError):require_equal(a,{'cp':a['cp']},'fixture')

    def test_matching_nan_means_matching_unknown_not_changed_physics(self):
        unknown=[];require_equal({'inactive':float('nan')},{'inactive':float('nan')},'fixture',unknown)
        self.assertEqual(unknown,['fixture.inactive'])
        with self.assertRaises(ValueError):require_equal(float('nan'),1.,'fixture')
        with self.assertRaises((ValueError,KeyError)):active_materials_finite({'material':{'SMA':{'rho_kg_per_m3':float('nan')}}})

    def test_only_generated_horizon_may_differ_not_period_or_stages(self):
        a={'tau_cycle_s':10.,'total_time_s':20.,'stage_end_s':np.array([3.5,5.,8.5,10.])}
        b=dict(a,total_time_s=10.)
        self.assertEqual(same_cycle_schedule(a,b,2,1)['experiment_s'],10.)
        b['stage_end_s']=np.array([3.,5.,8.5,10.])
        with self.assertRaises(ValueError):same_cycle_schedule(a,b,2,1)

    def test_runtime_probe_has_no_state_or_step_intervention(self):
        root=Path(__file__).resolve().parent
        helper=(root/'Configure_HeatDriveECC_NativeConsistencyProbe.m').read_text(encoding='utf-8')
        self.assertIn("set_param(p,'ConsistencyTolSource','LOCAL'",helper)
        self.assertNotIn("set_param(model,",helper)
        self.assertNotIn("'T0',",helper)
        self.assertNotIn('load(',helper)
        runner=(root/'Run_HeatDriveECC_SharedSMAColdInitial.m').read_text(encoding='utf-8')
        self.assertIn("if nargin<8,numerical_profile='inherited';end",runner)
        self.assertIn('cv.numerical_solver_contract=numerical',runner)


if __name__=='__main__':unittest.main()
