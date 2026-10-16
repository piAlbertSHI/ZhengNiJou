import json
from pathlib import Path
import tempfile
import unittest

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Verify_HeatDriveECC_ObservationPacket import timing_evidence


class PacketTimingTests(unittest.TestCase):
    def test_historical_packets_need_no_new_timing_or_replay(self):
        self.assertIsNone(timing_evidence(Path('not-read'),{}))

    def fixture(self,root,available):
        path=root/'simulation_timing.json'
        data=dict(schema='heatdrive_ecc_packet_simulation_timing_v1',window_s=[720,740],
            sim_call_wall_s=600,metadata_available=available,timing_is_physical_gate=False,
            simulation_settings_changed=False,source_state_edited=False)
        path.write_text(json.dumps(data))
        return path,data,dict(window_s=[720,740],simulation_timing_sha256=sha256(path))

    def test_missing_vendor_metadata_is_not_a_physics_failure(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);_,_,manifest=self.fixture(root,False)
            self.assertFalse(timing_evidence(root,manifest)['metadata_available'])

    def test_timing_is_sha_bound_and_cannot_become_a_gate_or_change_settings(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);path,data,manifest=self.fixture(root,True)
            self.assertTrue(timing_evidence(root,manifest)['metadata_available'])
            path.write_text('{}')
            with self.assertRaises(ValueError):timing_evidence(root,manifest)
            for key in ('timing_is_physical_gate','simulation_settings_changed','source_state_edited'):
                path.write_text(json.dumps(dict(data,**{key:True})));manifest['simulation_timing_sha256']=sha256(path)
                with self.assertRaises(ValueError):timing_evidence(root,manifest)

    def test_writer_reads_vendor_metadata_without_enabling_a_profiler_or_altering_mode(self):
        source=(Path(__file__).parent/'Collect_HeatDriveECC_ObservationPacket.m').read_text()
        self.assertIn('output.SimulationMetadata.TimingInfo',source)
        self.assertIn("'timing_is_physical_gate',false",source)
        self.assertIn('timing.metadata_error=ME.message',source)
        self.assertNotIn("'SimulationMode','accelerator'",source)
        self.assertNotIn("'Profile','on'",source)


if __name__=='__main__':unittest.main()
