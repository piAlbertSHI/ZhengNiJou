import json
from pathlib import Path
import tempfile
import unittest

from Analyze_HeatDriveECC_RecordedTenCycles import runtime_window
from Audit_HeatDriveECC_SegmentedEvidence import sha256


class RuntimeRollingTests(unittest.TestCase):
    def data(self, root, count=1, passed=True):
        origin = root/'origin.json'
        origin.write_text(json.dumps(dict(window_s=[120, 220], runtime_family=True,
            packets=[dict(packet_root='old'+str(k), window_s=[120+20*k, 140+20*k]) for k in range(5)])))
        stop = 220+20*count
        return dict(schema='heatdrive_ecc_runtime_boundary_transient_collection_v1',
            collection_window_s=[220, stop], planned_collection_window_s=[220, 420],
            **{'pass': True}, total_cycles=stop/10, error_message='', source_state_edited=False,
            partial_state_restore_used=False, stop_on_public_periodicity=True,
            origin_measured_window_path=str(origin), origin_measured_window_sha256=sha256(origin),
            latest_periodicity=dict(window_s=[stop-100, stop], physical_tolerances_changed=False,
                periodic_steady_state=passed),
            completed_packets=[dict(packet_root='new'+str(k), start_time_s=220+20*k,
                stop_time_s=240+20*k) for k in range(count)])

    def test_one_new_packet_uses_four_preserved_origin_packets(self):
        with tempfile.TemporaryDirectory() as d:
            a,b,rows,previous=runtime_window(self.data(Path(d)))
            self.assertEqual((a,b),(140,240))
            self.assertEqual([r['packet_root'] for r in rows],['old1','old2','old3','old4','new0'])
            self.assertEqual(str(previous),'old0')

    def test_full_new_window_has_the_actual_immediate_predecessor(self):
        with tempfile.TemporaryDirectory() as d:
            a,b,rows,previous=runtime_window(self.data(Path(d),5))
            self.assertEqual((a,b),(220,320))
            self.assertEqual([r['packet_root'] for r in rows],['new'+str(k) for k in range(5)])
            self.assertEqual(str(previous),'old4')

    def test_fail_closed_on_early_nonperiodic_or_changed_source(self):
        with tempfile.TemporaryDirectory() as d:
            data=self.data(Path(d),passed=False)
            with self.assertRaises(ValueError):runtime_window(data)
            data=self.data(Path(d));Path(data['origin_measured_window_path']).write_text('{}')
            with self.assertRaises(ValueError):runtime_window(data)

    def test_exhausted_budget_is_a_qualified_transient_not_a_fake_periodic_point(self):
        with tempfile.TemporaryDirectory() as d:
            a,b,rows,previous=runtime_window(self.data(Path(d),10,False))
            self.assertEqual((a,b,len(rows)),(320,420,5))
            self.assertEqual(str(previous),'new4')

    def test_original_gates_and_full_op_precede_stopping_and_failed_analysis_does_not_reject_good_state(self):
        source=(Path(__file__).parent/'Run_HeatDriveECC_BoundedObservationPackets.m').read_text()
        self.assertLess(source.index('[next,manifest]=Load_HeatDriveECC_GatedObservationPacket'),
            source.index('check=Check_HeatDriveECC_RuntimeRollingPeriodicity(root,origin_index,completed);',
                source.index('[next,manifest]=')))
        self.assertIn('~strcmp(record.current_attempt_root,record.last_verified_packet_root)',source)
        self.assertIn("'planned_collection_window_s'",source)
        helper=(Path(__file__).parent/'Check_HeatDriveECC_RuntimeRollingPeriodicity.m').read_text()
        self.assertIn('Analyze_HeatDriveECC_RecordedThermalPeriodicity',helper)
        self.assertNotIn('sim(',helper)
        self.assertIn('m.prescribed_Tc_K==276.95',helper)


if __name__=='__main__':unittest.main()
