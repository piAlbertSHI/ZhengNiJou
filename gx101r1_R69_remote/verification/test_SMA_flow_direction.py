import copy
import unittest

import numpy as np

import test_caloric_cycle as fixture
from Audit_HeatDriveECC_SMAFlowCoordinates import measured_sign, infer_sequence
from Run_HeatDriveECC_SavedNusseltControl import SavedNusseltCycle
from Run_HeatDriveECC_SMAFlowDirectionControl import CoDirectedSMACycle, DirectionalBoundaries, DirectionObservedCycle


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


if __name__ == "__main__":
    unittest.main()
