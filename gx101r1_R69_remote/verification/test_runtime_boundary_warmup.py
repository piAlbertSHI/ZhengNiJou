from pathlib import Path
import unittest

from Verify_HeatDriveECC_ObservationPacket import validate_manifest
from Analyze_HeatDriveECC_RecordedTenCycles import runtime_window


class RuntimeBoundaryWarmupTests(unittest.TestCase):
    def manifest(self):
        return dict(schema='heatdrive_ecc_split_observation_packet_v1',window_s=[20,40],source_snapshot_s=20,
            simulation_returned_without_error=True,source_state_edited=False,history_cap_cycles=2,state_history_cap_cycles=11,
            strict_vendor_restore=True,production_recovery_allowed=False,packet_role='runtime_boundary_transient',
            parent_complete_OP_sha256='A'*64,independent_cold_start=False,temperature_configurability='runtime',
            prescribed_Tc_K=276.95,command_horizon_cycles=200,checksum_policy='error/error')

    def test_same_runtime_complete_packet_accepted(self):
        self.assertEqual(validate_manifest(self.manifest()),(20,40))

    def test_temperature_or_family_change_is_not_silently_a_warmup(self):
        for key,value in [('prescribed_Tc_K',276.85),('temperature_configurability','compiletime'),
                          ('command_horizon_cycles',100),('checksum_policy','warning/error'),('independent_cold_start',True)]:
            m=self.manifest();m[key]=value
            with self.assertRaises(ValueError):validate_manifest(m)

    def test_time_origin_horizon_and_parent_are_bound(self):
        for key,value in [('source_snapshot_s',0),('window_s',[20,30]),('window_s',[2000,2020]),('parent_complete_OP_sha256','')]:
            m=self.manifest();m[key]=value
            with self.assertRaises(ValueError):validate_manifest(m)

    def test_warmup_uses_shared_recipe_and_shared_gated_collector(self):
        source=(Path(__file__).parent/'Run_HeatDriveECC_RuntimeBoundaryWarmup.m').read_text()
        self.assertIn('Prepare_HeatDriveECC_RuntimeFamilyRecipe',source)
        self.assertIn('Test_HeatDriveECC_RuntimeWarmupPolicy',source)
        cold=(Path(__file__).parent/'Run_HeatDriveECC_ColdChamberDiagnostic.m').read_text()
        self.assertIn("elseif strcmp(observation_options.mode,'runtime_boundary_warmup')",cold)
        self.assertIn('record.runtime_boundary_warmup=Run_HeatDriveECC_BoundedObservationPackets',cold)

    def test_source_types_are_not_mainline_or_old_family_aliases(self):
        source=(Path(__file__).parent/'Require_HeatDriveECC_RuntimeRecordingSource.m').read_text()
        self.assertIn("'heatdrive_ecc_runtime_boundary_cold_endpoint_v1'",source)
        self.assertIn("'heatdrive_ecc_runtime_boundary_warmup_endpoint_v1'",source)
        self.assertIn('~q.old_model_OP_imported',source)

    def completed(self):
        return dict(schema='heatdrive_ecc_runtime_boundary_transient_collection_v1',collection_window_s=[20,220],
            **{'pass':True},total_cycles=22,error_message='',source_state_edited=False,
            partial_state_restore_used=False,completed_packets=[dict(start_time_s=20+20*k,stop_time_s=40+20*k,
                packet_root='packet_'+str(k)) for k in range(10)])

    def test_current_ten_cycle_window_is_not_hardcoded_to_old_C72(self):
        start,stop,selected,previous=runtime_window(self.completed())
        self.assertEqual((start,stop,len(selected)),(120,220,5))
        self.assertEqual(str(previous),'packet_4')

    def test_missing_or_incomplete_warmup_cannot_supply_current_window(self):
        for key,value in [('pass',False),('total_cycles',23),('error_message','physical failure')]:
            data=self.completed();data[key]=value
            with self.assertRaises(ValueError):runtime_window(data)
        data=self.completed();data['completed_packets'].pop()
        with self.assertRaises(ValueError):runtime_window(data)

    def test_unsteady_qualification_stays_transient_and_retirement_cannot_delete_dependencies(self):
        source=(Path(__file__).parent/'Close_HeatDriveECC_RuntimeWarmup.py').read_text()
        self.assertIn('transient_continuation_allowed=True',source)
        self.assertIn("original_public_thermal_periodic_pass=statistics['statistics']['periodic_steady_state']",source)
        self.assertIn('Never retire qualified current-window dependencies',source)
        self.assertIn("'all_twenty_cycle_metrics.json'",source)

    def test_completed_retired_job_cannot_restart_in_place(self):
        source=(Path(__file__).parent/'Run_HeatDriveECC_BoundedObservationPackets.m').read_text()
        self.assertIn('COMPLETED_RAW_PREFIX_RETIRED.json',source)
        self.assertIn('use its latest qualified runtime endpoint in a new collection',source)

    def test_future_endpoint_promotion_is_atomic_and_bound_to_its_origin(self):
        source=(Path(__file__).parent/'Close_HeatDriveECC_RuntimeWarmup.py').read_text()
        self.assertIn("sha256(pointer)!=result['origin_snapshot_sha256']",source)
        self.assertIn('temporary.replace(pointer)',source)
        self.assertIn('retired completed jobs cannot be resealed from missing raw',source)


if __name__=='__main__':unittest.main()
