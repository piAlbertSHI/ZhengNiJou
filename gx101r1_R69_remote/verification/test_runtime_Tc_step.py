from pathlib import Path
import unittest

from HeatDriveECC_RuntimeTcTrial import validate_trial
from Verify_HeatDriveECC_ObservationPacket import validate_manifest
from Analyze_HeatDriveECC_RecordedTenCycles import runtime_window
import test_runtime_Tc_candidate as base


class RuntimeTcStepTests(unittest.TestCase):
    def trial(self):
        t=base.RuntimeTcCandidateTests().trial()
        t.update(schema='heatdrive_ecc_runtime_Tc_intervention_v2',source_Tc_K=276.85,
            candidate_Tc_K=274.85,transition_time_s=520,search_policy=dict(
                schema='heatdrive_ecc_runtime_Tc_bounded_search_v1',minimum_Tc_K=255.05,
                maximum_Tc_K=393.15,maximum_step_K=2,fluid_minimum_K=255.05,fluid_maximum_K=393.15,
                source_public_periodic_pass=True,source_target_precision_pass=True))
        return t

    def manifest(self):
        m=base.RuntimeTcCandidateTests().manifest()
        m.update(boundary_trial=self.trial(),window_s=[520,540],source_snapshot_s=520,prescribed_Tc_K=274.85)
        return m

    def test_real_step_has_a_new_schema_and_keeps_old_probe_limit(self):
        self.assertEqual(validate_manifest(self.manifest()),(520,540))
        t=self.trial();t['schema']='heatdrive_ecc_runtime_Tc_intervention_v1'
        with self.assertRaises(ValueError):validate_trial(t)

    def test_no_large_step_changed_physics_scope_or_unqualified_source(self):
        for key,value in [('candidate_Tc_K',274.8),('candidate_Tc_K',float('nan')),
                ('source_state_edited',True),('old_model_OP_imported',True),('transition_time_s',400)]:
            t=self.trial();t[key]=value
            with self.assertRaises(ValueError):validate_trial(t)
        for key,value in [('minimum_Tc_K',240.15),('maximum_step_K',10),('source_public_periodic_pass',False),
                ('source_target_precision_pass',False),('source_target_precision_pass',1)]:
            t=self.trial();t['search_policy'][key]=value
            with self.assertRaises(ValueError):validate_trial(t)

    def test_domain_not_arbitrarily_capped_at_ambient_temperature(self):
        t=self.trial();t.update(source_Tc_K=303.15,candidate_Tc_K=305.15)
        validate_trial(t)
        for source,target in [(255.05,254.05),(393.15,394.15)]:
            t.update(source_Tc_K=source,candidate_Tc_K=target)
            with self.assertRaises(ValueError):validate_trial(t)

    def completed(self):
        d=base.RuntimeTcCandidateTests().completed()
        d.update(boundary_trial=self.trial(),collection_window_s=[520,640],planned_collection_window_s=[520,720],
            candidate_Tc_K=274.85,total_cycles=64,target_precision_required=True,
            latest_periodicity=dict(window_s=[540,640],physical_tolerances_changed=False,periodic_steady_state=True),
            latest_target_stability=dict(window_s=[540,640],precision_pass=True),
            completed_packets=[dict(packet_root='p'+str(k),start_time_s=520+20*k,stop_time_s=540+20*k) for k in range(6)])
        return d

    def test_no_borrowed_source_window_or_early_exit_without_target_precision(self):
        d=self.completed();self.assertEqual(runtime_window(d)[:2],(540,640))
        d['latest_target_stability']['precision_pass']=False
        with self.assertRaises(ValueError):runtime_window(d)
        d=self.completed();d['latest_target_stability']['window_s']=[420,520]
        with self.assertRaises(ValueError):runtime_window(d)

    def test_stable_source_and_first_external_boundary_are_required_without_model_reset(self):
        root=Path(__file__).parent
        runner=(root/'Run_HeatDriveECC_RuntimeTcPackets.m').read_text()
        self.assertIn('if isempty(completed) && ~continuing',runner)
        self.assertIn('q.bounded_outer_metric_sampling_allowed',runner)
        self.assertIn("'source_Tc_K',source.Tc_K",runner)
        self.assertIn('if continuing,history=origin_index;else,history=[];end',runner)
        self.assertNotIn("setModelParameter('StartTime'",runner)
        self.assertIn("isequal(candidate_index.window_s(:),[source.snapshot_s-100;source.snapshot_s])",runner)

    def test_superseded_raw_retirement_keeps_events_all_OPs_and_current_qualified_inputs(self):
        source=(Path(__file__).parent/'Retire_HeatDriveECC_RuntimeTcSupersededRaw.ps1').read_text()
        self.assertIn('Select-Object -Skip 1',source)
        self.assertIn("@('native\\observations.mat','observed_states.mat')",source)
        self.assertLess(source.index('$protected.Contains($path)'),source.index('Remove-Item -LiteralPath $target.path'))
        self.assertIn('ReparsePoint',source)
        self.assertIn('COMPLETED_RAW_PREFIX_RETIRED.json',source)
        self.assertIn('old_qualifications_now_historical_not_full_raw_reverifiable=$true',source)
        self.assertNotIn('Remove-Item -Recurse',source)


if __name__=='__main__':unittest.main()
