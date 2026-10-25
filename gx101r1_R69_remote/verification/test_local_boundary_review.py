import json
from pathlib import Path
import tempfile
import unittest

from Analyze_HeatDriveECC_LocalBoundaryProtocol import readback


ROOT = Path("C:/tmp/se21_local_boundaries_cold_C1_r3_20261026")


class LocalReviewTests(unittest.TestCase):
    def test_actual_packet_has_local_identities_without_qualifying_material(self):
        result = readback(ROOT)
        self.assertEqual(len(result["control_volumes"]), 15)
        self.assertEqual(result["edge_count"], 23)
        self.assertTrue(result["all_saved_base_coordinates_bitwise_equal_to_control"])
        self.assertFalse(result["material_or_periodic_qualified"])
        self.assertFalse(result["strict_Table4_reproduced"])

    def test_nonisolated_observer_is_not_accepted_as_final_protocol(self):
        record = json.loads((ROOT/"local_boundary_execution.json").read_text(encoding="utf-8"))
        record["observer_coordinates_excluded_from_step_selection_and_error_norm"] = False
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/"local_boundary_execution.json").write_text(json.dumps(record), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "isolated-observer"):
                readback(root)

    def test_raw_bytes_changed_are_rejected_before_scientific_summary(self):
        record = json.loads((ROOT/"local_boundary_execution.json").read_text(encoding="utf-8"))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/"local_boundary_execution.json").write_text(json.dumps(record), encoding="utf-8")
            (root/record["raw"]["file"]).write_bytes(b"not the sealed raw data")
            with self.assertRaisesRegex(ValueError, "raw packet"):
                readback(root)


if __name__ == "__main__":
    unittest.main()
