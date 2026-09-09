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


if __name__ == '__main__':
    unittest.main()
