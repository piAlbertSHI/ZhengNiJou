import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


class PressureDomainClosureTests(unittest.TestCase):
    def test_real_table_domain_not_a_lowered_acceptance_threshold(self):
        source = (ROOT / 'Configure_HeatDriveECC_PressureCommandDomain.m').read_text(encoding='utf-8')
        self.assertIn("get_param(block,'p_min_1D')", source)
        self.assertIn("get_param(block,'p_max_1D')", source)
        self.assertIn('max([lower,options.validation.minimum_valid_liquid_pressure_MPa])', source)
        self.assertNotIn("set_param(", source)
        self.assertIn('A stale domain closure contract', source)

    def test_only_exact_qualified_component_and_source(self):
        source = (ROOT / 'Audit_HeatDriveECC_ManifoldMask.m').read_text(encoding='utf-8')
        self.assertIn("'ecc_inventory_endpoint_lib'", source)
        self.assertIn('strcmp(file_hash(actual),source_sha256)', source)
        self.assertIn('pass=common && geometry && source_bound', source)
        self.assertIn("'inventory_runtime_gate_evaluated',false", source)

    def test_safe_configuration_is_not_trajectory_or_recovery_approval(self):
        source = (ROOT / 'verification/Verify_HeatDriveECC_DomainComponentClosure.m').read_text(encoding='utf-8')
        self.assertIn('~before.validation.article_component_pipe_UA_audit.pressure.ok', source)
        self.assertIn("'actual_trajectory_pressure_verified',false", source)
        self.assertIn("'production_recovery_allowed',false", source)
        self.assertIn('An undeclared controller/material/geometry option changed', source)


if __name__ == '__main__':
    unittest.main()
