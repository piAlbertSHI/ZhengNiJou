"""Partition adversaries and constructor source scope, not runtime physics."""
from pathlib import Path
import unittest

from Audit_HeatDriveECC_SharedSMAFluid import partition, require_partition


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


if __name__ == "__main__":
    unittest.main()
