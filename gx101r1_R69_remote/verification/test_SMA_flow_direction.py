import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np

import test_caloric_cycle as fixture
from Audit_HeatDriveECC_SMAFlowCoordinates import measured_sign, infer_sequence, route_inventory
from Analyze_HeatDriveECC_DirectionFailureSummary import stage_comparisons
from Run_HeatDriveECC_SavedNusseltControl import SavedNusseltCycle
from Run_HeatDriveECC_SMAFlowDirectionControl import CoDirectedSMACycle, DirectionalBoundaries, DirectionObservedCycle, persist_completed_arm, run


class SMAFlowDirectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fixture.CoupledTests.setUpClass()
        cls.c = copy.deepcopy(fixture.CoupledTests.contract)
        cls.c["saved_forced_Nu"] = {"SMA": 4.365993493890937, "SE": 3.66}
        fluids = fixture.CoupledTests.model.fluids
        cls.old = SavedNusseltCycle(cls.c, fluids)
        cls.new = CoDirectedSMACycle(cls.c, fluids)

    def state(self):
        h = fixture.CoupledTests()
        h.model = self.old
        return h.varied_state()

    def test_sensor_sign_not_pipe_letter_determines_solid_visit_order(self):
        self.assertEqual(infer_sequence(21, 1, 1), list(range(21, 0, -1)))
        self.assertEqual(infer_sequence(21, 1, -1), list(range(1, 22)))
        self.assertEqual(infer_sequence(1, 21, -1), list(range(21, 0, -1)))

    def test_mixed_or_zero_route_flow_does_not_get_a_false_direction(self):
        self.assertEqual(measured_sign([-1., -.1]), -1)
        self.assertEqual(measured_sign([.1, 1.]), 1)
        self.assertEqual(measured_sign([-1., 1.]), 0)
        with self.assertRaises(ValueError):
            infer_sequence(1, 21, 0)

    def test_first_heating_half_RHS_exactly_unchanged(self):
        y = self.state()
        for stage in (1, 2):
            np.testing.assert_array_equal(self.old.evaluate(y, stage)[0], self.new.evaluate(y, stage)[0])

    def test_cooling_change_is_only_bed_advection_and_common_return_energy(self):
        y = self.state()
        for stage in (3, 4):
            change = self.new.evaluate(y, stage)[0]-self.old.evaluate(y, stage)[0]
            mask = np.ones(self.old.size, dtype=bool)
            mask[self.old.slices["bed_a"]] = False
            mask[self.old.slices["buffer_H"].start] = False
            np.testing.assert_array_equal(change[mask], 0.)
            self.assertLess(abs(change[self.old.slices["bed_a"]].sum()+change[self.old.slices["buffer_H"].start]), 1e-10)
            self.assertGreater(float(np.max(abs(change))), .1)

    def test_matched_Nu_and_direction_local_boundaries_match_all_CVs(self):
        y = self.state()
        for model, direction in ((self.old, False), (self.new, True)):
            boundaries = DirectionalBoundaries(model, direction)
            for stage in (1, 2, 3, 4):
                d = model.evaluate(y, stage)[0]
                e, mass = boundaries.boundary_rates(y, stage)
                np.testing.assert_allclose(boundaries.energy_weights@d, boundaries.incidence@e, rtol=0., atol=3e-9)
                np.testing.assert_allclose(boundaries.mass_weights@d, boundaries.incidence@mass, rtol=0., atol=1e-16)

    def test_wrong_direction_observer_cannot_hide_behind_global_cancellation(self):
        y = self.state()
        wrong = DirectionalBoundaries(self.new, False)
        d = self.new.evaluate(y, 3)[0]
        e, _ = wrong.boundary_rates(y, 3)
        error = wrong.energy_weights@d-wrong.incidence@e
        self.assertGreater(float(np.max(abs(error))), .1)
        self.assertLess(abs(error.sum()), 1e-9)

    def test_no_initial_or_probe_coordinate_reset_and_observer_prefix_isolated(self):
        y = self.state()
        before = y.copy()
        for stage in (1, 2, 3, 4):
            self.new.evaluate(y, stage)
        np.testing.assert_array_equal(y, before)
        np.testing.assert_array_equal(self.new.initial_state(), self.old.initial_state())
        observed = DirectionObservedCycle(self.new, True)
        self.assertEqual(observed.controlled_size, self.new.size)
        self.assertEqual(observed.boundaries.contract()["SMA_cooling_direction"], "co_directed")


