import unittest
from pathlib import Path

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


if __name__ == '__main__':
    unittest.main()
