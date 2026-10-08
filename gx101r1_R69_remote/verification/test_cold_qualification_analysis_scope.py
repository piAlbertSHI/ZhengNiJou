import copy
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from HeatDriveECC_DiagnosticAnalysisScope import diagnostic_arms


class ColdQualificationAnalysisScopeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'native').mkdir()
        self.execution = dict(diagnostic_state_options={'mode': 'restore_preflight'},
                              requested_arms=['native'], requested_arm_collection_pass=True,
                              collection_pass=False, state_restore_preflight_pass=True,
                              start_time_s=0, stop_time_s=20, cycle_count=2,
                              checkpoint_saved=True, c200_state_imported=False,
                              production_recovery_allowed=False, error_message='', execution_commit='a'*40)
        self.mechanism = dict(execution_commit='a'*40, mechanism_pass=True,
                              checks={str(i): True for i in range(73)},
                              directional_pressure_observation={'pass': True}, observation_sha256='HASH')
        self.write('cold_mechanism_audit.json', self.mechanism)
        self.write('native_ledger_persistence.json', dict(all_trace_values_clock_units_metadata_exact=True,
                                                        native_trace_count=1262))
        self.write('state_restore_preflight.json', dict(same_model_restore_preflight_pass=True,
                                                      source_operating_point_sha256='HASH'))
        self.write('diagnostic_state_capture.json', dict(operating_point_sha256='HASH'))
        self.write('arm_completion.json', dict(execution_commit='a'*40, observation_sha256='HASH'))

    def write(self, name, value):
        (self.root / 'native' / name).write_text(json.dumps(value), encoding='utf-8')

    @patch('HeatDriveECC_DiagnosticAnalysisScope.sha256', return_value='HASH')
    def test_complete_cold_scope_is_one_arm_not_a_resume(self, _):
        self.assertEqual(diagnostic_arms(self.root, self.execution), ('native',))

    def test_nonterminal_or_partial_collection_is_rejected(self):
        for key, value in [('error_message', 'terminated'), ('state_restore_preflight_pass', False),
                           ('requested_arm_collection_pass', False), ('start_time_s', 20)]:
            execution = copy.deepcopy(self.execution)
            execution[key] = value
            with self.assertRaises(ValueError):
                diagnostic_arms(self.root, execution)

    @patch('HeatDriveECC_DiagnosticAnalysisScope.sha256', return_value='HASH')
    def test_truthy_string_cannot_hide_failed_predicate(self, _):
        self.mechanism['checks']['0'] = 'false'
        self.write('cold_mechanism_audit.json', self.mechanism)
        with self.assertRaises(ValueError):
            diagnostic_arms(self.root, self.execution)

    @patch('HeatDriveECC_DiagnosticAnalysisScope.sha256', return_value='HASH')
    def test_incomplete_marker_forbids_source_authority(self, _):
        (self.root / 'INCOMPLETE_DO_NOT_RESUME.json').write_text('{}')
        with self.assertRaises(ValueError):
            diagnostic_arms(self.root, self.execution)


if __name__ == '__main__':
    unittest.main()
