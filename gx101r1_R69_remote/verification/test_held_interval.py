import unittest
from pathlib import Path
import numpy as np
from Audit_HeatDriveECC_HeldIntervalBalance import balance, check_held_contract
from Audit_HeatDriveECC_HybridHeldResult import expected_solver, expected_tolerances


class HeldIntervalTests(unittest.TestCase):
    def test_nonuniform_grid_linear_flux_is_integrated(self):
        t=np.array([0,.001,.004,.018,.04]);r=balance(t,1+t*t,2+3*t*t,2*t,6*t)
        self.assertTrue(r['mass_closure_pass']);self.assertTrue(r['energy_closure_pass'])
        self.assertFalse(r['quadrature_convergence_verified'])
        self.assertLess(r['simpson_mass_max_abs_residual_kg'],1e-15)
        self.assertLess(r['simpson_energy_max_abs_residual_J'],1e-8)

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

    def test_native_one_ulp_boundary_is_not_a_command_change(self):
        c=self.fixture();c['constant_interval_end_exclusive_s']=.05000000000000001
        for row in c['commands']:row['time_s'][1]=.05000000000000001
        check_held_contract(c)
        c['constant_interval_end_exclusive_s']=.05001
        with self.assertRaises(ValueError):check_held_contract(c)

    def test_step_trial_is_separate_from_physics_and_tolerance_overrides(self):
        source=(Path(__file__).parent/'Inspect_HeatDriveECC_ColdCompiledStates.m').read_text(encoding='utf-8')
        self.assertIn('if nargin<33,held_max_step=[];end',source)
        self.assertIn('ismember(held_max_step,[.0005,.00025]) && ~tighten_global && ~half_step',source)
        self.assertIn("set_param(model,'MaxStep',num2str(held_max_step,'%.17g'))",source)
        self.assertIn('record.output_sampling_settings',source)

    def test_step_audit_changes_only_declared_maximum(self):
        baseline=dict(Solver='ode15s',SolverType='Variable-step',MaxStep='0.001',InitialStep='auto')
        for case,step in [('halfstep',.0005),('quarterstep',.00025)]:
            changed=expected_solver(baseline,case)
            self.assertEqual(float(changed.pop('MaxStep')),step)
            self.assertEqual(changed,{k:v for k,v in baseline.items() if k!='MaxStep'})
        self.assertEqual(baseline['MaxStep'],'0.001')
        with self.assertRaises(ValueError):expected_solver(baseline,'unregistered')

    def test_error_control_trial_is_bounded_and_has_rejection_provenance(self):
        source=(Path(__file__).parent/'Inspect_HeatDriveECC_ColdCompiledStates.m').read_text(encoding='utf-8')
        self.assertIn('if nargin<34,held_error_control=false;end',source)
        self.assertIn('held_interval && isequal(held_max_step,.00025) && ~tighten_global',source)
        self.assertIn('6C6A9CA6885AFD49693F014F15EC66C2A39C73784A3742E2667AD705BAAAA975',source)
        self.assertIn('record.held_error_control_trial=held_error_control',source)
        self.assertIn("set_param(model,'RelTol','1e-10','AbsTol','1e-12')",source)

    def test_error_control_stagnation_is_an_error_not_endless_warning(self):
        source=(Path(__file__).parent/'Inspect_HeatDriveECC_ColdCompiledStates.m').read_text(encoding='utf-8')
        self.assertIn("set_param(model,'MinStepSizeMsg','error')",source)
        self.assertNotIn("set_param(model,'MaxConsecutiveMinStep'",source)
        self.assertIn("'pre_simulation_inspection.json'",source)
        self.assertLess(source.index("'pre_simulation_inspection.json'"),source.index('output=sim(input)'))
        self.assertIn('record.simulation_error_message=output.ErrorMessage',source)

    def test_moderate_level_is_explicit_and_retains_tight_rejection(self):
        source=(Path(__file__).parent/'Inspect_HeatDriveECC_ColdCompiledStates.m').read_text(encoding='utf-8')
        self.assertIn("if nargin<35,held_error_control_level='tight';end",source)
        self.assertIn("{'tight','moderate'}",source)
        self.assertIn('0788BA8C9DC025CA20F61894581DE40E3CEF283EE75214AF6C4E2FCD4CAA5B50',source)
        self.assertIn("set_param(model,'RelTol','1e-6','AbsTol','1e-8')",source)

    def test_moderate_audit_does_not_change_existing_step_tolerances(self):
        baseline=dict(RelTol='1e-2',AbsTol='1e-3')
        for case in ('baseline','halfstep','quarterstep'):
            self.assertEqual(expected_tolerances(baseline,case),baseline)
        self.assertEqual(expected_tolerances(baseline,'moderate_control'),dict(RelTol='1e-6',AbsTol='1e-8'))
        self.assertEqual(baseline,dict(RelTol='1e-2',AbsTol='1e-3'))
        with self.assertRaises(ValueError):expected_tolerances(baseline,'undeclared')

    def test_one_step_solver_is_separate_and_preserves_historical_default(self):
        source=(Path(__file__).parent/'Inspect_HeatDriveECC_ColdCompiledStates.m').read_text(encoding='utf-8')
        self.assertIn("if nargin<36,held_solver_method='ode15s';end",source)
        self.assertIn("held_error_control && strcmp(held_error_control_level,'moderate')",source)
        self.assertIn("set_param(model,'Solver','ode23t')",source)
        self.assertIn('48ECCCA5D663B1F423CA838D5A84F7EECD9A74D59B4564079B4F941FC8E7A2F9',source)
