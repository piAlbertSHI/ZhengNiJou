"""Coverage/serializer scope checks. Actual native runtime is a separate proof."""
import copy
from pathlib import Path
import unittest

import numpy as np

from HeatDriveECC_TraceColumns import unpack
from Review_HeatDriveECC_CoupledCVPacket import on_grid


class PacketTests(unittest.TestCase):
    def packet(self):
        return {"schema":"heatdrive_ecc_shared_clock_trace_columns_v1","time_interpolation_performed":False,
                "state_values_modified":False,"not_an_OP_or_restart_state":True,
                "time_grids":{"grid_index":1,"time_s":np.array([0.,.001,.002])},
                "rows":[{"block_path":"fixture","state_name":"T","unit":"K","grid_index":1,"values":np.array([0.,-0.,1.]),"channel_count":1},
                        {"block_path":"fixture","state_name":"Q","unit":"W","grid_index":1,"values":np.arange(6.).reshape(3,2),"channel_count":2}]}

    def test_one_original_clock_is_shared_without_changing_value_bits(self):
        p=self.packet();r=unpack(p)
        self.assertIs(r['fixture','T']['time_s'],r['fixture','Q']['time_s'])
        np.testing.assert_array_equal(r['fixture','T']['values'].ravel().view(np.uint64),p['rows'][0]['values'].view(np.uint64))

    def test_missing_grid_or_wrong_channel_count_is_rejected(self):
        p=self.packet();p['rows'][0]['grid_index']=2
        with self.assertRaises(ValueError):unpack(p)
        p=self.packet();p['rows'][1]['channel_count']=3
        with self.assertRaises(ValueError):unpack(p)

    def test_duplicate_native_key_is_rejected(self):
        p=self.packet();p['rows'].append(copy.deepcopy(p['rows'][0]))
        with self.assertRaises(ValueError):unpack(p)

    def test_interpolated_or_resumable_packet_is_rejected(self):
        p=self.packet();p['time_interpolation_performed']=True
        with self.assertRaises(ValueError):unpack(p)
        p=self.packet();p['not_an_OP_or_restart_state']=False
        with self.assertRaises(ValueError):unpack(p)

    def test_new_inventory_is_exact_by_path_not_a_relaxed_119_check(self):
        root=Path(__file__).resolve().parent
        source=(root/'Extract_HeatDriveECC_NativeStorageTraces.m').read_text(encoding='utf-8')
        self.assertIn('component_count == 119',source)
        self.assertIn('sort(inventory_contract.storage_paths(:))',source)
        self.assertIn('isequal(observed_counts,inventory_contract.type_counts)',source)
        capture=(root/'Capture_HeatDriveECC_CoupledCVPacket.m').read_text(encoding='utf-8')
        self.assertLess(capture.index("save(file,'packet','-v7')"),capture.index('Extract_HeatDriveECC_BoundaryTraces'))
        self.assertNotIn('save_system(',capture)

    def test_hex_pressure_uses_absolute_exposed_Pa_port_not_difference_P(self):
        source=(Path(__file__).resolve().parent/'Prepare_HeatDriveECC_CoupledCVObservation.m').read_text(encoding='utf-8')
        self.assertIn("for field={'T','Pa'}",source)
        self.assertIn("'pressure_spec','foundation.enum.PressureMeasementSpec.Absolute'",source)
        self.assertIn("properties=simscape.connectionPortProperties(converter)",source)

    def test_actual_grid_selects_last_event_without_interpolation(self):
        row={'time_s':np.array([0.,.001,.001,.002]),
             'values':np.array([[1.],[2.],[3.],[4.]])}
        np.testing.assert_array_equal(on_grid(row,np.array([0.,.001,.002])).ravel(),[1.,3.,4.])
        with self.assertRaises(ValueError):on_grid(row,np.array([.0015]))

    def test_shared_legacy_gate_is_explicitly_unsupported_not_relaxed(self):
        root=Path(__file__).resolve().parent
        source=(root.parent/'Validate_HeatDriveECC_EighthRound_Physics.m').read_text(encoding='utf-8')
        self.assertIn('Validate:EighthRound:SharedSMATopologyUnsupported',source)
        capture=(root/'Prepare_HeatDriveECC_CoupledCVObservation.m').read_text(encoding='utf-8')
        self.assertIn("'cv_PI_sma_state','cv_PI_se_stage2_state','stage4_integrator_state'",capture)
        self.assertIn("'controller_parameters_modified',false",capture)
        self.assertNotIn("set_param(p,'InitialCondition'",capture)


if __name__=='__main__':unittest.main()
