from pathlib import Path
import tempfile
import unittest

import h5py
import numpy as np

from Archive_HeatDriveECC_ObsoleteArm import export, retained_mask, selected_data
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Share_HeatDriveECC_ArchivedKeyEvidence import share


class StorageReliefTests(unittest.TestCase):
    def test_original_samples_only_first_ten_last_twenty(self):
        time = np.arange(201, dtype=float)
        mask = retained_mask(time)
        self.assertEqual(np.flatnonzero(mask).tolist(), list(range(11)) + list(range(180, 201)))
        values = np.vstack([time, -time])
        out, axis = selected_data(values, mask)
        self.assertEqual(axis, 1)
        np.testing.assert_array_equal(out[0], time[mask])

    def test_ambiguous_dimensions_are_rejected(self):
        with self.assertRaises(ValueError):
            selected_data(np.zeros((3, 3)), np.ones(3, dtype=bool))

    def test_export_preserves_selected_bits_and_never_overwrites(self):
        with tempfile.TemporaryDirectory() as folder:
            src, dst = Path(folder) / 'source.mat', Path(folder) / 'key.h5'
            with h5py.File(src, 'w') as f:
                row = f.create_group('row')
                for name, value in [('block_path', 'component'), ('state_name', 'T'), ('unit', 'K')]:
                    row.create_dataset(name, data=np.array([[ord(c) for c in value]], dtype=np.uint16))
                row.create_dataset('channel_count', data=[[1.]])
                row.create_dataset('time_s', data=np.arange(41., dtype=float)[None, :])
                row.create_dataset('values', data=np.arange(41., dtype=float)[None, :])
                f.create_dataset('native', data=np.array([[row.ref]], dtype=h5py.ref_dtype))
                signal = f.create_group('signals').create_group('test')
                signal.create_dataset('time_s', data=np.arange(201., dtype=float)[None, :])
                signal.create_dataset('values', data=(-np.arange(201., dtype=float))[None, :])
            original = sha256(src)
            receipt = export(src, dst, original)
            self.assertTrue(receipt['retained_bytes_exact'])
            self.assertFalse(receipt['compression_or_resampling_used'])
            self.assertEqual(sha256(src), original)
            with h5py.File(dst) as f:
                self.assertEqual(f['signals/test/time_s'].shape, (1, 32))
                self.assertIsNone(f['signals/test/values'].compression)
            with self.assertRaises(ValueError):
                export(src, dst, original)

    def test_executors_exclude_active_case_and_use_literal_deletes(self):
        root = Path(__file__).parent
        config = (root / 'Consolidate_HeatDriveECC_IdenticalConfigs.ps1').read_text(encoding='utf-8')
        arms = (root / 'Retire_HeatDriveECC_ArchivedObsoleteArms.ps1').read_text(encoding='utf-8')
        for source in (config, arms):
            self.assertNotIn('Remove-Item -Recurse', source)
            self.assertIn('Remove-Item -LiteralPath', source)
            self.assertIn('Reparse point forbidden', source)
        self.assertIn('Active case excluded', config)
        self.assertIn('Outside immutable exact allowlist', arms)
        self.assertIn('Check-Records $q.protected_files', arms)

    def test_shared_archive_reuses_only_identical_arrays_and_keeps_differences(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'native').mkdir()
            (root / 'conservative').mkdir()
            native = root / 'native/observations.mat'
            old = root / 'conservative/old.h5'
            out = root / 'conservative/shared.h5'
            with h5py.File(native, 'w') as f:
                g = f.create_group('signals').create_group('test')
                g.create_dataset('time_s', data=np.arange(5.)[None, :])
                g.create_dataset('values', data=np.arange(5.)[None, :])
            with h5py.File(old, 'w') as f:
                g = f.create_group('signals').create_group('test')
                g.create_dataset('time_s', data=np.arange(5.)[None, :])
                g.create_dataset('values', data=(-np.arange(5.))[None, :])
            r = share(old, native, out, sha256(old), sha256(native))
            self.assertEqual(r['identical_datasets_shared'], 1)
            self.assertTrue(r['all_retained_datasets_bitwise_equal'])
            with h5py.File(out) as f:
                self.assertIsInstance(f['signals/test'].get('time_s', getlink=True), h5py.ExternalLink)
                np.testing.assert_array_equal(f['signals/test/values'][:], -np.arange(5.)[None, :])


if __name__ == '__main__':
    unittest.main()
