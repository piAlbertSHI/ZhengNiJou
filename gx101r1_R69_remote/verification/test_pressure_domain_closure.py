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

    def test_cold_analysis_does_not_require_a_nonexistent_restart(self):
        source = (ROOT / 'verification/Make_HeatDriveECC_MechanismWindow.m').read_text(encoding='utf-8')
        self.assertIn('(~provenance.checkpoint_restart_used || provenance.checkpoint_chain_verified)', source)
        self.assertIn('provenance.sim_call_count == physical.sim_call_count', source)

    def test_failed_mechanism_is_preserved_before_state_verification(self):
        source = (ROOT / 'verification/Run_HeatDriveECC_ColdChamberDiagnostic.m').read_text(encoding='utf-8')
        self.assertLess(source.index('Evaluate_HeatDriveECC_ColdMechanism('),
                        source.index('Verify_HeatDriveECC_CoupledStateRestore('))
        self.assertIn('REJECTED_DO_NOT_RESUME.json', source)
        self.assertIn('New bounded cold mechanism failed', source)

    def test_native_persistence_uses_public_supported_api(self):
        source = (ROOT / 'verification/Snapshot_HeatDriveECC_NativeLog.m').read_text(encoding='utf-8')
        self.assertIn('log.savable', source)
        self.assertIn("save(target,'native_log','-v7.3')", source)
        self.assertIn("load(target,'native_log')", source)
        self.assertIn('numel(inventory_paths)==6', source)
        self.assertIn('isequaln(t,s) && isequaln(a,b) && strcmp(u,v)', source)
        self.assertNotIn('interp1', source)
        self.assertIn('simscape.logging.export(log,target)', source)
        self.assertIn('simscape.logging.import(target)', source)
        self.assertIn('log.exportable', source)

    def test_transport_failure_is_not_a_scientific_failure_or_resume_authority(self):
        source = (ROOT / 'verification/Require_HeatDriveECC_BoundedStateCandidate.m').read_text(encoding='utf-8')
        self.assertIn('mechanism.mechanism_pass', source)
        self.assertIn('all(structfun(@logical,mechanism.checks))', source)
        self.assertIn('capture.operating_point_sha256', source)
        self.assertIn("'diagnostic_continuation_allowed',false", source)
        self.assertIn('REJECTED_DO_NOT_RESUME.json', source)


if __name__ == '__main__':
    unittest.main()
