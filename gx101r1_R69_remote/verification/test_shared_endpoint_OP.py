"""Scope checks only; full-OP runtime and fresh-process evidence are separate."""
from pathlib import Path
import unittest
import numpy as np
from HeatDriveECC_TraceColumns import scalar_text
from Analyze_HeatDriveECC_SharedEndpointWarmup import actual_native_window,periodic_screens,matlab_metadata
from Analyze_HeatDriveECC_CoupledCVTrajectories import stage_coordinates


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
        self.assertIn('load_system(runtime.saved_runtime_model_path)',source)
        self.assertIn('runtime.loaded_project_sources',source)
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
        self.assertIn('runtime.bounded_observation_from_cold_start',source)
        self.assertIn('diagnostic_operating_point=output.interface_final_op',source)
        self.assertIn('terminal_OP_requires_scientific_review_before_continuation=true',source)
        self.assertLess(source.index("save(terminal,"),source.index('Capture_HeatDriveECC_StateInterfaceTrace('))
        self.assertNotIn('.loggedStates=',source)

    def test_logging_parameter_accepts_documented_numeric_or_character_storage(self):
        source=(Path(__file__).resolve().parent/'Resume_HeatDriveECC_SharedEndpointOP.m').read_text(encoding='utf-8')
        self.assertIn("numeric_parameter(get_param(model,'SimscapeLogDataHistory'))",source)
        self.assertIn('if ischar(v) || isstring(v),v=str2double(v);end',source)
        self.assertIn("validateattributes(v,{'numeric'},{'scalar','real','finite'})",source)

    def test_warmup_keeps_actual_samples_and_rejects_a_missing_endpoint(self):
        clock=np.arange(20001)*.001+380
        row={'time_s':clock,'values':clock[:,None],'unit':'K'}
        result=actual_native_window({('m','T'):row},380,400)['m','T']
        np.testing.assert_array_equal(result['values'],row['values'])
        row['time_s']=clock[:-1];row['values']=row['values'][:-1]
        with self.assertRaises(ValueError):actual_native_window({('m','T'):row},380,400)

    def test_fixed_horizon_endpoint_is_preserved_but_not_a_third_settled_cycle(self):
        time=np.arange(380000,400001)*.001
        options={'cycle_count':100,'schedule':{'tau_cycle_s':10,
            'stage_start_s':[0,2.5,5,7.5],'stage_end_s':[2.5,5,7.5,10]}}
        cycle,stage,elapsed=stage_coordinates(time,options)
        self.assertEqual(cycle[-1],41);self.assertEqual(stage[-1],1)
        core=(elapsed>=.1)&(elapsed<=2.4)
        self.assertEqual(sorted(set(cycle[core].tolist())),[39,40])

    def test_small_endpoint_drift_does_not_override_failed_same_phase_RMS(self):
        d={'all_native_temperature_C2_drift_K':{'endpoint_max_abs':.001,'same_phase_max_abs':.02,
            'same_phase_p99_abs':.02,'same_phase_RMS':.02},
            'phase_C2_drift':{'endpoint_max_abs':.00001,'same_phase_p99_abs':.0001,'same_phase_RMS':.0001}}
        v={'max_periodic_endpoint_drift_K':.05,'max_periodic_same_phase_temperature_drift_K':.05,
           'max_periodic_same_phase_temperature_p99_drift_K':.05,'max_periodic_same_phase_temperature_rms_drift_K':.01,
           'max_periodic_phase_drift':.0001,'max_periodic_same_phase_phase_p99_drift':.002,
           'max_periodic_same_phase_phase_rms_drift':.0004}
        screens=periodic_screens(d,v)
        self.assertTrue(screens['temperature_endpoint']);self.assertFalse(screens['temperature_RMS'])
        self.assertFalse(all(screens.values()))

    def test_MAT_metadata_arrays_are_lists_without_touching_observation_packets(self):
        row={'vertex_indices':np.array([1,2]),'source_file':np.array([],dtype='U1'),
             'grid':np.array([[1.,2.],[3.,4.]])}
        self.assertEqual(matlab_metadata(row),{'vertex_indices':[1,2],'source_file':'','grid':[[1.,2.],[3.,4.]]})

    def test_warmup_audit_requires_real_packet_coverage_through_the_terminal_window(self):
        source=(Path(__file__).resolve().parent/'Analyze_HeatDriveECC_SharedEndpointWarmup.py').read_text(encoding='utf-8')
        self.assertIn("r['actual_tout_first_s']>=window_start",source)
        self.assertIn("for packet_name in ('workspace_packet','source_packet','state_packet')",source)
        self.assertIn("max(float(x['time_s'][-1]) for x in packet.values())<window_stop",source)

    def test_C60_continuation_is_anchored_to_the_reviewed_C40_terminal_OP(self):
        source=(Path(__file__).resolve().parent/'Resume_HeatDriveECC_SharedEndpointOP.m').read_text(encoding='utf-8')
        self.assertIn("warmup_C60_from_C40",source)
        self.assertIn("review.completed_total_cycles==40",source)
        self.assertIn("point_path=prior.terminal_OP_path",source)
        self.assertIn("point_snapshot=prior.terminal_OP_snapshot_s",source)
        self.assertIn("stop=600",source)


if __name__=='__main__':unittest.main()