class ArmDurabilityTests(unittest.TestCase):
    def arrays(self):
        return {"time_s": np.array([0., .1]), "completed_stage": np.array([1, 1]), "physical": np.arange(6.).reshape(2, 3),
                "edge_J": np.zeros((2, 2)), "edge_kg": np.zeros((2, 2))}

    def test_two_exclusive_arm_markers_do_not_collide(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in ("counter", "co"):
                row = persist_completed_arm(root, name, self.arrays(), {"arm": name})
                marker = json.loads((root/("completed_arm_"+name+".json")).read_text(encoding="utf-8"))
                self.assertEqual(row, marker)
                self.assertTrue((root/row["raw"]["file"]).is_file())
            self.assertEqual(len(list(root.glob("*.npz"))), 2)
            self.assertFalse((root/"paired_direction_profiles.npz").exists())

    def test_duplicate_arm_cannot_overwrite_existing_observations(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            persist_completed_arm(root, "counter", self.arrays(), {"arm": "counter"})
            old = (root/"counter_direction_profiles.npz").read_bytes()
            with self.assertRaises(FileExistsError):
                persist_completed_arm(root, "counter", self.arrays(), {"arm": "counter"})
            self.assertEqual((root/"counter_direction_profiles.npz").read_bytes(), old)

    def test_marker_failure_does_not_destroy_either_raw_arm(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            persist_completed_arm(root, "counter", self.arrays(), {"arm": "counter"})
            with patch("Run_HeatDriveECC_SMAFlowDirectionControl.write_json", side_effect=OSError("synthetic publication failure")):
                with self.assertRaises(OSError):
                    persist_completed_arm(root, "co", self.arrays(), {"arm": "co"})
            self.assertTrue((root/"completed_arm_counter.json").is_file())
            self.assertFalse((root/"completed_arm_co.json").exists())
            with np.load(root/"co_direction_profiles.npz", allow_pickle=False) as z:
                np.testing.assert_array_equal(z["physical"], self.arrays()["physical"])

    def test_whole_pair_publication_with_stubbed_solver_never_reuses_one_shot_filename(self):
        # I/O workflow regression only; this intentionally does NOT simulate physics.
        fixture.CoupledTests.setUpClass()
        c = copy.deepcopy(fixture.CoupledTests.contract)
        c["saved_forced_Nu"] = {"SMA": 4.365993493890937, "SE": 3.66}
        baseline = SavedNusseltCycle(c, fixture.CoupledTests.model.fluids)
        t = np.array([0., 3.5, 5., 8.5, 10., 13.5, 15., 18.5, 20.])
        control = {"time_s": t[:5], "diagnostic_coordinates_NOT_OP": np.tile(baseline.initial_state(), (5, 1))}
        original = {"network_contract": c, "max_accepted_step_s": .005, "rtol": 1e-8}
        def fake_solver(model, cycles, max_step, rtol, sink):
            return {"time_s": t, "completed_stage": np.array([1, 1, 2, 3, 4, 1, 2, 3, 4]),
                    "diagnostic_coordinates_NOT_OP": np.tile(model.initial_state(), (len(t), 1))}, {"cycles": 2}
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root/"control").mkdir()
            (root/"control/saved_Nu_execution.json").write_text("{}", encoding="utf-8")
            with patch("Run_HeatDriveECC_SMAFlowDirectionControl.audit", return_value={"synthetic_IO_test": True}), \
                    patch("Run_HeatDriveECC_SMAFlowDirectionControl.load_control", return_value=(original, control)), \
                    patch("Run_HeatDriveECC_SMAFlowDirectionControl.simulate", side_effect=fake_solver):
                result = run(root/"control", root/"unused_native", root/"output")
            record = json.loads((root/"output/direction_execution.json").read_text(encoding="utf-8"))
            self.assertEqual(result["arms"], 2)
            self.assertTrue(record["collection_complete"])
            self.assertEqual(len(record["raw_files"]), 2)
            self.assertFalse((root/"output/completed_arm_evidence.json").exists())
            self.assertFalse((root/"output/paired_direction_profiles.npz").exists())


class RetainedStageSummaryTests(unittest.TestCase):
    def record(self):
        p = Path("C:/tmp/se21_SMA_direction_pair_C2_r1_20261026/FAILED_DO_NOT_RESUME.json")
        return json.loads(p.read_text(encoding="utf-8"))

    def test_only_recorded_stage_range_endpoints_are_recovered(self):
        rows = stage_comparisons(self.record())
        self.assertEqual(len(rows), 8)
        second_hot = next(r for r in rows if r["cycle"] == 2 and r["stage"] == 1)
        self.assertAlmostEqual(second_hot["range_endpoint_differences_co_minus_counter"]["SE_xM_range"][0],
                               -5.762246347185584e-7, places=13)
        self.assertTrue(all(not r["spatial_pointwise_or_time_maximum_difference_available"] for r in rows))

    def test_incomplete_or_other_failure_is_not_summarized_as_completed_pair(self):
        r = self.record()
        r["completed_arms"] = 1
        with self.assertRaises(ValueError):
            stage_comparisons(r)
        r = self.record()
        r["error_traceback"] = "physical solver failure"
        with self.assertRaises(ValueError):
            stage_comparisons(r)


class RouteInventoryTests(unittest.TestCase):
    def metadata(self, per_route_volume):
        return {"storage_blocks": [{"block_path": "model/SMA/"+name+"Pipe_%03d" % i,
                "mask_parameters": {"area": {"value": 1., "unit": "m^2"},
                                    "length": {"value": per_route_volume/21, "unit": "m"}}}
                for name in ("Hold", "Cooldown") for i in range(1, 22)]}

    def test_two_full_bed_storage_routes_have_twice_one_bed_inventory(self):
        r = route_inventory(self.metadata(1.), 1., 1000., 4., 500.)
        self.assertAlmostEqual(r["total_over_single_bed_ratio"], 2.)
        self.assertTrue(r["each_route_matches_a_whole_bed"])
        self.assertAlmostEqual(r["excess_reference_capacity_J_K"], 4000.)

    def test_two_half_volume_routes_are_not_falsely_called_duplicate_whole_beds(self):
        r = route_inventory(self.metadata(.5), 1., 1000., 4., 500.)
        self.assertAlmostEqual(r["total_over_single_bed_ratio"], 1.)
        self.assertFalse(r["each_route_matches_a_whole_bed"])
        self.assertAlmostEqual(r["excess_reference_capacity_J_K"], 0.)

    def test_missing_storage_segment_is_not_silently_ignored(self):
        m = self.metadata(1.)
        m["storage_blocks"].pop()
        with self.assertRaises(ValueError):
            route_inventory(m, 1., 1000., 4., 500.)


if __name__ == "__main__":
    unittest.main()
