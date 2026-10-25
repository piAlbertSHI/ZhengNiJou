import unittest

import numpy as np

import test_caloric_cycle as fixture
from Reference_HeatDriveECC_LocalBoundaries import LocalBoundaries, ObservedCycle
from Reference_HeatDriveECC_TwoWayPhase import TwoWaySharedSurfaceCycle


class LocalBoundaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fixture.CoupledTests.setUpClass()
        cls.base = fixture.CoupledTests.model

    def state(self):
        helper = fixture.CoupledTests()
        helper.model = self.base
        return helper.varied_state()

    def test_every_CV_has_correct_instantaneous_energy_and_mass(self):
        for model in (self.base, TwoWaySharedSurfaceCycle(self.base.c, self.base.fluids)):
            ledger = LocalBoundaries(model)
            # Explicit operator identity must match the model type too.
            if isinstance(model, TwoWaySharedSurfaceCycle):
                model.c = dict(model.c, phase_operator="stage_free_shared_surface")
            y = self.state()
            for stage in (1, 2, 3, 4):
                d, _, _ = model.evaluate(y, stage)
                e, mass = ledger.boundary_rates(y, stage)
                np.testing.assert_allclose(ledger.energy_weights@d, ledger.incidence@e, rtol=0, atol=2e-9)
                np.testing.assert_allclose(ledger.mass_weights@d, ledger.incidence@mass, rtol=0, atol=1e-15)

    def test_wrong_heat_exchange_sign_cannot_hide_in_global_cancellation(self):
        ledger = LocalBoundaries(self.base)
        e, _ = ledger.boundary_rates(self.state(), 2)
        wrong = e.copy()
        wrong[ledger.edge_index["SMA_to_fluid"]] *= -1
        difference = ledger.incidence@(wrong-e)
        self.assertAlmostEqual(float(difference.sum()), 0., places=9)
        self.assertGreater(abs(difference[ledger.index["bed_a"]]), 1.)
        self.assertGreater(abs(difference[ledger.index["SMA_total"]]), 1.)

    def test_signed_stage2_and_stage4_mass_uses_physical_chambers(self):
        ledger = LocalBoundaries(self.base)
        y, mr = self.state(), self.base.c["mass_flow_kg_s"]["SE"]
        for stage, hot_sign in ((2, 1), (4, -1)):
            _, mass = ledger.boundary_rates(y, stage)
            net = ledger.incidence@mass
            self.assertAlmostEqual(net[ledger.index["hot_chamber"]], hot_sign*mr)
            self.assertAlmostEqual(net[ledger.index["cold_chamber"]], -hot_sign*mr)
            self.assertAlmostEqual(float(net.sum()), 0.)

    def test_observation_state_does_not_feed_back_to_physics(self):
        wrapper = ObservedCycle(self.base)
        y = np.r_[self.state(), np.zeros(2*wrapper.edge_count)]
        first = wrapper.evaluate(y, 4)[0]
        y[self.base.size:] = np.linspace(-1e6, 1e6, 2*wrapper.edge_count)
        second = wrapper.evaluate(y, 4)[0]
        np.testing.assert_array_equal(first, second)

    def test_port_formula_matches_each_MC_boundary_without_reusing_flux_code(self):
        from Reference_HeatDriveECC_ConservativeTransport import advective_faces
        h = np.array([13., -2., 8., 7.])
        for flow in (-.03, .03):
            faces = advective_faces(h, flow, 9., 12., order=2, limiter="MC")
            expected = faces[-1] if flow > 0 else -faces[0]
            self.assertAlmostEqual(abs(flow)*LocalBoundaries.outlet(h, flow), expected)


if __name__ == "__main__":
    unittest.main()
