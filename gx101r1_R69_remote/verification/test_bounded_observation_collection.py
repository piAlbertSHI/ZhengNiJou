from pathlib import Path
import re
import subprocess
import unittest

from Verify_HeatDriveECC_ObservationPacket import validate_manifest


class BoundedObservationCollectionTests(unittest.TestCase):
    def manifest(self):
        return dict(schema='heatdrive_ecc_split_observation_packet_v1',window_s=[640,660],
            simulation_returned_without_error=True,source_state_edited=False,history_cap_cycles=2,
            state_history_cap_cycles=11,strict_vendor_restore=True,production_recovery_allowed=False,
            packet_role='bounded_transient_observation',parent_complete_OP_sha256='A'*64)

    def test_bounded_packet_keeps_source_hash(self):
        self.assertEqual(validate_manifest(self.manifest()),(640,660))

    def test_missing_parent_hash_rejected(self):
        value=self.manifest();value.pop('parent_complete_OP_sha256')
        with self.assertRaises(ValueError):validate_manifest(value)

    def test_past_sealed_boundary_rejected(self):
        value=self.manifest();value['window_s']=[720,740]
        with self.assertRaises(ValueError):validate_manifest(value)

    def test_short_unapproved_packet_rejected(self):
        value=self.manifest();value['window_s']=[640,650]
        with self.assertRaises(ValueError):validate_manifest(value)

    def test_measured_execution_section_is_identical_to_qualified_writer(self):
        root=Path(__file__).resolve().parents[2]
        original=subprocess.check_output(['git','show',
            '31e948e:gx101r1_R69_remote/verification/Verify_HeatDriveECC_SplitObservation.m'],cwd=root).decode('utf-8')
        shared=(Path(__file__).parent/'Collect_HeatDriveECC_ObservationPacket.m').read_text(encoding='utf-8')
        def section(value):
            return re.sub(r'\s+','',value[value.index('output=sim('):value.index('manifest=struct(')])
        expected=section(original).replace('fullfile(folder,','fullfile(prepared_folder,')
        self.assertEqual(expected,section(shared))

    def test_no_timer_or_state_reconstruction_in_collector(self):
        source=(Path(__file__).parent/'Run_HeatDriveECC_BoundedObservationPackets.m').read_text(encoding='utf-8')
        self.assertIn('channel.tryLock()',source)
        self.assertIn('Explicit diagnosis/resume',source)
        self.assertNotIn('pause(',source)
        self.assertNotIn('loggedStates=',source)
        self.assertNotIn('setVariable(',source)

    def test_gated_boundary_precedes_checkpoint_registration(self):
        source=(Path(__file__).parent/'Run_HeatDriveECC_BoundedObservationPackets.m').read_text(encoding='utf-8')
        self.assertLess(source.index('boundary=Verify_HeatDriveECC_ObservationBoundary'),source.index('completed{end+1}'))
        self.assertIn('manifest.parent_complete_OP_sha256,parent_hash',source)

    def test_retained_memory_join_is_not_opaque_joint_norm(self):
        source=(Path(__file__).parent/'Verify_HeatDriveECC_ObservationBoundary.m').read_text(encoding='utf-8')
        self.assertIn('nnz(selected)==4',source)
        self.assertIn('row.bitwise_values_equal',source)
        self.assertNotIn('norm(',source)


if __name__=='__main__':unittest.main()
