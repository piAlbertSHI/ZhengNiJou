import unittest
import numpy as np
from Audit_HeatDriveECC_PublicSnapshotEvidence import compare_window, validate_source, LEGACY_METADATA_SHA256


class SourceMetadataTests(unittest.TestCase):
    def setUp(self):
        self.meta=dict(strict_restore_pass=True, observation_complete=True, error_message='',
            source_operating_point_edited=False, production_recovery_allowed=False,
            partial_restore_executed=False, cold_start_executed=False,
            physical_options_unchanged={'geometry':True})

    def test_only_frozen_legacy_can_omit_scope(self):
        validate_source(self.meta,LEGACY_METADATA_SHA256)
        with self.assertRaises(KeyError):validate_source(self.meta,'modified')

    def test_new_source_requires_unchanged_scope(self):
        self.meta.update(command_horizon_extended=False,boundary_sample_hold_diagnostic=False,
                         original_cycle_count=200,target_cycle_count=200)
        validate_source(self.meta,'new')
        self.meta['target_cycle_count']=201
        with self.assertRaises(ValueError):validate_source(self.meta,'new')

    def test_empty_physical_options_rejected(self):
        self.meta['physical_options_unchanged']={}
        with self.assertRaises(ValueError):validate_source(self.meta,LEGACY_METADATA_SHA256)


class SnapshotWindowTests(unittest.TestCase):
    def setUp(self):
        self.reference={'x':('K',np.array([2000,2000.001,2000.002]),np.array([[310.,311.,312.]]))}
        self.actual={'x':('K',np.array([2000.001,2000.002]),np.array([[311.,312.]]))}

    def run_comparison(self):
        return compare_window(self.reference,self.actual,[2000,2000.001,2000.002],[2000.001,2000.002],1)

    def test_exact_reference_slice(self):
        self.assertEqual(self.run_comparison()[0]['exact'],[True,True])

    def test_shifted_values_fail(self):
        self.actual['x'][2][:]=[[310.,311.]]
        self.assertFalse(self.run_comparison()[0]['comparisons'][0]['pass_endpoint_match'])

    def test_time_shift_rejected(self):
        self.actual['x'][1][0]=2000
        with self.assertRaises(ValueError):self.run_comparison()

    def test_unit_mismatch_rejected(self):
        self.actual['x']=('W',self.actual['x'][1],self.actual['x'][2])
        with self.assertRaises(ValueError):self.run_comparison()

    def test_coverage_loss_rejected(self):
        self.actual={}
        with self.assertRaises(ValueError):self.run_comparison()

    def test_nan_rejected(self):
        self.actual['x'][2][0,0]=np.nan
        with self.assertRaises(ValueError):self.run_comparison()


if __name__=='__main__':unittest.main()
