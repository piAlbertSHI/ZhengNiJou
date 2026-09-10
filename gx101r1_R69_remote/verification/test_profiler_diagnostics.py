import unittest
from pathlib import Path
import numpy as np
from Audit_HeatDriveECC_ProfilerDiagnostics import history,matching_times,state_identity,inaccurate_rows,reset_interval_defects
from Audit_HeatDriveECC_HybridHeldResult import check_robust_callbacks,expected_solver,expected_tolerances


class ProfilerDiagnosticsTests(unittest.TestCase):
    def test_robust_comparison_rejects_other_changes(self):
        old=[dict(solver_iteration_options=dict(SolverResetMethod='Fast',MaxOrder=5),RelTol='1e-6') for _ in range(3)]
        new=[dict(solver_iteration_options=dict(SolverResetMethod='Robust',MaxOrder=5),RelTol='1e-6',AutoScaleAbsTol='on') for _ in range(3)]
        check_robust_callbacks(new,old)
        new[0]['RelTol']='1e-5'
        with self.assertRaises(ValueError):check_robust_callbacks(new,old)
        self.assertEqual(expected_solver(dict(Solver='ode15s',MaxStep='0.001'),'robust_reset'),dict(Solver='ode23t',MaxStep='0.00025000000000000001'))
        self.assertEqual(expected_tolerances({},'robust_reset'),dict(RelTol='1e-6',AbsTol='1e-8'))

    def test_reset_trial_is_separate_and_requires_diagnosed_evidence(self):
        source=(Path(__file__).parent/'Inspect_HeatDriveECC_ColdCompiledStates.m').read_text(encoding='utf-8')
        self.assertIn('if nargin<39,held_robust_reset=false;end',source)
        self.assertIn('~held_split_tolerances && ~held_profiler',source)
        self.assertIn('A7C46FF8CD4D6C611DFD1D8F30B2BA3EA6613FB0492D02F199A1E7DCC2C58732',source)
        self.assertEqual(source.count("set_param(model,'SolverResetMethod','Robust')"),1)

    def test_defect_attribution_does_not_move_or_discard_residuals(self):
        r=reset_interval_defects([0,.01,.02,.03],[1,1.1,1.2,1.3],[0,0,0,0],[0,.02])
        self.assertEqual(r['intervals_starting_at_reset'],2)
        self.assertAlmostEqual(r['signed_defect_sum'],.3)
        self.assertAlmostEqual(r['fraction_of_absolute_defect_after_reset'],2/3)
        self.assertTrue(r['association_only_not_causal_proof'])
        with self.assertRaises(ValueError):reset_interval_defects([0,0],[1,2],[0,0],[0])

    def test_history_must_be_finite_and_ordered(self):
        t,v=history(dict(time=[0,.04],value=[1,2]))
        np.testing.assert_array_equal(t,[0,.04])
        for time,value in [([0,.05],[1,2]),([.02,0],[1,2]),([0,.04],[1,np.nan]),([0],[1,2])]:
            with self.assertRaises(ValueError):history(dict(time=time,value=value))

    def test_sample_mapping_cannot_interpolate_or_pick_duplicates(self):
        self.assertEqual(matching_times([.02,.04],np.array([0,.02,.04])),[1,2])
        with self.assertRaises(ValueError):matching_times([.01],np.array([0,.02,.04]))
        with self.assertRaises(ValueError):matching_times([.02],np.array([0,.02,.02]))

    def test_state_requires_matching_full_block_cross_reference(self):
        s=dict(name='model.A.M',block=['model/A'])
        r=dict(states=[s],state_stats=[dict(stateName=s['name'],blockIdx=1)],
               block_stats=[dict(blockName='model/A',stateIdx=1)])
        self.assertEqual(state_identity(r,1),s)
        for index in (0,2,1.5):
            with self.assertRaises(ValueError):state_identity(r,index)
        r['block_stats'][0]['blockName']='model/B'
        with self.assertRaises(ValueError):state_identity(r,1)

    def test_cell_columns_are_reconstructed_and_extrema_checked(self):
        states=[dict(name='A',xmin=0,xmax=1),dict(name='B',xmin=2,xmax=3)]
        flat=[0,2,1,3,.1,.1,'A','B']
        self.assertEqual(inaccurate_rows(flat,states),[[0,1,.1,'A'],[2,3,.1,'B']])
        for bad in (flat[:-1],[8]+flat[1:],flat[:-1]+['C']):
            with self.assertRaises(ValueError):inaccurate_rows(bad,states)

    def test_extractor_is_version_locked_and_does_not_run_or_mutate_model(self):
        source=(Path(__file__).parent/'Export_HeatDriveECC_ProfilerDiagnosticsR2025b.m').read_text(encoding='utf-8')
        self.assertIn("version('-release'),'2025b'",source)
        self.assertIn("isequal(m.Access,'public')",source)
        self.assertIn('ids_before,Simulink.sdi.getAllRunIDs',source)
        for forbidden in ('sim(','set_param(','load_system(','profileModel(','Simulink.sdi.clear','setData('):
            self.assertNotIn(forbidden,source)
        self.assertIn("'raw_matrices_exported',false",source)
