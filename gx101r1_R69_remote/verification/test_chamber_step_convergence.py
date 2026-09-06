import unittest

import numpy as np

from Audit_HeatDriveECC_ChamberStepConvergence import audit_case, convergence_order, reference_solution, sealed_rhs


def constant_tables(alpha=0):
    return {k: (lambda point, value=v: np.full(len(point), value))
            for k, v in dict(rho=1000., cp=4000., alpha=alpha, beta=2e9).items()}


class ChamberStepTests(unittest.TestCase):
    def test_analytic_no_expansion(self):
        result = reference_solution(constant_tables(), 1e-6, 10, 300, 1e6)
        np.testing.assert_allclose(result.y[:, -1], [302.5, 1e6], rtol=0, atol=1e-9)

    def test_pressure_temperature_derivative_constraint(self):
        derivative = sealed_rhs(constant_tables(.0002), 1e-6, 10)(0, [300, 1e6])
        self.assertAlmostEqual(derivative[1]/derivative[0], 4e5)
        self.assertAlmostEqual(derivative[0], 10/(1e-6*(4e6-300*2e9*.0002**2)))

    def test_heat_sign(self):
        np.testing.assert_allclose(sealed_rhs(constant_tables(), 1e-6, -10)(0, [300, 1e6]), [-2.5, 0])

    def test_invalid_capacity_and_volume(self):
        with self.assertRaises(ValueError):
            sealed_rhs(constant_tables(), -1, 10)
        with self.assertRaises(ValueError):
            sealed_rhs(constant_tables(1), 1, 10)(0, [300, 1e6])

    def test_first_order_not_flat_or_second_order(self):
        self.assertTrue(convergence_order([4, 2, 1])[1])
        self.assertFalse(convergence_order([4, 4, 4])[1])
        self.assertFalse(convergence_order([16, 4, 1])[1])

    def test_zero_or_invalid_error_not_convergence(self):
        for errors in ([0, 0, 0], [1, 2], [1, np.nan, .1], [1, -1, .1]):
            with self.assertRaises(ValueError):
                convergence_order(errors)

    def test_global_only_step_change_rejected(self):
        meta = dict(local_solver_enabled='off', local_solver='NE_BACKWARD_EULER_ADVANCER')
        with self.assertRaises(ValueError):
            audit_case(meta, [], {}, {}, None)

    def test_wrong_heat_and_mass_leak_rejected(self):
        meta = dict(local_solver_enabled='on', local_solver='NE_BACKWARD_EULER_ADVANCER',
                    local_step_s=.001, global_solver='ode3', global_step_s=.001,
                    stop_s=1, initial_pressure_Pa=1e6, heat_source_command_W=-10, expected_Q_H_W=10)
        for flow, heat in ((1e-6, 10), (0, -10)):
            values = dict(mdot_A=np.array([flow]), Phi_A=np.array([0]), Q_H=np.array([heat]))
            with self.assertRaises(ValueError):
                audit_case(meta, [0], values, {}, None)


if __name__ == '__main__':
    unittest.main()
