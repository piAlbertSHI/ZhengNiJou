"""Pin the shared extractor's default behavior to the pre-move source."""
import subprocess
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]


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
        new = (REPO / "Extract_HeatDriveECC_PhysicalLogs.m").read_text(encoding="utf-8")
        new = new.replace("function physical = Extract_HeatDriveECC_PhysicalLogs(sim_out, options, model_name, include_legacy_inventory)\n"
                          "% Shared physical extraction; new native diagnostics never import legacy inventory.\n"
                          "    if nargin < 4, include_legacy_inventory = true; end",
                          "function physical = extract_physical_simscape_logs(sim_out, options, model_name)")
        new = new.replace("    if include_legacy_inventory\n        physical = collect_fluid_inventory_energy( ...\n"
                          "            physical, sim_out, model_name, time_s);\n    end",
                          "    physical = collect_fluid_inventory_energy( ...\n        physical, sim_out, model_name, time_s);")
        new += (REPO / "HeatDriveECC_CycleStageFromTime.m").read_text(encoding="utf-8")
        new = new.replace("HeatDriveECC_CycleStageFromTime(", "cycle_stage_from_time(")
        self.assertEqual(normalized(old), normalized(new))

    def test_production_driver_is_unchanged_apart_from_shared_calls(self):
        old = self.old[:self.old.index("function physical = extract_physical_simscape_logs(")]
        start = self.old.index("function steps = required_simscape_history_steps(")
        stop = self.old.index("function sampled_values = read_optional_simscape_on_grid(", start)
        old += self.old[start:stop]
        new = (REPO / "Run_HeatDriveECC_EighthRound_Simulink_Cycles.m").read_text(encoding="utf-8")
        new = new.replace("Extract_HeatDriveECC_PhysicalLogs(", "extract_physical_simscape_logs(")
        new = new.replace("HeatDriveECC_CycleStageFromTime(", "cycle_stage_from_time(")
        self.assertEqual(normalized(old), normalized(new))


if __name__ == "__main__":
    unittest.main()
