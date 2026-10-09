import unittest
from pathlib import Path


class ConstitutiveStabilitySourceTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(__file__).resolve().parents[1]

    def test_stable_branch_is_explicit_and_default_is_unchanged(self):
        interface = (self.root / "Integrate_HeatDriveECC_Constitutive21_Interface.m").read_text()
        step = (self.root / "HeatDriveECC_ConstitutiveStateVectorStep21_StableDiagnostic.m").read_text()
        runner = (self.root / "verification" / "Run_HeatDriveECC_StableConstitutiveDiagnosticSegment.m").read_text()
        self.assertIn("HeatDriveECC_ConstitutiveStateVectorStep21", interface)
        self.assertIn("diagnostic_step_function", interface)
        self.assertIn("Integrate_HeatDriveECC_StableConstitutiveSample", step)
        self.assertIn("Never overwrite a stable constitutive diagnostic", runner)
        self.assertIn("production_recovery_allowed',false", runner)

    def test_prototype_does_not_use_synthetic_phase_smoothing(self):
        integrator = (self.root / "verification" / "Integrate_HeatDriveECC_StableConstitutiveSample.m").read_text()
        bound = (self.root / "verification" / "HeatDriveECC_ConstitutiveStabilityBound.m").read_text()
        self.assertIn("phase_front_smoothing_1_per_s==0", bound)
        self.assertIn("energy(:,k)=energy(:,k)+audit.", integrator)
        self.assertNotIn("phase_laplacian_neumann", integrator)

    def test_stable_branch_is_not_authorized_as_production_recovery(self):
        runner = (self.root / "verification" / "Run_HeatDriveECC_StableConstitutiveDiagnosticSegment.m").read_text()
        self.assertIn("production_recovery_allowed',false", runner)
        self.assertIn("source_state_edited',false", runner)
        self.assertIn("ismember(substeps,[32 64])", runner)
