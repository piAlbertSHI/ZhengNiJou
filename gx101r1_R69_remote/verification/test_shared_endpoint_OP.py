"""Scope checks only; full-OP runtime and fresh-process evidence are separate."""
from pathlib import Path
import unittest
import numpy as np
from HeatDriveECC_TraceColumns import scalar_text


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

    def test_MATLAB_empty_state_labels_remain_empty_not_fabricated_names(self):
        self.assertEqual(scalar_text(np.array([],dtype='U1'),True),'')
        with self.assertRaises(ValueError):scalar_text(np.array([],dtype=float),True)
        with self.assertRaises(ValueError):scalar_text(np.array(['a','b']))
        with self.assertRaises(ValueError):scalar_text('',False)

    def test_bounded_process_probe_keeps_loaded_identity_and_changes_only_logging(self):
        source=(Path(__file__).resolve().parent/'Resume_HeatDriveECC_SharedEndpointOP.m').read_text(encoding='utf-8')
        self.assertIn("input.setBlockParameter(sinks{k},'MaxDataPoints','40002')",source)
        self.assertIn('assert(strcmpi(actual,expected)',source)

    def test_bounded_epoch_is_configured_before_model_persistence_and_first_simulation(self):
        source=(Path(__file__).resolve().parent/'Verify_HeatDriveECC_SharedEndpointOP.m').read_text(encoding='utf-8')
        setup=source.index("set_param(model,'SimscapeLogLimitData','on'")
        self.assertLess(setup,source.index('save_system(model,model_file)'))
        self.assertLess(setup,source.index('reference=sim('))

    def test_long_warmup_uses_proven_epoch_and_saves_OP_before_observation_export(self):
        source=(Path(__file__).resolve().parent/'Resume_HeatDriveECC_SharedEndpointOP.m').read_text(encoding='utf-8')
        self.assertIn('proof.new_process_full_cycle_covered',source)
        self.assertIn('prior.bounded_observation_from_cold_start',source)
        self.assertIn('diagnostic_operating_point=output.interface_final_op',source)
        self.assertIn('terminal_OP_requires_scientific_review_before_continuation=true',source)
        self.assertLess(source.index("save(terminal,"),source.index('Capture_HeatDriveECC_StateInterfaceTrace('))
        self.assertNotIn('.loggedStates=',source)


if __name__=='__main__':unittest.main()
