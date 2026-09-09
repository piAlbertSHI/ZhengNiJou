import copy
import unittest
from pathlib import Path
from Audit_HeatDriveECC_ColdProjectionInitialization import check_derivative, check_runtime, GLOBAL, BASE, RUNTIME_BASE, TOLERANCES


class ColdProjectionTests(unittest.TestCase):
    def contract(self):
        names=['SMA_pressure_bias_command','SMA_pressure_feedback_enable_command','SMA_pressure_feedback_reset_command']
        return dict(initialization_only=True,allowed_stop_time_s=0,constant_interval_start_s=0,
                    constant_interval_end_exclusive_s=.05,first_derivative_MPa_per_s=0,filtering='provide',
                    provided_derivatives_before='0',provided_derivatives_after='1',production_recovery_allowed=False,
                    full_cycle_derivative_verified=False,command_samples=[dict(variable=n,time_s=[0,.05],values=[v,v],interpolate=i)
                        for n,v,i in zip(names,[-1e-6,0,1],['on','off','off'])])

    def test_constant_gated_initial_interval(self):
        check_derivative(self.contract())

    def test_trajectory_filter_or_claim_rejected(self):
        for key,value in [('allowed_stop_time_s',.01),('full_cycle_derivative_verified',True),('filtering','filter'),
                          ('production_recovery_allowed',True),('first_derivative_MPa_per_s',1)]:
            c=self.contract();c[key]=value
            with self.assertRaises(ValueError):check_derivative(c)

    def test_nonconstant_reset_enable_or_interval_rejected(self):
        for index,values in [(0,[-1e-6,0]),(1,[1,1]),(2,[0,0]),(0,[float('nan')]*2)]:
            c=self.contract();c['command_samples'][index]['values']=values
            with self.assertRaises(ValueError):check_derivative(c)
        c=self.contract();c['constant_interval_end_exclusive_s']=.1
        with self.assertRaises(ValueError):check_derivative(c)

    def fixture(self):
        t=[dict(path='x',unit='K',priority='High',value=300)]
        rt=dict(RUNTIME_BASE,IndexReductionMethod='Projection');settings=dict(BASE,UseLocalSolver='off')
        r=dict(global_implicit_requested=True,projection_requested=True,global_solver_configuration=GLOBAL,
               global_tolerances_after=TOLERANCES,consistency_settings_before=BASE,consistency_settings_after=settings,
               runtime_solver_options_before=RUNTIME_BASE,runtime_solver_options_after=rt)
        for k in ('half_step_requested','disable_regularization_requested','momentum_buffers_requested','normal_mode_requested',
                  'buffer_nominal_scaling_requested','global_tolerance_override','consistency_tolerance_override','residual_tolerance_override'):r[k]=False
        r['runtime_callbacks']=[dict(stage=s,simulation_status=status,solver_settings=settings,runtime_solver_options=rt,
            global_solver_configuration=GLOBAL,**TOLERANCES,targets=t,has_private_data=False,LoadInitialState='off',
            SimscapeUseOperatingPoints='on',mode='accelerator') for s,status in [('InitFcn','initializing'),('StopFcn','terminating')]]
        return copy.deepcopy(r),t

    def test_failure_prefix_and_targets(self):
        r,t=self.fixture();check_runtime(r,t,'projection')
        r['runtime_callbacks'][0]['targets'][0]['value']=301
        with self.assertRaises(ValueError):check_runtime(r,t,'projection')

    def test_runtime_solver_change_or_false_success_prefix_rejected(self):
        r,t=self.fixture();r['runtime_callbacks'][0]['global_solver_configuration']['Solver']='ode3'
        with self.assertRaises(ValueError):check_runtime(r,t,'projection')
        r,t=self.fixture();r['runtime_callbacks'][0]['stage']='StartFcn'
        with self.assertRaises(ValueError):check_runtime(r,t,'projection')

    def test_matlab_guard_does_not_filter_or_override_value(self):
        source=(Path(__file__).parent/'Configure_HeatDriveECC_ColdInitialPressureDerivative.m').read_text(encoding='utf-8')
        self.assertIn("strcmp(get_param(model,'StopTime'),'0')",source)
        self.assertIn("set_param(converter,'UdotUserProvided','1')",source)
        for forbidden in ('save_system(', 'delete_line(', "'FilteringAndDerivatives','filter'"):
            self.assertNotIn(forbidden,source)


if __name__=='__main__':unittest.main()
