"""Cold-start runner scope; actual native runtime review is separate."""
from pathlib import Path
import unittest


class ColdInitialScopeTests(unittest.TestCase):
    def setUp(self):
        root = Path(__file__).resolve().parent
        self.run = (root/"Run_HeatDriveECC_SharedSMAColdInitial.m").read_text(encoding="utf-8")
        self.observer = (root/"HeatDriveECC_ShortColdTimeObserver.m").read_text(encoding="utf-8")

    def test_new_initialization_does_not_change_hot_boundary_or_load_old_state(self):
        self.assertIn("set_param(p,'T0',num2str(options.system.T0_K,17),'T0_unit','K')", self.run)
        self.assertIn("o.simulation.resume_checkpoint_path=''", self.run)
        self.assertIn("'LoadInitialState','off','SaveState','off','SaveFinalState','off'", self.run)
        self.assertNotIn("setInitialState(", self.run)
        self.assertNotIn("options.system.Tshex_K=", self.run)
        self.assertNotIn("final_operating_point.mat", self.run)

    def test_both_arm_geometry_counts_are_explicit(self):
        self.assertIn("arms={'dual','shared'}", self.run)
        self.assertIn("expected=42;if strcmp(name,'shared'),expected=21;end", self.run)
        self.assertIn("assert(numel(paths)==expected)", self.run)

    def test_selected_raw_saved_before_gate_and_marker(self):
        write = self.run.index("write_json(raw,traces)")
        check = self.run.index("assert(max_initial_T_error<1e-6")
        marker = self.run.index("write_json(fullfile(arm,'completed_initial_probe.json')")
        self.assertLess(write, check)
        self.assertLess(check, marker)
        self.assertNotIn("save(fullfile", self.run)

    def test_native_energy_contract_is_not_variable_density_inventory(self):
        self.assertIn("rho_nominal*volume*u_I", self.run)
        self.assertIn("not rho_I*volume*u_I", self.run)
        self.assertIn("D0B8A66CBD6AFE7BBF14402A78BFE975BCBE009A5817D346CCBC5F64A85E1693", self.run)

    def test_observation_is_solver_sampled_not_external_polling(self):
        self.assertIn("HeatDriveECC_ProcessLocalTimeObserver(block)", self.observer)
        self.assertIn("block.SampleTimes=[.001 0]", self.observer)
        self.assertNotIn("timer(", self.run+self.observer)
        self.assertNotIn("pause(", self.run+self.observer)
        self.assertNotIn("save_system(", self.run)


if __name__ == "__main__":
    unittest.main()
