import tempfile
import unittest
from pathlib import Path

from Snapshot_HeatDriveECC_StableEvidence import snapshot


class SnapshotGuards(unittest.TestCase):
    def test_existing_snapshot_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            dest=root/'snapshot';dest.mkdir()
            with self.assertRaises(FileExistsError):
                snapshot(root/'execution',dest)
            self.assertTrue(dest.is_dir())

    def test_missing_sources_do_not_create_a_destination(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);dest=root/'snapshot'
            with self.assertRaises(ValueError):
                snapshot(root/'execution',dest)
            self.assertFalse(dest.exists())


if __name__=='__main__':
    unittest.main()
