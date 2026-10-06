"""Verify the historical mechanical move and the current shared interfaces."""
import subprocess
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
MOVE_COMMIT = "17d7b85e95e69c5b01e3f328473d49c7557730b2"


def moved_source(name):
    return subprocess.check_output(
        ["git", "show", f"{MOVE_COMMIT}:gx101r1_R69_remote/{name}"],
        cwd=REPO, encoding="utf-8").replace("\r\n", "\n")


def normalized(text):
    return [line.strip() for line in text.splitlines() if line.strip()]


class PhysicalExtractionMoveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.old = subprocess.check_output(
            ["git", "show", "43329ec:gx101r1_R69_remote/Run_HeatDriveECC_EighthRound_Simulink_Cycles.m"],
            cwd=REPO, encoding="utf-8").replace("\r\n", "\n")

    def test_extractor_default_is_mechanical_move(self):
        old = self.old[self.old.index("function physical = extract_physical_simscape_logs("):]
        first = old.index("function steps = required_simscape_history_steps(")
        last = old.index("function sampled_values = read_optional_simscape_on_grid(", first)
        old = old[:first] + old[last:]
        new = moved_source("Extract_HeatDriveECC_PhysicalLogs.m")
        new = new.replace("function physical = Extract_HeatDriveECC_PhysicalLogs(sim_out, options, model_name, include_legacy_inventory)\n"
                          "% Shared physical extraction; new native diagnostics never import legacy inventory.\n"
                          "    if nargin < 4, include_legacy_inventory = true; end",
                          "function physical = extract_physical_simscape_logs(sim_out, options, model_name)")
        new = new.replace("    if include_legacy_inventory\n        physical = collect_fluid_inventory_energy( ...\n"
                          "            physical, sim_out, model_name, time_s);\n    end",
                          "    physical = collect_fluid_inventory_energy( ...\n        physical, sim_out, model_name, time_s);")
        new += moved_source("HeatDriveECC_CycleStageFromTime.m")
        new = new.replace("HeatDriveECC_CycleStageFromTime(", "cycle_stage_from_time(")
        self.assertEqual(normalized(old), normalized(new))

    def test_production_driver_is_unchanged_apart_from_shared_calls(self):
        old = self.old[:self.old.index("function physical = extract_physical_simscape_logs(")]
        start = self.old.index("function steps = required_simscape_history_steps(")
        stop = self.old.index("function sampled_values = read_optional_simscape_on_grid(", start)
        old += self.old[start:stop]
        new = moved_source("Run_HeatDriveECC_EighthRound_Simulink_Cycles.m")
        new = new.replace("Extract_HeatDriveECC_PhysicalLogs(", "extract_physical_simscape_logs(")
        new = new.replace("HeatDriveECC_CycleStageFromTime(", "cycle_stage_from_time(")
        self.assertEqual(normalized(old), normalized(new))

    def test_current_extractor_preserves_legacy_opt_in_and_missing_signal_error(self):
        source = (REPO / "Extract_HeatDriveECC_PhysicalLogs.m").read_text(encoding="utf-8")
        self.assertIn("if nargin < 4, include_legacy_inventory = true; end", source)
        self.assertIn("if include_legacy_inventory\n", source)
        self.assertIn("HeatDriveECC_CycleStageFromTime(time_s, options)", source)
        self.assertIn("Run:EighthRound:MissingPhysicalSignals", source)

    def test_current_driver_uses_shared_extractor(self):
        source = (REPO / "Run_HeatDriveECC_EighthRound_Simulink_Cycles.m").read_text(encoding="utf-8")
        self.assertIn("segment_physical = Extract_HeatDriveECC_PhysicalLogs(", source)
        self.assertNotIn("function physical = extract_physical_simscape_logs(", source)
        self.assertIn("HeatDriveECC_CycleStageFromTime(physical.time_s, options)", source)


if __name__ == "__main__":
    unittest.main()
