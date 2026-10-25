from dataclasses import replace
import unittest

import numpy as np

from Reference_HeatDriveECC_ConservativeTransport import Bed, bs3_step
from Reference_HeatDriveECC_EnthalpyTransport import TabulatedEOS, EnthalpyBed


def synthetic_eos():
    t = np.array([280., 300., 320., 350., 400.])
    p = np.array([.45e6, .85e6, 2e6, 5e6])
    rho = 1000.-.3*(t[:, None]-300.)+.0000005*(p[None, :]-.85e6)
    u = 4200.*(t[:, None]-280.)+np.zeros_like(p)[None, :]
    return TabulatedEOS(t, p, rho, u, np.full(len(t), .6))


def test_bed(nodes=6):
    geometry = Bed(nodes, .3, 1e-5, 1000., 4200., .6, 2e-5, .04, 500., 18., 30., slope_limiter="MC")
    return EnthalpyBed(geometry, synthetic_eos(), 3.66, .0005, .01)


class EnthalpyTransportTests(unittest.TestCase):
    def test_bilinear_derivatives_match_finite_differences_not_a_separate_cp_table(self):
        eos = synthetic_eos()
        t, p = np.array([290., 310., 370.]), np.array([.6e6, 1.1e6, 3e6])
        props = eos.properties(t, p)
        for name in ("rho", "u"):
            numerical_t = (eos.properties(t+1e-3, p)[name]-eos.properties(t-1e-3, p)[name])/.002
            numerical_p = (eos.properties(t, p+10)[name]-eos.properties(t, p-10)[name])/20
            np.testing.assert_allclose(props[name+"_T"], numerical_t, rtol=1e-9, atol=1e-8)
            np.testing.assert_allclose(props[name+"_p"], numerical_p, rtol=1e-7, atol=1e-11)

    def test_inverse_recovers_temperature_and_pressure_without_reset(self):
        eos = synthetic_eos()
        t, p = np.array([289., 310., 379.]), np.array([.6e6, 1.1e6, 3e6])
        original = eos.properties(t, p)
        solved = eos.invert(original["rho"], original["u"])
        np.testing.assert_allclose(solved["T"], t, rtol=0, atol=1e-10)
        np.testing.assert_allclose(solved["p"], p, rtol=0, atol=.001)

    def test_outside_domain_rejected_not_extrapolated_or_clipped(self):
        eos = synthetic_eos()
        for t, p in ((279., .85e6), (401., .85e6), (300., .4e6), (300., 5.1e6)):
            with self.assertRaises(ValueError):
                eos.properties([t], [p])
        with self.assertRaises(ValueError):
            eos.invert([-1.], [100.])

    def test_conserved_rates_telescope_for_both_directions(self):
        bed = test_bed()
        initial = bed.initial_state()
        for flow, left, right in ((.0032, 390., 303.15), (-.0032, 303.15, 285.)):
            rate, props = bed.evaluate(initial, flow, left, right)
            self.assertAlmostEqual(np.sum(rate[:bed.nodes]), rate[-2], places=17)
            self.assertAlmostEqual(np.sum(rate[bed.nodes:3*bed.nodes]), rate[-1], places=12)
            self.assertLess(np.max(abs(props["pressure_rate_Pa_s"])), .001)

    def test_heating_expels_mass_and_cooling_draws_mass(self):
        bed = test_bed()
        for flow, left, right, sign in ((.0032, 390., 303.15, -1), (-.0032, 303.15, 285., 1)):
            rate, props = bed.evaluate(bed.initial_state(), flow, left, right)
            self.assertEqual(np.sign(rate[-2]), sign)
            self.assertNotEqual(abs(props["mass_faces_kg_s"][0]), abs(props["mass_faces_kg_s"][-1]))

    def test_uniform_equilibrium_has_no_mass_energy_change(self):
        bed = test_bed()
        for flow in (.0032, -.0032):
            rate = bed.rhs(bed.initial_state(), flow, 303.15, 303.15)
            np.testing.assert_allclose(rate, 0., rtol=0, atol=1e-12)

    def test_sealed_dwell_is_not_silently_replaced_by_constant_pressure(self):
        bed = test_bed()
        with self.assertRaisesRegex(ValueError, "sealed/zero-flow"):
            bed.rhs(bed.initial_state(), 0., 390., 285.)

    def test_primary_mass_energy_and_reversal_preserve_discrete_ledgers(self):
        bed = test_bed()
        initial = bed.initial_state()
        state = initial.copy()
        for step in range(40):
            flow = .0032 if step < 20 else -.0032
            rhs = lambda t, y: bed.rhs(y, flow, 330., 285.)
            state = bs3_step(rhs, step*.0001, state, .0001)
        self.assertLess(abs(state[:bed.nodes].sum()-initial[:bed.nodes].sum()-state[-2]), 1e-16)
        self.assertLess(abs(state[bed.nodes:3*bed.nodes].sum()-state[-1]), 1e-12)
        np.testing.assert_array_equal(initial, bed.initial_state())

    def test_grid_refinement_preserves_initial_mass_and_solid_heat_capacity(self):
        a, b = test_bed(6), test_bed(12)
        self.assertAlmostEqual(a.initial_state()[:6].sum(), b.initial_state()[:12].sum(), places=16)
        self.assertEqual(a.geometry.solid_capacity*6, b.geometry.solid_capacity*12)

    def test_adaptive_reference_preserves_ledgers_and_observes_pressure_without_projection(self):
        from Run_HeatDriveECC_EnthalpyReference import adaptive_case
        arrays, record = adaptive_case(test_bed(), .0032, "SMA", .01, 1e-10, np.array([0., .005, .01]))
        self.assertTrue(record["mass_numerical_invariant_pass"])
        self.assertTrue(record["energy_numerical_invariant_pass"])
        self.assertTrue(record["pressure_invariant_numerical_target_pass"])
        self.assertFalse(record["state_or_pressure_projection_applied"])
        self.assertTrue(record["transitions"][0]["all_coordinates_bitwise_unchanged"])
        np.testing.assert_array_equal(arrays["time_s"], [0., .005, .01])

    def test_invalid_internal_trial_rejects_step_without_replacing_accepted_state(self):
        from Run_HeatDriveECC_EnthalpyReference import DomainAwareDOP853
        from Reference_HeatDriveECC_EnthalpyTransport import EOSDomainError
        failed = [False]
        def rhs(t, y):
            if t > 0 and not failed[0]:
                failed[0] = True
                raise EOSDomainError("injected inadmissible internal trial")
            return -y
        solver = DomainAwareDOP853(rhs, 0., np.array([1.]), .001, first_step=.001, rtol=1e-10, atol=1e-12)
        solver.step()
        self.assertEqual(solver.domain_rejections, 1)
        self.assertTrue(solver.first_domain_rejection["accepted_state_unchanged"])
        self.assertAlmostEqual(solver.y[0], np.exp(-solver.t), places=12)

    def test_persistent_domain_failure_ends_without_an_infinite_retry_or_state_reset(self):
        from Run_HeatDriveECC_EnthalpyReference import DomainAwareDOP853
        from Reference_HeatDriveECC_EnthalpyTransport import EOSDomainError
        def rhs(t, y):
            if t > 0:
                raise EOSDomainError("persistent inadmissible trial")
            return -y
        solver = DomainAwareDOP853(rhs, 0., np.array([1.]), .001, first_step=.001)
        solver.step()
        self.assertEqual(solver.status, "failed")
        self.assertEqual(solver.t, 0.)
        np.testing.assert_array_equal(solver.y, [1.])
        self.assertLessEqual(solver.domain_rejections, 20)

    def test_impossible_iso_u_target_is_classified_as_domain_not_newton_failure(self):
        from Reference_HeatDriveECC_EnthalpyTransport import EOSDomainError
        eos = synthetic_eos()
        point = eos.properties([310.], [eos.pressure[0]])
        with self.assertRaisesRegex(EOSDomainError, "no in-domain EOS solution") as captured:
            eos.invert(point["rho"]-.05, point["u"])
        self.assertEqual(captured.exception.details["infeasible_indices"], [0])

    def test_valid_domain_corners_are_not_rejected_by_reference_pressure_energy_bounds(self):
        base = synthetic_eos()
        u = base.u-.0001*(base.pressure[None, :]-.85e6)
        eos = TabulatedEOS(base.temperature, base.pressure, base.rho, u, base.k)
        t = np.array([280., 280., 400., 400.])
        p = np.array([.45e6, 5e6, .45e6, 5e6])
        points = eos.properties(t, p)
        inverse = eos.invert(points["rho"], points["u"])
        np.testing.assert_allclose(inverse["T"], t, rtol=0, atol=1e-10)
        np.testing.assert_allclose(inverse["p"], p, rtol=0, atol=.001)

    def test_constrained_step_satisfies_primary_ledgers_and_EOS_together(self):
        from Reference_HeatDriveECC_ConstrainedEnthalpy import constrained_midpoint_step
        bed = test_bed()
        old = bed.initial_state()
        state, diagnostics = constrained_midpoint_step(bed, old, .0032, 393.15, 303.15, .001)
        self.assertLess(abs(state[:bed.nodes].sum()-old[:bed.nodes].sum()-state[-2]), 1e-15)
        self.assertLess(abs(state[bed.nodes:3*bed.nodes].sum()-state[-1]), 1e-8)
        self.assertLess(diagnostics["max_endpoint_pressure_deviation_Pa"], .001)
        self.assertFalse(diagnostics["accepted_state_projected_or_reset"])
        np.testing.assert_array_equal(old, bed.initial_state())

    def test_constrained_step_does_not_fix_an_inconsistent_failed_prior_state(self):
        from Reference_HeatDriveECC_ConstrainedEnthalpy import constrained_midpoint_step
        bed = test_bed()
        state = bed.initial_state()
        temperature = np.full(bed.nodes, bed.eos.Tref)
        props = bed.eos.properties(temperature, np.full(bed.nodes, 1e6))
        state[:bed.nodes] = props["rho"]*bed.volume
        state[bed.nodes:2*bed.nodes] = state[:bed.nodes]*(props["u"]-bed.eos.uref)
        with self.assertRaisesRegex(ValueError, "cannot be repaired/projected"):
            constrained_midpoint_step(bed, state, .0032, 393.15, 303.15, .001)

    def test_nonlinear_success_flag_does_not_replace_conservation_residual_check(self):
        from unittest.mock import patch
        from scipy.optimize import root as real_root
        from Reference_HeatDriveECC_ConstrainedEnthalpy import constrained_midpoint_step
        def premature(*args, **kwargs):
            solution = real_root(*args, **kwargs)
            solution.x[0] += 1e-7
            solution.success = True
            return solution
        bed = test_bed()
        with patch("Reference_HeatDriveECC_ConstrainedEnthalpy.root", side_effect=premature):
            _, diagnostics = constrained_midpoint_step(bed, bed.initial_state(), .0032, 393.15, 303.15, .001)
        self.assertGreater(diagnostics["unaccepted_nonlinear_unknown_polish_iterations"], 0)
        self.assertLessEqual(diagnostics["max_nonlinear_energy_residual_J"], diagnostics["roundoff_scaled_residual_allowance_J"])

    def test_minpack_QR_orientation_recovers_independent_linear_Jacobian(self):
        from scipy.optimize import root
        from Reference_HeatDriveECC_ConstrainedEnthalpy import minpack_jacobian
        a = np.array([[2., 3.], [-4., 5.]])
        solution = root(lambda x: a@x-np.array([1., 2.]), [0., 0.])
        np.testing.assert_allclose(minpack_jacobian(solution), a, rtol=0, atol=1e-10)

    def test_numerical_Jacobian_recycling_does_not_change_physical_trajectory(self):
        from Reference_HeatDriveECC_ConstrainedEnthalpy import constrained_midpoint_step
        bed = test_bed()
        baseline, cached = bed.initial_state(), bed.initial_state()
        memory = {}
        for command in (.0032, .0032, -.0032, -.0032):
            baseline, _ = constrained_midpoint_step(bed, baseline, command, 393.15, 303.15, .001)
            cached, info = constrained_midpoint_step(bed, cached, command, 393.15, 303.15, .001, memory)
            np.testing.assert_allclose(cached, baseline, rtol=0, atol=1e-10)
        self.assertTrue(info["numerical_Jacobian_reused"])


if __name__ == "__main__":
    unittest.main()
