import unittest

import numpy as np

from coupled_cooling.demo import demo_model, run
from coupled_cooling.material import MaterialThermodynamics
from coupled_cooling.transport import advective_faces


class ReferenceTests(unittest.TestCase):
    def test_temperature_enthalpy_round_trip_and_domain_rejection(self):
        fluid = demo_model().fluids["SMA"]
        t = np.linspace(272., 415., 50)
        np.testing.assert_allclose(fluid.temperature(fluid.enthalpy(t)), t, rtol=0, atol=1e-12)
        with self.assertRaises(ValueError):
            fluid.enthalpy(260.)

    def test_reversing_transport_mirrors_flux_not_resident_state(self):
        state = np.array([298., 301., 311., 319.])
        left, right = 295., 330.
        sent = advective_faces(state, -.015, left, right, limiter="MC")
        flipped = advective_faces(state[::-1], .015, right, left, limiter="MC")
        np.testing.assert_array_equal(sent, -flipped[::-1])
        np.testing.assert_array_equal(state, [298., 301., 311., 319.])

    def test_fixed_cold_demo_has_mass_energy_and_passive_work_closure(self):
        outcome = run()
        self.assertEqual(outcome["duration_s"], 10.)
        self.assertAlmostEqual(outcome["cold_reservoir_K"], 298.15)
        self.assertGreater(abs(outcome["cold_reservoir_reaction_J"]), 1e-6)
        self.assertLess(abs(outcome["net_energy_residual_J"]), 1e-7)
        self.assertLess(abs(outcome["SE_mass_residual_kg"]), 1e-14)
        self.assertLess(abs(outcome["mechanical_exchange_residual_J"]), 1e-9)
        self.assertTrue(all(0 <= x <= 1 for x in outcome["phase_fraction_mean"].values()))

    def test_invalid_time_grid_is_rejected(self):
        with self.assertRaises(ValueError):
            run(step_s=.013)

    def test_thermodynamic_identity(self):
        model = MaterialThermodynamics(60e9, 30e9, .04, 6500., 470., 200e6, 303.15, 6e6)
        temperature = np.array([295., 303.15, 320.])
        result = model.evaluate(temperature, .025, .43)
        np.testing.assert_allclose(result["internal_energy_J_m3"],
            result["free_energy_J_m3"] + temperature*result["entropy_J_m3K"], atol=1e-8)


if __name__ == "__main__":
    unittest.main()
