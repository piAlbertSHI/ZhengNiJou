import copy
import unittest

import numpy as np

import test_caloric_cycle as fixture
from Run_HeatDriveECC_SavedNusseltControl import SavedNusseltCycle


class SavedNusseltTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fixture.CoupledTests.setUpClass()
        cls.old = fixture.CoupledTests.model

    def model(self, nu):
        c = copy.deepcopy(self.old.c)
        c["saved_forced_Nu"] = {"SMA": nu, "SE": 3.66}
        return SavedNusseltCycle(c, self.old.fluids)

    def state(self):
        h = fixture.CoupledTests()
        h.model = self.old
        return h.varied_state()

    def test_legacy_Nu_exactly_restores_old_derivative(self):
        m, y = self.model(3.66), self.state()
        for stage in (1, 2, 3, 4):
            np.testing.assert_array_equal(m.evaluate(y, stage)[0], self.old.evaluate(y, stage)[0])

    def test_sole_direct_change_is_equal_opposite_SMA_heat_exchange(self):
        m, y = self.model(4.365993493890937), self.state()
        for stage in (1, 2, 3, 4):
            change = m.evaluate(y, stage)[0]-self.old.evaluate(y, stage)[0]
            np.testing.assert_allclose(change[m.slices["bed_a"]], -change[m.slices["solid_a"]], atol=5e-12)
            mask = np.ones(m.size, dtype=bool)
            mask[m.slices["bed_a"]] = False
            mask[m.slices["solid_a"]] = False
            np.testing.assert_array_equal(change[mask], 0.)
            self.assertGreater(float(np.max(abs(change))), 0.)

    def test_no_phase_or_initial_coordinate_reset(self):
        m = self.model(4.365993493890937)
        np.testing.assert_array_equal(m.initial_state(), self.old.initial_state())
        y = self.state()
        before = y.copy()
        m.evaluate(y, 1)
        np.testing.assert_array_equal(y, before)


if __name__ == "__main__":
    unittest.main()
