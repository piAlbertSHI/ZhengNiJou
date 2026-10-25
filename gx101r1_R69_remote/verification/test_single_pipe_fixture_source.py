"""Static source/data-transcription checks; actual component runtime is separate."""
from pathlib import Path
import re
import unittest

import numpy as np


ROOT = Path(__file__).resolve().parent


def literal(source, name, occurrence=0):
    matches = list(re.finditer(r"\b" + re.escape(name) + r"\s*=\s*\[(.*?)\]", source, re.S))
    text = re.sub(r"\.\.\.|%[^\n]*", " ", matches[occurrence].group(1))
    tokens = re.split(r"[;,\s]+", text.strip())
    return np.array([float(token) for token in tokens if token])


class SinglePipeFixtureSourceTests(unittest.TestCase):
    def setUp(self):
        self.fixture = (ROOT / "Run_HeatDriveECC_SinglePipeHeatStep.m").read_text(encoding="utf-8")
        self.builder = (ROOT.parent / "Build_HeatDriveECC_EighthRound_Simulink_Model.m").read_text(encoding="utf-8")

    def test_water_transport_vectors_match_actual_builder(self):
        np.testing.assert_array_equal(literal(self.fixture, "viscosity"), literal(self.builder, "nu_water_mm2_per_s"))
        np.testing.assert_array_equal(literal(self.fixture, "conductivity"), literal(self.builder, "k_water_mW_per_mK"))

    def test_glycol_transport_vectors_match_actual_builder(self):
        np.testing.assert_array_equal(literal(self.fixture, "density"), literal(self.builder, "rho_se_kg_per_m3"))
        np.testing.assert_array_equal(literal(self.fixture, "viscosity", 1), literal(self.builder, "mu_se_mPa_s"))
        np.testing.assert_array_equal(literal(self.fixture, "conductivity", 1), literal(self.builder, "k_se_mW_per_mK"))

    def test_native_component_not_replaced_by_probe(self):
        self.assertIn("'fl_lib/Thermal Liquid/Elements/Pipe (TL)'", self.fixture)
        self.assertIn("native_probe_equivalence_pass", self.fixture)
        self.assertIn("'SaveState','off','SaveFinalState','off','LoadInitialState','off'", self.fixture)
        self.assertNotIn("Build_HeatDriveECC_EighthRound_Simulink_Model(options", self.fixture)
        self.assertNotIn("setInitialState(", self.fixture)


if __name__ == "__main__":
    unittest.main()
