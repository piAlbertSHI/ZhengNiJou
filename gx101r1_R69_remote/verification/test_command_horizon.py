import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

import h5py
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from HeatDriveECC_CommandHorizon import audit_prefix, contract, prefix_arrays
from Verify_HeatDriveECC_ObservationPacket import validate_manifest


class CommandHorizonTest(unittest.TestCase):
    def declaration(self, case='extended'):
        return dict(schema='heatdrive_ecc_command_horizon_comparison_v1', case=case,
            source_snapshot_s=1080, source_Tc_K=274.85, source_horizon_cycles=200, future_horizon_cycles=1000,
            actual_horizon_cycles=1000 if case == 'extended' else 200,
            source_OP_sha256='A'*64, source_qualification_sha256='B'*64,
            prefix_proof_sha256='C'*64, payload_sha256='D'*64,
            source_state_edited=False, comparison_only=True)

    def manifest(self, case='extended'):
        c = self.declaration(case)
        return dict(schema='heatdrive_ecc_split_observation_packet_v1', window_s=[1080, 1100],
            simulation_returned_without_error=True, source_state_edited=False, history_cap_cycles=2,
            state_history_cap_cycles=11, strict_vendor_restore=True, production_recovery_allowed=False,
            packet_role='runtime_horizon_comparison', parent_complete_OP_sha256='A'*64,
            source_snapshot_s=1080, checksum_policy='error/error', temperature_configurability='runtime',
            source_generation_horizon_cycles=200, command_horizon_cycles=c['actual_horizon_cycles'],
            prescribed_Tc_K=274.85, horizon_comparison=c)

    def test_two_explicit_comparison_cases(self):
        for case in ('reference', 'extended'):
            self.assertEqual(validate_manifest(self.manifest(case)), (1080, 1100))

    def test_undeclared_cap_change_rejected(self):
        m = self.manifest(); m['command_horizon_cycles'] = 200
        with self.assertRaises(ValueError):
            validate_manifest(m)

    def test_changed_parent_or_scope_rejected(self):
        for field, value in (('parent_complete_OP_sha256', 'E'*64), ('checksum_policy', 'warning/error'),
                             ('prescribed_Tc_K', 276.95), ('source_generation_horizon_cycles', 1000)):
            m = self.manifest(); m[field] = value
            with self.assertRaises(ValueError):
                validate_manifest(m)

    def test_bad_comparison_contract_rejected(self):
        for field, value in (('comparison_only', False), ('source_state_edited', True),
                             ('future_horizon_cycles', 2000), ('source_OP_sha256', '1234'),
                             ('source_snapshot_s', 1980), ('source_Tc_K', 254)):
            c = self.declaration(); c[field] = value
            with self.assertRaises(ValueError):
                contract(c, [c['source_snapshot_s'], c['source_snapshot_s']+20])

    def arrays(self):
        a = np.array([0., 1080., 1100., 1200., 1990., 2000.])
        b = np.array([0., 1080., 1100., 1200., 1990., 2000., 10000.])
        x = np.array([[0., 1., 0., 1., 0., 1.]])
        y = np.array([[0., 1., 0., 1., 0., 0., 1.]])
        return a, x, b, y

    def test_future_change_does_not_change_interpolation_prefix(self):
        self.assertEqual(prefix_arrays(*self.arrays(), 1100), 4)

    def test_next_knot_is_part_of_past_interpolation_proof(self):
        a, x, b, y = self.arrays(); y[0, 3] = 2
        with self.assertRaises(ValueError):
            prefix_arrays(a, x, b, y, 1100)

    def test_changed_past_time_or_values_rejected(self):
        a, x, b, y = self.arrays(); b[1] += .001
        with self.assertRaises(ValueError):
            prefix_arrays(a, x, b, y, 1100)

    def test_signed_zero_change_is_not_bitwise_exact(self):
        a, x, b, y = self.arrays(); y[0, 0] = -0.
        with self.assertRaises(ValueError):
            prefix_arrays(a, x, b, y, 1100)

    def test_bad_clock_or_dtype_rejected(self):
        for index in (0, 1, 2, 3):
            values = list(self.arrays()); values[index] = values[index].astype(np.float32)
            with self.assertRaises(ValueError):
                prefix_arrays(*values, 1100)

    def test_legacy_writer_extraction_stays_unchanged(self):
        root = Path(__file__).resolve().parents[2]
        old = subprocess.check_output(['git', 'show',
            '3f74274:gx101r1_R69_remote/verification/Collect_HeatDriveECC_ObservationPacket.m'], cwd=root).decode()
        current = (Path(__file__).parent/'Collect_HeatDriveECC_ObservationPacket.m').read_text()
        section = lambda s: re.sub(r'\s+', '', s[s.index('assert(isempty(output.ErrorMessage)'):s.index('provenance=struct(')])
        self.assertEqual(section(old), section(current))

    def test_generator_waveforms_are_not_rewritten(self):
        root = Path(__file__).resolve().parents[2]
        name = 'gx101r1_R69_remote/Integrate_HeatDriveECC_Constitutive21_Interface.m'
        old = subprocess.check_output(['git', 'show', '3f74274:'+name], cwd=root).decode('utf-8')
        current = (root/name).read_text(encoding='utf-8')
        suffix = lambda s: re.sub(r'\s+', '', s[s.index('function sim_params = apply_full_cycle_valve_commands'):])
        self.assertEqual(suffix(old), suffix(current))

    def test_preflight_states_cannot_enter_the_loader(self):
        source = (Path(__file__).parent/'Load_HeatDriveECC_GatedObservationPacket.m').read_text()
        self.assertIn("~strcmp(manifest.packet_role,'runtime_horizon_comparison')", source)
        self.assertIn('comparison-only, never continuation authority', source)

    def test_old_capacity_guards_remain_versioned(self):
        source = (Path(__file__).parent/'Run_HeatDriveECC_RuntimeTcPackets.m').read_text()
        self.assertIn('target<=2000', source)
        state = (Path(__file__).parent/'Resolve_HeatDriveECC_DiagnosticStateOptions.m').read_text()
        self.assertIn("'<=',200", state)

    def payload(self, root, changed_past=False):
        a, x, b, y = self.arrays()
        if changed_past:
            y[0, 1] += 1
        row = dict(variable='cmd', prefix_and_interpolation_bracket_bitwise_equal=True,
                   resampling_used=False, first_possible_changed_interval_s=1990, interpolation_method='linear')
        with h5py.File(root/'command_payload.mat', 'w') as f:
            for group, prefix, time, values in (('reference', 'old', a, x), ('extended', 'new', b, y)):
                g = f.create_group('payload/'+group+'/cmd')
                for name, data in (('time', time.reshape(1, -1)), ('values', values)):
                    g.create_dataset('time_s' if name == 'time' else name, data=data)
                    row[prefix+'_'+name+'_sha256'] = hashlib.sha256(data.tobytes()).hexdigest().upper()
        p = dict(schema='heatdrive_ecc_future_command_prefix_v1', source_snapshot_s=1080,
            comparison_stop_s=1100, old_horizon_cycles=200, new_horizon_cycles=1000,
            source_state_edited=False, resampling_used=False, physical_parameters_changed=False,
            payload_sha256=sha256(root/'command_payload.mat'), commands=[row],
            unique_command_variables=1, actual_command_blocks=1, bindings=[dict(variable='cmd')])
        (root/'command_prefix.json').write_text(json.dumps(p))
        c = self.declaration(); c['prefix_proof_sha256'] = sha256(root/'command_prefix.json')
        c['payload_sha256'] = p['payload_sha256']
        return c

    def test_independent_HDF5_array_prefix_reverification(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); c = self.payload(root)
            self.assertTrue(audit_prefix(root/'reference', c)['prefix_with_interpolation_bracket_exact'])

    def test_rehashed_payload_does_not_hide_a_changed_past(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); c = self.payload(root, changed_past=True)
            with self.assertRaises(ValueError):
                audit_prefix(root/'extended', c)

    def test_changed_payload_and_missing_command_binding_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); c = self.payload(root)
            (root/'command_payload.mat').write_bytes(b'changed')
            with self.assertRaises(ValueError):
                audit_prefix(root/'extended', c)

    def test_post_simulation_binding_check_is_read_only(self):
        source = (Path(__file__).parent/'Check_HeatDriveECC_HorizonBindings.m').read_text()
        self.assertIn('slResolve', source)
        self.assertNotIn('assignin(', source)

    def test_no_hidden_mode_or_state_conversion(self):
        source = (Path(__file__).parent/'Verify_HeatDriveECC_RuntimeHorizon.m').read_text()
        self.assertNotIn("'SimulationMode','accelerator'", source)
        self.assertNotIn("setModelParameter('StartTime'", source)
        self.assertIn('.setInitialState(source_op)', source)
        self.assertIn("Check_HeatDriveECC_HorizonBindings(commands{k}", source)


if __name__ == '__main__':
    unittest.main()
