import unittest

import numpy as np
from scipy.integrate import RK23

from Reference_HeatDriveECC_CompensatedBS3 import CompensatedBS3, compensated_add


def finish(solver):
    while solver.status == "running":
        solver.step()
    if solver.status != "finished":
        raise AssertionError("Integrator did not finish")
    return solver


class CompensatedTests(unittest.TestCase):
    def test_summation_recovers_sub_ulp_increments_not_energy_projection(self):
        state, remainder = np.array([1e12]), np.array([0.])
        for _ in range(10000):
            state, remainder = compensated_add(state, np.array([1e-6]), remainder)
        self.assertEqual(state[0], 1e12+.01)

    def test_nonzero_physical_increments_not_forced_to_balance(self):
        sol = finish(CompensatedBS3(lambda t, y: np.array([1., 2.]), 0., np.zeros(2), 2., max_step=.005))
        np.testing.assert_allclose(sol.y, [2., 4.], atol=1e-14, rtol=0)

    def test_affine_energy_growth_and_dense_clock_against_exact_solution(self):
        sol = CompensatedBS3(lambda t, y: np.array([t*t, -2*t*t]), 0., np.array([2., 3.]), 1., max_step=.005)
        while sol.status == "running":
            sol.step()
            mid = .5*(sol.t_old+sol.t)
            np.testing.assert_allclose(sol.dense_output()(mid), [2+mid**3/3, 3-2*mid**3/3], atol=2e-14, rtol=0)
        np.testing.assert_allclose(sol.y, [2+1/3, 3-2/3], atol=2e-14, rtol=0)

    def test_rejected_trials_do_not_consume_summation_remainder(self):
        sol = finish(CompensatedBS3(lambda t, y: y, 0., np.array([1.]), 1., first_step=.9,
                                   rtol=1e-10, atol=1e-12))
        reference = finish(RK23(lambda t, y: y, 0., np.array([1.]), 1., first_step=.9, rtol=1e-10, atol=1e-12))
        self.assertGreater(sol.nfev, 100)
        np.testing.assert_allclose(sol.y, [np.e], rtol=2e-10)
        np.testing.assert_allclose(sol.y, reference.y, rtol=1e-12, atol=1e-12)

    def test_numerical_remainder_is_carried_across_stage_boundary(self):
        f = lambda t, y: np.array([1e-4])
        one = finish(CompensatedBS3(f, 0., np.array([1e12]), 1., max_step=.005))
        two = finish(CompensatedBS3(f, 1., one.y, 2., max_step=.005, compensation=one.compensation))
        full = finish(CompensatedBS3(f, 0., np.array([1e12]), 2., max_step=.005))
        np.testing.assert_array_equal(two.y, full.y)


if __name__ == "__main__":
    unittest.main()
