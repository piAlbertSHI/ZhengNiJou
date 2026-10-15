import json
from pathlib import Path
import tempfile
import unittest

from Verify_HeatDriveECC_ObservationPacket import validate_manifest
from Analyze_HeatDriveECC_RecordedTenCycles import runtime_window
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Measure_HeatDriveECC_TargetWindow import precision


class RuntimeTcContinuationTests(unittest.TestCase):
    def manifest(self):
        t=dict(schema='heatdrive_ecc_runtime_Tc_intervention_v1',source_Tc_K=276.95,candidate_Tc_K=276.85,
            transition_time_s=280,minimum_transition_cycles=12,source_complete_OP_sha256='A'*64,
            source_qualification_sha256='B'*64,plant_recipe_sha256='C'*64,
            only_runtime_temperature_variable_changed=True,source_state_edited=False,old_model_OP_imported=False)
        return dict(schema='heatdrive_ecc_split_observation_packet_v1',window_s=[400,420],source_snapshot_s=400,
            simulation_returned_without_error=True,source_state_edited=False,history_cap_cycles=2,state_history_cap_cycles=11,
            strict_vendor_restore=True,production_recovery_allowed=False,packet_role='runtime_boundary_Tc_continuation',
            parent_complete_OP_sha256='D'*64,independent_cold_start=False,temperature_configurability='runtime',
            prescribed_Tc_K=276.85,command_horizon_cycles=200,checksum_policy='error/error',boundary_trial=t,
            continuation=dict(source_snapshot_s=400,source_OP_sha256='D'*64,source_qualification_sha256='E'*64,
                budget_stop_s=600,temperature_unchanged=True))

    def completed(self,root,count=1,passed=True):
        p=root/'origin.json';p.write_text(json.dumps(dict(window_s=[300,400],fixed_Tc_candidate=True,candidate_Tc_K=276.85,
            packets=[dict(packet_root='old'+str(k),window_s=[300+20*k,320+20*k]) for k in range(5)])))
        stop=400+20*count
        return dict(schema='heatdrive_ecc_runtime_Tc_continuation_collection_v1',collection_window_s=[400,stop],
            planned_collection_window_s=[400,600],continuation=self.manifest()['continuation'],
            **{'pass':True},total_cycles=stop/10,error_message='',source_state_edited=False,partial_state_restore_used=False,
            candidate_Tc_K=276.85,origin_measured_window_path=str(p),origin_measured_window_sha256=sha256(p),
            latest_periodicity=dict(window_s=[stop-100,stop],periodic_steady_state=True),
            latest_target_stability=dict(window_s=[stop-100,stop],precision_pass=passed),
            completed_packets=[dict(packet_root='new'+str(k),start_time_s=400+20*k,stop_time_s=420+20*k) for k in range(count)])

    def test_resume_from_current_C40_not_C28_and_later_native_windows_are_bounded(self):
        self.assertEqual(validate_manifest(self.manifest()),(400,420))
        m=self.manifest();m.update(window_s=[580,600],source_snapshot_s=580,parent_complete_OP_sha256='F'*64)
        self.assertEqual(validate_manifest(m),(580,600))
        m['packet_role']='runtime_boundary_Tc_candidate'
        with self.assertRaises(ValueError):validate_manifest(m)

    def test_no_temperature_change_parent_substitution_or_budget_override(self):
        for key,value in [('temperature_unchanged',False),('source_OP_sha256','F'*64),('budget_stop_s',800)]:
            m=self.manifest();m['continuation'][key]=value
            with self.assertRaises(ValueError):validate_manifest(m)

    def test_rolling_window_keeps_only_current_same_Tc_packets(self):
        with tempfile.TemporaryDirectory() as d:
            a,b,rows,p=runtime_window(self.completed(Path(d)))
            self.assertEqual((a,b,str(p)),(320,420,'old0'))
            self.assertEqual([r['packet_root'] for r in rows],['old1','old2','old3','old4','new0'])

    def test_early_exit_needs_both_periodic_and_precision_while_budget_exhaustion_is_not_physics_failure(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(ValueError):runtime_window(self.completed(Path(d),passed=False))
            a,b,rows,p=runtime_window(self.completed(Path(d),10,False))
            self.assertEqual((a,b,len(rows)),(500,600,5))

    def test_target_precision_is_finite_window_not_an_invented_inventory_gate(self):
        cycles=[dict(cycle=k,temperature_lift_eq9_K=k*.01,SCP_W_per_g=k*.0001) for k in range(10)]
        self.assertTrue(precision(cycles)['precision_pass'])
        cycles[-1]['temperature_lift_eq9_K']=.11
        self.assertFalse(precision(cycles)['precision_pass'])
        cycles[5]['SCP_W_per_g']=float('nan')
        with self.assertRaises(ValueError):precision(cycles)

    def test_same_Tc_first_boundary_uses_unchanged_parameter_comparison(self):
        source=(Path(__file__).parent/'Run_HeatDriveECC_RuntimeTcPackets.m').read_text()
        self.assertIn('if isempty(completed) && ~continuing',source)
        self.assertIn('if periodic && (~qualified || precision) && op.snapshotTime>=minimum_stop,break;end',source)
        self.assertIn("reference_field='plant_build_options'",source)
        self.assertNotIn("setModelParameter('StartTime'",source)

    def test_preparation_provenance_reads_the_candidate_qualification_not_an_absent_baseline_pointer(self):
        source=(Path(__file__).parent/'Run_HeatDriveECC_ColdChamberDiagnostic.m').read_text()
        self.assertIn("elseif any(strcmp(observation_options.mode,{'runtime_boundary_Tc_continuation','runtime_boundary_Tc_step'}))",source)
        self.assertIn('source_contract_sha256=file_hash(observation_options.candidate_qualification_path)',source)

    def test_shared_comparison_stop_cannot_be_shortened_or_retired_job_reused(self):
        with tempfile.TemporaryDirectory() as d:
            data=self.completed(Path(d));data['minimum_stop_time_s']=520
            with self.assertRaises(ValueError):runtime_window(data)
        source=(Path(__file__).parent/'Run_HeatDriveECC_RuntimeTcPackets.m').read_text()
        self.assertIn('COMPLETED_RAW_PREFIX_RETIRED.json',source)


if __name__=='__main__':unittest.main()
