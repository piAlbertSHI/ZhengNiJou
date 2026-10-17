from pathlib import Path
import unittest


class ColdL8PermissionSourceTests(unittest.TestCase):
    def test_legacy_geometry_code_has_only_the_guarded_append(self):
        repo=Path(__file__).resolve().parents[1]
        actual=(repo/'Check_HeatDriveECC_DiagnosticManifoldGeometry.m').read_text()
        suffix='    if ~allowed\n        allowed=Check_HeatDriveECC_ColdL8ManifoldGeometry(options);\n    end\nend\n'
        self.assertTrue(actual.endswith(suffix))
        self.assertIn('if allowed, return; end',actual)
        self.assertIn('ismember(branch.cold_manifold_inventory_volume_factor,[1 0.1])',actual)

    def test_joint_permission_requires_the_actual_27_fields_and_cold_scope(self):
        source=(Path(__file__).parent/'Check_HeatDriveECC_ColdL8ManifoldGeometry.m').read_text()
        for token in ('numel(fields)==27','~options.simulation.persist_model_configuration',
                      'isempty(options.simulation.resume_checkpoint_path)','c.parameter_source_configuration_sha256',
                      'isequaln(v,r.after)','[.9 1.1]'):
            self.assertIn(token,source)

    def test_source_delta_exception_is_exact_not_a_generic_whitelist(self):
        source=(Path(__file__).parent/'Review_HeatDriveECC_ConstructorSourceDelta.m').read_text()
        self.assertIn('isequal(current,[prefix suffix])',source)
        self.assertIn('isempty(setdiff(changed,{checker}))',source)


if __name__=='__main__':unittest.main()
