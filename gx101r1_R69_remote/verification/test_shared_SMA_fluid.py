"""Partition adversaries and constructor source scope, not runtime physics."""
from pathlib import Path
import unittest
from unittest.mock import patch

from Audit_HeatDriveECC_SharedSMAFluid import partition, require_partition, review


def topology(keys, pairs):
    return {"vertices": [{"key": k} for k in keys],
            "edges": [{"a": a+1, "b": b+1, "kind": "physical_wire_net"} for a, b in pairs]}


class WirePartitionTests(unittest.TestCase):
    def test_declared_retirement_and_join_only(self):
        old = topology(["keep:A", "remove:A", "port:A", "outside:A"], [(1, 2)])
        new = topology(["keep:A", "port:A", "outside:A"], [(0, 1)])
        self.assertEqual(require_partition(old, new, r"^remove$", [("keep:A", "port:A")]), 1)

    def test_silent_external_short_rejected(self):
        old = topology(["a:A", "b:A", "outside:A"], [])
        new = topology(["a:A", "b:A", "outside:A"], [(0, 1), (1, 2)])
        with self.assertRaisesRegex(ValueError, "partition"):
            require_partition(old, new, r"never", [("a:A", "b:A")])

    def test_silent_solid_disconnect_rejected(self):
        old = topology(["solid:M", "hold:B", "cool:B"], [(0, 1), (0, 2)])
        new = topology(["solid:M", "hold:B"], [])
        with self.assertRaisesRegex(ValueError, "partition"):
            require_partition(old, new, r"^cool$")

    def test_unlisted_state_removal_rejected(self):
        with self.assertRaisesRegex(ValueError, "vertex"):
            require_partition(topology(["solid:M", "pipe:A"], []), topology(["solid:M"], []), r"never")

    def test_primitive_component_is_not_a_wire_short(self):
        t = topology(["a:A", "b:B"], [(0, 1)])
        t["edges"][0]["kind"] = "primitive_internal"
        with self.assertRaises(ValueError):
            partition(t)

    def test_duplicate_coordinates_rejected(self):
        with self.assertRaises(ValueError):
            partition(topology(["a:A", "a:A"], []))


class ConstructorScopeTests(unittest.TestCase):
    def test_no_simulation_reset_or_production_save(self):
        root = Path(__file__).resolve().parent
        apply = (root/"Apply_HeatDriveECC_SharedSMAFluidDiagnostic.m").read_text(encoding="utf-8")
        run = (root/"Run_HeatDriveECC_SharedSMAConstruction.m").read_text(encoding="utf-8")
        for text in (apply, run):
            self.assertNotIn("save_system(", text)
            self.assertNotIn("setInitialState(", text)
            self.assertNotIn("SimulationCommand','start", text)
            self.assertNotIn("sim(model", text)
        self.assertIn("'LoadInitialState','off','SaveState','off','SaveFinalState','off'", run)
        self.assertIn("'Inputs','2'", apply)
        self.assertIn("'Function','max'", apply)
        self.assertIn("isequal(pipes{i},pipe_parameters(keep{i}))", apply)
        self.assertIn("live=get_param(h,'Line')", apply)
        self.assertNotIn("for line=unique(line_handles)", apply)
        self.assertIn("get_param(line,'LineParent')", apply)


class RetainedConstructorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path("C:/tmp/se21_shared_SMA_constructor_r5_20261026")
        cls.result = review(cls.root)

    def test_actual_construction_is_one_inventory_not_physical_qualification(self):
        r = self.result
        self.assertEqual(r["retained_SMA_fluid_pipe_count"], 21)
        self.assertEqual(r["retired_liquid_typed_vertices"], 42)
        self.assertTrue(r["all_surviving_thermal_wire_partitions_unchanged"])
        self.assertFalse(r["compiled_inventory_state_count_verified"])
        self.assertFalse(r["switch_continuity_or_energy_balance_proven"])
        self.assertFalse(r["production_recovery_or_twenty_cycle_seed_allowed"])

    def test_actual_hot_constructor_is_not_mislabeled_uniform_cold(self):
        r = self.result
        self.assertEqual(r["retained_bed_initial_T_K_from_constructor_rules"], 393.15)
        self.assertEqual(r["removed_cooling_representation_initial_T_K"], 303.15)
        self.assertFalse(r["uniform_cold_start_proven"])

    def test_wrong_historical_producer_source_is_rejected(self):
        with patch("Audit_HeatDriveECC_SharedSMAFluid.subprocess.check_output", return_value=b"different source"):
            with self.assertRaisesRegex(ValueError, "producer source"):
                review(self.root)


if __name__ == "__main__":
    unittest.main()
