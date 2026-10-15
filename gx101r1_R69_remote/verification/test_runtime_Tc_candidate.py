from pathlib import Path
import unittest

from Verify_HeatDriveECC_ObservationPacket import validate_manifest
from Analyze_HeatDriveECC_RecordedTenCycles import runtime_window


class RuntimeTcCandidateTests(unittest.TestCase):
    def trial(self):
        return dict(schema='heatdrive_ecc_runtime_Tc_intervention_v1',source_Tc_K=276.95,candidate_Tc_K=276.85,
            transition_time_s=280,minimum_transition_cycles=12,source_complete_OP_sha256='A'*64,
            source_qualification_sha256='B'*64,plant_recipe_sha256='C'*64,
            only_runtime_temperature_variable_changed=True,source_state_edited=False,old_model_OP_imported=False)

    def manifest(self):
        return dict(schema='heatdrive_ecc_split_observation_packet_v1',window_s=[280,300],source_snapshot_s=280,
            simulation_returned_without_error=True,source_state_edited=False,history_cap_cycles=2,state_history_cap_cycles=11,
            strict_vendor_restore=True,production_recovery_allowed=False,packet_role='runtime_boundary_Tc_candidate',
            parent_complete_OP_sha256='A'*64,independent_cold_start=False,temperature_configurability='runtime',
            prescribed_Tc_K=276.85,command_horizon_cycles=200,checksum_policy='error/error',boundary_trial=self.trial())

    def completed(self):
        return dict(schema='heatdrive_ecc_runtime_Tc_candidate_collection_v1',collection_window_s=[280,400],
            planned_collection_window_s=[280,480],boundary_trial=self.trial(),candidate_Tc_K=276.85,
            **{'pass':True},total_cycles=40,error_message='',source_state_edited=False,partial_state_restore_used=False,
            transition_excluded_from_current_window=True,
            latest_periodicity=dict(window_s=[300,400],physical_tolerances_changed=False,periodic_steady_state=True),
            completed_packets=[dict(packet_root='packet_'+str(k),start_time_s=280+20*k,stop_time_s=300+20*k) for k in range(6)])

    def test_real_declared_candidate_is_not_silently_the_old_temperature(self):
        self.assertEqual(validate_manifest(self.manifest()),(280,300))
        for key,value in [('prescribed_Tc_K',276.95),('strict_vendor_restore',False),
                          ('checksum_policy','warning/error'),('parent_complete_OP_sha256','D'*64)]:
            m=self.manifest();m[key]=value
            with self.assertRaises(ValueError):validate_manifest(m)

    def test_wide_or_undeclared_intervention_rejected(self):
        for key,value in [('candidate_Tc_K',270.),('minimum_transition_cycles',10),('old_model_OP_imported',True),
                          ('source_state_edited',True),('only_runtime_temperature_variable_changed',False)]:
            m=self.manifest();m['boundary_trial'][key]=value
            with self.assertRaises(ValueError):validate_manifest(m)

    def test_actual_candidate_window_excludes_first_two_cycles(self):
        a,b,rows,previous=runtime_window(self.completed())
        self.assertEqual((a,b),(300,400));self.assertEqual(str(previous),'packet_0')
        self.assertEqual([r['packet_root'] for r in rows],['packet_'+str(k) for k in range(1,6)])

    def test_no_borrowed_baseline_or_shortened_transition_window(self):
        for key,value in [('transition_excluded_from_current_window',False),('candidate_Tc_K',276.95),('pass',False)]:
            d=self.completed();d[key]=value
            with self.assertRaises(ValueError):runtime_window(d)
        d=self.completed();d['completed_packets'].pop();d['collection_window_s'][1]=380;d['total_cycles']=38
        with self.assertRaises(ValueError):runtime_window(d)

    def test_boundary_intervention_does_not_relax_same_parameter_bitwise_gate(self):
        source=(Path(__file__).parent/'Verify_HeatDriveECC_ObservationBoundary.m').read_text()
        self.assertIn('states.pass && native.pass && sources.pass && public.pass && memory_exact',source)
        self.assertIn('record.pass=memory_exact && retained_external && applied',source)
        self.assertIn('source_heat_impulse_independently_closed=false',source)
        writer=(Path(__file__).parent/'Collect_HeatDriveECC_ObservationPacket.m').read_text()
        self.assertIn('saved.plant_build_options=saved.options',writer)
        self.assertIn('saved.options=options',writer)
        runner=(Path(__file__).parent/'Run_HeatDriveECC_RuntimeTcPackets.m').read_text()
        self.assertIn("candidate_input=input.setVariable('cold_sink_T_init',Tc)",runner)
        self.assertIn('numel(completed)>=6',runner)
        self.assertNotIn("setModelParameter('StartTime'",runner)
        self.assertNotIn("OperatingPointContentsChecksumMismatchMsg','warning'",runner)

    def test_closeout_does_not_promote_unmatched_windows_into_an_outer_derivative(self):
        source=(Path(__file__).parent/'Close_HeatDriveECC_RuntimeTcCandidate.py').read_text()
        self.assertIn('baseline_candidate_windows_matched=False,causal_Tc_derivative_claim=False',source)
        self.assertIn('finite_window_spread_is_not_asymptotic_error_bound=True',source)
        self.assertIn('production_recovery_allowed=False,outer_solve_eligible=False',source)
        self.assertNotIn('current_runtime_boundary_warmup.json',source)


if __name__=='__main__':unittest.main()
