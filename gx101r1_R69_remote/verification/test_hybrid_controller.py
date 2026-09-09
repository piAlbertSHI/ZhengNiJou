import unittest
import copy
from pathlib import Path
from Audit_HeatDriveECC_HybridColdActuation import check_hybrid_runtime

ROOT = Path(__file__).parent


class HybridControllerTests(unittest.TestCase):
    def test_integrator_and_output_law_are_unchanged(self):
        old = (ROOT/'simscape_sma_controller/+ecc_sma_controller/pressure_controller.ssc').read_text(encoding='utf-8')
        new = (ROOT/'simscape_sma_hybrid/+ecc_sma_hybrid/pressure_controller.ssc').read_text(encoding='utf-8')
        self.assertEqual(old[old.index('    pi_integrator.R == reset;'):], new[new.index('    pi_integrator.R == reset;'):])
        start = '    pi_integrator = foundation.signal.linear.integrator('
        self.assertEqual(old[old.index(start):old.index('equations\n')], new[new.index(start):new.index('equations\n')])
        start = "    kp = {-.6, 'MPa'};"
        old_parameters = old[old.index(start):old.index('components (')].replace("    initial_lag = {0, '1'};\n", '')
        self.assertEqual(old_parameters, new[new.index(start):new.index('components (')])

    def test_internal_lag_removed_not_duplicated(self):
        new = (ROOT/'simscape_sma_hybrid/+ecc_sma_hybrid/pressure_controller.ssc').read_text(encoding='utf-8')
        self.assertIn('lag == lag_input;', new)
        for forbidden in ('error_lag', 'transfer_function(', 'mdot', 'target', 'tau ='):
            self.assertNotIn(forbidden, new)

    def test_equivalence_uses_independent_state_and_no_converter_filter(self):
        runner = (ROOT/'Run_HeatDriveECC_PSControllerEquivalence.m').read_text(encoding='utf-8')
        self.assertIn('(~external_lag || ~gate_reference_reset)', runner)
        self.assertIn("lag=[model '/CandidateLag']", runner)
        self.assertIn("wire(model,[model '/Error'],1,lag,1)", runner)
        self.assertIn("'FilteringAndDerivatives','provide','UdotUserProvided','0'", runner)
        self.assertIn("'same_reference_state_used',false", runner)

    def test_coupled_adapter_requires_qualified_library_and_original_lag(self):
        adapter=(ROOT/'Configure_HeatDriveECC_ColdPassivePSObserver.m').read_text(encoding='utf-8')
        for expected in ('E2B9A87B4EA88A33C3376D11F3EE716692F5C8B7F558133E7471142CBF6A4CC9',
                         '42A1C93C7130EDCE8D85E0FD21740D81B4EEC0C6BE10A6C1B6021DBD856B4743',
                         "observer_input='lag_input'", "'Denominator','[.002 1]'",
                         'hybrid_contract.original_internal_lag_removed=true'):
            self.assertIn(expected,adapter)

    def test_coupled_trial_keeps_compile_callbacks_and_initial_only_guard(self):
        inspector=(ROOT/'Inspect_HeatDriveECC_ColdCompiledStates.m').read_text(encoding='utf-8')
        self.assertIn('if nargin<32,external_lag=false;end',inspector)
        self.assertIn('actuate_ps_output && ~tighten_global && duration==0 && capture_runtime',inspector)
        self.assertIn("record.pre_simulation_compile_callbacks=evalin('base','cold_initialization_context')",inspector)

    def runtime_fixture(self):
        p='heatdrive_ecc_coupled_se21/';lag=p+'ColdObserver_ErrorLag'
        c=dict(external_lag=True,flow_input_mode='live_external_lag',flow_value_source=lag,provided_flow_derivatives='0',
               hybrid_contract=dict(lag_path=lag,lag_numerator='1',lag_denominator='[.002 1]',normalization='1',
                                    additional_lag_state_added=False,original_internal_lag_removed=True),
               observer_solver_contract=dict(settings=dict(UseLocalSolver='off')))
        callback=dict(passive_observer_flow_input=dict(path=p+'ColdObserver_mdot_PS',Unit='1',FilteringAndDerivatives='provide',
                      UdotUserProvided='0',input_count=1,value_source=lag),
                      external_controller_lag=dict(path=lag,block_type='TransferFcn',numerator='1',denominator='[.002 1]',
                                                  input_source=p+'ColdObserver_ErrorNormalizer'),
                      passive_observer_solver=dict(copied_settings_identical=True,settings=dict(UseLocalSolver='off')),
                      pressure_converter=dict(value_source=p+'ColdObserver_pressure_Output'))
        expected=dict(lag_input=(0.,'1'),bias=(-1e-6,'MPa'),enable=(0.,'1'),reset=(1.,'1'),
                      pressure=(-1e-6,'MPa'),lag=(0.,'1'),integral=(0.,'MPa'))
        return dict(passive_ps_observer_contract=c,actual_initial_sensor_mdot_kg_s=-6e-10,
                    ps_controller_child_ids=['pi_integrator'],states=[dict(block_path=[lag],time_s=0)],
                    runtime_callbacks=[copy.deepcopy(callback)],
                    pre_simulation_compile_callbacks=[dict(copy.deepcopy(callback),stage='InitFcn',simulation_status='updating') for _ in range(2)],
                    ps_initial_actuation_contract=dict(pressure_driver=p+'ColdObserver_pressure_Output'),
                    algebraic_structure=dict(loop_count=0,loops=[],simulation_run=False),
                    ps_controller_initial=[dict(name=k,actual=v,unit=u,source_time_s=0) for k,(v,u) in expected.items()])

    def test_hybrid_runtime_contract(self):
        check_hybrid_runtime(self.runtime_fixture())

    def test_extra_state_loop_or_filter_rejected(self):
        for change in ('duplicate','internal','loop','filter','coefficient','initial'):
            r=self.runtime_fixture()
            if change=='duplicate':r['states']*=2
            elif change=='internal':r['ps_controller_child_ids'].append('error_lag')
            elif change=='loop':r['algebraic_structure']['loop_count']=1
            elif change=='filter':r['runtime_callbacks'][0]['passive_observer_flow_input']['FilteringAndDerivatives']='filter'
            elif change=='coefficient':r['runtime_callbacks'][0]['external_controller_lag']['denominator']='[.004 1]'
            else:r['ps_controller_initial'][0]['actual']=.01
            with self.subTest(change=change):
                with self.assertRaises(ValueError):check_hybrid_runtime(r)


if __name__ == '__main__':
    unittest.main()
