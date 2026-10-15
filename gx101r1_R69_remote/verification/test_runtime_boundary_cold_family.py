from pathlib import Path
import unittest

from Verify_HeatDriveECC_ObservationPacket import validate_manifest


class RuntimeBoundaryColdFamilyTests(unittest.TestCase):
    def manifest(self):
        return dict(schema='heatdrive_ecc_split_observation_packet_v1',window_s=[0,20],
            source_snapshot_s=0,simulation_returned_without_error=True,source_state_edited=False,
            history_cap_cycles=2,state_history_cap_cycles=11,strict_vendor_restore=False,checksum_policy='error/error',
            production_recovery_allowed=False,packet_role='runtime_boundary_cold_baseline',
            independent_cold_start=True,parent_complete_OP_sha256='')

    def test_independent_runtime_baseline_is_not_a_warm_state(self):
        self.assertEqual(validate_manifest(self.manifest()),(0,20))

    def test_old_state_hash_cannot_enter_runtime_cold_baseline(self):
        m=self.manifest();m['parent_complete_OP_sha256']='A'*64
        with self.assertRaises(ValueError):validate_manifest(m)

    def test_not_cold_and_shortened_baselines_are_rejected(self):
        for field,value in [('independent_cold_start',False),('window_s',[0,10]),('source_snapshot_s',720)]:
            m=self.manifest();m[field]=value
            with self.assertRaises(ValueError):validate_manifest(m)

    def test_runner_never_loads_old_op_and_drops_restore_fields(self):
        source=(Path(__file__).parent/'Run_HeatDriveECC_RuntimeBoundaryColdFamily.m').read_text()
        self.assertIn("struct('mode','capture','command_horizon_cycles',200)",source)
        self.assertNotIn('setInitialState(',source)
        self.assertNotIn('Load_HeatDriveECC_',source)

    def test_original_gates_precede_runtime_baseline_restore(self):
        source=(Path(__file__).parent/'Verify_HeatDriveECC_RuntimeBoundaryColdFamily.m').read_text()
        self.assertLess(source.index('Collect_HeatDriveECC_ObservationPacket(input,[],0,20'),source.index('Load_HeatDriveECC_GatedObservationPacket(baseline,false)'))
        self.assertIn('REJECTED_DO_NOT_RESUME',source)
        self.assertIn("'outer_solve_eligible',false",source)
        self.assertNotIn("set_param(model,'OperatingPoint",source)

    def test_only_explicit_family_changes_configurability(self):
        source=(Path(__file__).parent/'Run_HeatDriveECC_ColdChamberDiagnostic.m').read_text()
        self.assertIn('if runtime_boundary_family',source)
        self.assertIn("overrides.system.cold_boundary_temperature_configurability='runtime'",source)


if __name__=='__main__':unittest.main()
