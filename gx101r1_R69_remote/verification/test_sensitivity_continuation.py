from pathlib import Path
import unittest

from Verify_HeatDriveECC_ObservationPacket import validate_manifest
import test_sensitivity_cold_case as cold


class SensitivityContinuationTests(unittest.TestCase):
    def manifest(self,role='runtime_sensitivity_continuation'):
        m=cold.ColdSensitivityTests().manifest()
        m.update(packet_role=role,window_s=[200,220],source_snapshot_s=200,
            strict_vendor_restore=True,independent_cold_start=False,parent_complete_OP_sha256='A'*64)
        return m

    def test_same_case_continuation_is_bounded_without_changed_legacy_cold_scope(self):
        self.assertEqual(validate_manifest(self.manifest()),(200,220))
        for key,value in (('window_s',[1980,2010]),('window_s',[200,210]),('window_s',[180,200]),
                          ('source_snapshot_s',0),('prescribed_Tc_K',274.85),('strict_vendor_restore',False),
                          ('independent_cold_start',True),('parent_complete_OP_sha256','')):
            bad=self.manifest();bad[key]=value
            with self.assertRaises(ValueError):validate_manifest(bad)
        bad=self.manifest();bad.update(window_s=[1980,2000],source_snapshot_s=1980)
        self.assertEqual(validate_manifest(bad),(1980,2000))

    def test_comparison_allows_only_original_two_cycle_or_half_window(self):
        m=self.manifest('runtime_sensitivity_split_comparison')
        self.assertEqual(validate_manifest(m),(200,220))
        m.update(window_s=[210,220],source_snapshot_s=210)
        self.assertEqual(validate_manifest(m),(210,220))
        m.update(window_s=[220,240],source_snapshot_s=220)
        with self.assertRaises(ValueError):validate_manifest(m)

    def test_comparison_state_is_never_general_continuation_authority(self):
        source=(Path(__file__).parent/'Load_HeatDriveECC_GatedObservationPacket.m').read_text()
        first=source.split('if nargin<3')[0]
        self.assertIn('runtime_sensitivity_split_comparison',first)

    def test_resume_never_rebuilds_partial_state_or_repeats_cold_probe(self):
        source=(Path(__file__).parent/'Verify_HeatDriveECC_SensitivityContinuation.m').read_text()
        self.assertNotIn('Capture_HeatDriveECC_FreshSensitivityNative(',source)
        self.assertIn('Load_HeatDriveECC_GatedObservationPacket(source.packet_root,true,source.case_contract_sha256)',source)
        self.assertIn("'state_reconstructed_or_reset',false",source)
        self.assertIn("movefile(temp,path,'f')",source)


if __name__=='__main__':unittest.main()
