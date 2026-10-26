"""Scope checks only; full-OP runtime and fresh-process evidence are separate."""
from pathlib import Path
import unittest


class EndpointOPTests(unittest.TestCase):
    def test_full_OP_is_untouched_and_both_checksum_policies_are_errors(self):
        root=Path(__file__).resolve().parent
        source=(root/'Verify_HeatDriveECC_SharedEndpointOP.m').read_text(encoding='utf-8')
        self.assertIn("'SaveOperatingPoint','on'",source)
        self.assertIn("'OperatingPointContentsChecksumMismatchMsg','error'",source)
        self.assertIn("'OperatingPointInterfaceChecksumMismatchMsg','error'",source)
        self.assertIn('setInitialState(loaded.diagnostic_operating_point)',source)
        self.assertNotIn('.loggedStates=',source)
        self.assertNotIn("'FixedStep',",source)
        self.assertNotIn('Build_HeatDriveECC_ColdInitialFluxCompensation',source)

    def test_command_horizon_does_not_shrink_to_the_segment_end(self):
        source=(Path(__file__).resolve().parent/'Run_HeatDriveECC_SharedSMAColdInitial.m').read_text(encoding='utf-8')
        self.assertIn('o.cycle_count=inventory.command_cycle_count',source)
        self.assertIn('inventory.command_cycle_count==100',source)
        self.assertIn("'state_interface_execution.json'",source)

    def test_rebuilt_process_loads_persisted_model_not_a_partial_builder(self):
        source=(Path(__file__).resolve().parent/'Resume_HeatDriveECC_SharedEndpointOP.m').read_text(encoding='utf-8')
        self.assertIn('load_system(prior.saved_runtime_model_path)',source)
        self.assertIn('prior.loaded_project_sources',source)
        self.assertNotIn('Build_HeatDriveECC_EighthRound_Simulink_Model(',source)
        self.assertNotIn('set_param(model,',source)
        self.assertNotIn('.loggedStates=',source)


if __name__=='__main__':unittest.main()
