import unittest

import numpy as np
from scipy.integrate import RK23

from Reference_HeatDriveECC_ConservativeTransport import (
    Bed, advective_faces, conductive_faces, bs3_step, advance_segments, affine_exponential)


def example_bed(nodes=12, periodic=False, **kw):
    defaults = dict(length_m=1., fluid_area_m2=1., fluid_rho_kg_m3=1., fluid_cp_J_kgK=1.,
                    fluid_k_W_mK=.01, solid_area_m2=1., solid_mass_kg=2., solid_cp_J_kgK=1.,
                    solid_k_W_mK=.02, UA_W_K=.3)
    defaults.update(kw)
    return Bed(nodes=nodes, periodic=periodic, **defaults)


class ConservativeTransportTests(unittest.TestCase):
    def test_invalid_geometry_rejected(self):
        for kw in ({"nodes": 2}, {"fluid_rho_kg_m3": 0}, {"UA_W_K": -1},
                   {"length_m": np.nan}, {"advection_order": 3}):
            with self.assertRaises(ValueError):
                example_bed(**kw)

    def test_constant_temperature_preserved_at_both_flow_signs(self):
        for sign in (-1, 0, 1):
            for periodic in (False, True):
                bed = example_bed(periodic=periodic)
                state = np.r_[np.full(2*bed.nodes, 3.), 0.]
                np.testing.assert_allclose(bed.rhs(state, sign, 3., 3.), 0., atol=1e-14)

    def test_shared_faces_telescope_for_both_signs_and_internal_heat_cancels(self):
        bed = example_bed()
        state = np.r_[np.linspace(-1, 2, bed.nodes), np.linspace(3, -2, bed.nodes), 0.]
        for sign in (-1, 0, 1):
            rate = bed.rhs(state, sign, 4., -5.)
            self.assertAlmostEqual(bed.energy(rate), rate[-1], places=13)

    def test_periodic_faces_are_identical_and_net_external_energy_is_zero(self):
        bed = example_bed(periodic=True)
        state = np.sin(np.arange(bed.state_size))
        for sign in (-1, 1):
            fluid, solid, _ = bed.fluxes(state, sign, 99., -99.)
            self.assertEqual(fluid[0], fluid[-1])
            self.assertEqual(solid[0], solid[-1])
            self.assertEqual(bed.rhs(state, sign)[-1], 0.)

    def test_reversal_is_flux_reflection_not_state_mutation(self):
        original = np.array([1., 4., 2., 3.])
        saved = original.copy()
        negative = advective_faces(original, -2., 10., -4.)
        reflected = -advective_faces(original[::-1], 2., -4., 10.)[::-1]
        np.testing.assert_array_equal(negative, reflected)
        np.testing.assert_array_equal(original, saved)

    def test_second_order_linear_faces_include_inlet_half_cell(self):
        temperature = (np.arange(8) + .5)/8
        np.testing.assert_allclose(advective_faces(temperature, 1., 0., 1.), np.arange(9)/8)
        np.testing.assert_allclose(advective_faces(temperature, -1., 0., 1.), -np.arange(9)/8)

    def test_centered_conduction_and_insulated_ends(self):
        faces = conductive_faces(np.array([1., 2., 4.]), 3.)
        np.testing.assert_array_equal(faces, [0., -3., -6., 0.])

    def test_bs3_matches_independently_instantiated_scipy_tableau(self):
        rhs = lambda t, y: np.array([y[1] + t, -.7*y[0] + y[1]**2])
        y = np.array([.2, -.3]); dt = .01
        tableau = RK23(rhs, 0., y, .1)
        stages = np.zeros((3, 2))
        for i in range(3):
            stages[i] = rhs(tableau.C[i]*dt, y + dt*np.dot(tableau.A[i, :i], stages[:i]))
        np.testing.assert_allclose(bs3_step(rhs, 0., y, dt), y + dt*tableau.B.dot(stages), rtol=0, atol=1e-16)

    def test_time_error_decreases_against_matrix_exponential(self):
        bed = example_bed(8)
        segment = {"end_s": .2, "mdot_kg_s": .3, "left_K": 1., "right_K": -1.}
        exact = affine_exponential(lambda y: bed.rhs(y, .3, 1., -1.), np.zeros(bed.state_size), .2)
        errors = []
        for dt in (.01, .005, .0025):
            sampled, meta = advance_segments(bed, [segment], dt, [0., .2])
            errors.append(np.max(abs(sampled[-1] - exact)))
            self.assertLess(meta["max_abs_energy_residual_J"], 1e-12)
        for ratio in (errors[0]/errors[1], errors[1]/errors[2]):
            self.assertGreater(ratio, 7.)
            self.assertLess(ratio, 9.)

    def test_reversal_retains_entire_nonuniform_state(self):
        bed = example_bed()
        segments = [{"end_s": .1, "mdot_kg_s": .2, "left_K": 3., "right_K": -4.},
                    {"end_s": .2, "mdot_kg_s": -.2, "left_K": 3., "right_K": -4.}]
        initial = np.r_[np.linspace(-1, 2, bed.nodes), np.linspace(3, -2, bed.nodes), 0.]
        samples, meta = advance_segments(bed, segments, .001, [0, .1, .2], initial)
        self.assertTrue(meta["transitions"][0]["all_coordinates_bitwise_unchanged"])
        first, _ = advance_segments(bed, segments[:1], .001, [0, .1], initial)
        second, _ = advance_segments(bed, [dict(segments[1], end_s=.1)], .001, [0, .1], first[-1])
        np.testing.assert_array_equal(samples[-1], second[-1])
        self.assertLess(meta["max_abs_energy_residual_J"], 1e-12)

    def test_non_grid_events_nonfinite_drives_and_partial_output_rejected(self):
        bed = example_bed()
        for segment, times in (({"end_s": .105, "mdot_kg_s": 1., "left_K": 0., "right_K": 0.}, [0, .105]),
                               ({"end_s": .1, "mdot_kg_s": np.nan, "left_K": 0., "right_K": 0.}, [0, .1]),
                               ({"end_s": .1, "mdot_kg_s": 1., "left_K": 0., "right_K": 0.}, [0, .05])):
            with self.assertRaises(ValueError):
                advance_segments(bed, [segment], .01, times)

    def test_external_heat_is_not_silently_lost_from_ledger(self):
        bed = example_bed()
        y = np.zeros(bed.state_size)
        qf, qs = np.full(bed.nodes, .2), np.full(bed.nodes, -.1)
        rate = bed.rhs(y, 0., fluid_power=qf, solid_power=qs)
        self.assertAlmostEqual(rate[-1], .1 * bed.nodes)
        self.assertAlmostEqual(bed.energy(rate), rate[-1])

    def test_grid_refinement_does_not_change_total_inventory_or_exchange_area(self):
        beds = [example_bed(n) for n in (21, 42, 84)]
        for bed in beds:
            self.assertEqual(bed.fluid_mass, beds[0].fluid_mass)
            self.assertEqual(bed.solid_mass_kg, beds[0].solid_mass_kg)
            self.assertAlmostEqual(bed.fluid_capacity * bed.nodes, beds[0].fluid_capacity * beds[0].nodes)
            state = np.r_[np.zeros(bed.nodes), np.ones(bed.nodes), 0.]
            self.assertAlmostEqual(np.sum(bed.fluxes(state, 0., 0., 0.)[2]), bed.UA_W_K)

    def test_periodic_analytic_pde_is_second_order_for_advection_and_diffusion(self):
        from Run_HeatDriveECC_ConservativeTransport import smooth_spatial_review
        review = smooth_spatial_review()
        self.assertTrue(review["spatial_observations_all_pass"])
        self.assertLess(review["reversal_energy_residual_J"], 1e-12)

    def test_open_boundary_closure_converges_in_both_directions(self):
        from Run_HeatDriveECC_ConservativeTransport import open_boundary_review
        for row in open_boundary_review()["rows"]:
            self.assertTrue(row["errors_decrease"])
            for order in row["observed_spatial_orders"]:
                self.assertGreater(order, 1.8)
                self.assertLess(order, 2.2)


if __name__ == "__main__":
    unittest.main()
