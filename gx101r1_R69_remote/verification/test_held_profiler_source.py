import unittest
from pathlib import Path


class HeldProfilerSourceTests(unittest.TestCase):
    def test_one_public_profiler_call_no_restart_or_state_import(self):
        source=(Path(__file__).parent/'Profile_HeatDriveECC_DeclaredHeldFailure.m').read_text(encoding='utf-8')
        self.assertEqual(source.count('solverprofiler.profileModel('),1)
        self.assertNotIn('TimeOut',source)
        self.assertNotIn('set_param(',source)
        self.assertIn("'SaveOperatingPoint','off'",source)
        self.assertIn("'full_jacobian_analyzed',false",source)
        self.assertIn("'science_gate_pass',false",source)
        self.assertIn("'SaveJacobian','on'",source)

    def test_opt_in_and_prior_failure_hash(self):
        source=(Path(__file__).parent/'Inspect_HeatDriveECC_ColdCompiledStates.m').read_text(encoding='utf-8')
        self.assertIn('if nargin<38,held_profiler=false;end',source)
        self.assertIn('(~held_profiler || held_split_tolerances)',source)
        self.assertIn('4A398B9E07CA55B2A84FEBBF440A601274BBE0102624AE0383AC39E3C6002370',source)
        self.assertIn('record.profiler_capture_pass=record.profiler.capture_pass;',source)

    def test_auto_scale_is_observed_not_changed(self):
        source=(Path(__file__).parent/'Capture_HeatDriveECC_ColdInitializationContext.m').read_text(encoding='utf-8')
        self.assertIn("record.AutoScaleAbsTol=get_param(model,'AutoScaleAbsTol');",source)
