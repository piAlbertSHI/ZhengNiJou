import unittest
import numpy as np

from Analyze_HeatDriveECC_EnthalpyTransport import profile_inventory_checks, compare_profiles
from Reference_HeatDriveECC_ConstrainedEnthalpy import constrained_midpoint_step
from test_enthalpy_transport import test_bed


class EnthalpyReviewTests(unittest.TestCase):
    def test_primary_conservation_cannot_hide_wrong_EOS_temperature(self):
        bed = test_bed()
        initial = bed.initial_state()
        final, _ = constrained_midpoint_step(bed, initial, .0032, 393.15, 303.15, .001)
        state = np.array([initial, final])
        props = [bed.unpack(y) for y in state]
        temp = np.array([np.r_[p["T"], p["solid_T"]] for p in props])
        pressure = np.array([p["p"] for p in props])
        check = profile_inventory_checks(state, temp, pressure, bed)
        self.assertTrue(check["saved_inventory_and_EOS_checks_pass"])
        temp[1, 0] += .1
        self.assertFalse(profile_inventory_checks(state, temp, pressure, bed)["saved_inventory_and_EOS_checks_pass"])

    def test_compare_profiles_does_not_mix_mass_and_energy_units(self):
        fields = {"time_s": np.array([0., 1.]), "conserved_diagnostic_profiles": np.zeros((2, 11)),
            "fluid_and_solid_temperature_K": np.zeros((2, 6)), "pressure_Pa": np.zeros((2, 3))}
        other = {name: value.copy() for name, value in fields.items()}
        other["conserved_diagnostic_profiles"][1, 0] = 1e-6
        other["conserved_diagnostic_profiles"][1, 3] = 2.
        result = compare_profiles(fields, other)
        self.assertEqual(result["mass_coordinates_kg"], 1e-6)
        self.assertEqual(result["fluid_energy_coordinates_J"], 2.)
        self.assertNotIn("conserved_diagnostic_profiles", result)


if __name__ == "__main__":
    unittest.main()
