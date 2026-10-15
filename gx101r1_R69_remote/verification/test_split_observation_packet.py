from pathlib import Path
import unittest

from Verify_HeatDriveECC_ObservationPacket import reviewed_mechanism, validate_manifest


class SplitObservationPacketTests(unittest.TestCase):
    def base(self):
        return dict(schema='heatdrive_ecc_split_observation_packet_v1', window_s=[620, 640],
                    simulation_returned_without_error=True, source_state_edited=False,
                    history_cap_cycles=2, state_history_cap_cycles=11, strict_vendor_restore=True,
                    production_recovery_allowed=False)

    def test_full_reference_has_twenty_actual_seconds(self):
        self.assertEqual(validate_manifest(self.base()), (620, 640))

    def test_prefix_and_suffix_have_complete_cycles(self):
        for window in ([620, 630], [630, 640]):
            record=self.base();record['window_s']=window
            self.assertEqual(validate_manifest(record), tuple(window))

    def test_logging_changes_are_not_silently_accepted(self):
        for key, value in (('history_cap_cycles', 10), ('state_history_cap_cycles', 2)):
            record=self.base();record[key]=value
            with self.assertRaises(ValueError):validate_manifest(record)

    def test_failed_state_or_relaxed_vendor_policy_rejected(self):
        for key, value in (('simulation_returned_without_error', False), ('source_state_edited', True),
                           ('strict_vendor_restore', False), ('production_recovery_allowed', True)):
            record=self.base();record[key]=value
            with self.assertRaises(ValueError):validate_manifest(record)

    def test_prepared_twenty_cycle_target_is_not_completed_evidence(self):
        record=self.base();record['window_s']=[620, 820]
        with self.assertRaises(ValueError):validate_manifest(record)

    def test_incomplete_or_off_phase_packet_rejected(self):
        for window in ([620, 629.999], [620.001, 630.001], [640, 620]):
            record=self.base();record['window_s']=window
            with self.assertRaises(ValueError):validate_manifest(record)

    def test_default_runner_remains_single_sim_path(self):
        source=(Path(__file__).parent/'Run_HeatDriveECC_ColdChamberDiagnostic.m').read_text(encoding='utf-8')
        self.assertIn('if nargin<26, observation_options=struct(); end',source)
        self.assertIn('if ~isempty(fieldnames(observation_options))',source)
        self.assertEqual(source.count('output=sim(input);'), 1)

    def test_prefix_is_gated_and_hash_checked_before_suffix_load(self):
        source=(Path(__file__).parent/'Verify_HeatDriveECC_SplitObservation.m').read_text(encoding='utf-8')
        self.assertIn("assert(gate.gate_pass,'A failed packet cannot propagate.')",source)
        self.assertLess(source.index('prefix_manifest.complete_OP_sha256'), source.index('restored=load('))
        self.assertNotIn("'warning'",source)

    def test_history_guard_accepts_actual_numeric_API_without_changing_limit(self):
        source=(Path(__file__).parent/'Verify_HeatDriveECC_SplitObservation.m').read_text(encoding='utf-8')
        self.assertIn('Resolve_HeatDriveECC_ObservationCount(native_history)==20002',source)
        self.assertIn('Resolve_HeatDriveECC_ObservationCount(state_history)==110002',source)
        self.assertNotIn("str2double(get_param(model,'SimscapeLogDataHistory'))",source)

    def review_fixture(self):
        checks={'qian_numerical_time_step_contract':False, **{f'physical_{i}':True for i in range(72)}}
        proof=dict(schema='heatdrive_ecc_observation_provenance_review_v1', mechanism_pass=True,
            other_72_predicates_unchanged=True, simulation_executed=False, operating_point_loaded=False,
            source_state_edited=False, production_recovery_allowed=False, reference_comparison_only=True,
            input_sha256={'original_manifest':'A'*64}, metadata_fields_added=['solver','fixed_step_s','simulation_mode'],
            actual_configuration={'solver':'ode3','fixed_step_s':.001,'simulation_mode':'accelerator'},
            checks=dict(checks,qian_numerical_time_step_contract=True))
        return dict(checks=checks,passed=False),proof

    def test_missing_metadata_review_does_not_change_other_predicates(self):
        original,proof=self.review_fixture()
        self.assertTrue(reviewed_mechanism(original,proof,'A'*64)['passed'])
        self.assertFalse(original['checks']['qian_numerical_time_step_contract'])

    def test_real_physical_failure_cannot_be_promoted_by_metadata_review(self):
        original,proof=self.review_fixture();original['checks']['physical_0']=False
        with self.assertRaises(ValueError):reviewed_mechanism(original,proof,'A'*64)

    def test_reference_review_requires_same_source_manifest(self):
        original,proof=self.review_fixture()
        with self.assertRaises(ValueError):reviewed_mechanism(original,proof,'B'*64)

    def test_changed_time_step_cannot_be_called_provenance_only(self):
        original,proof=self.review_fixture();proof['actual_configuration']['fixed_step_s']=.002
        with self.assertRaises(ValueError):reviewed_mechanism(original,proof,'A'*64)

    def test_native_packet_export_uses_measured_interval_without_changing_log_cap(self):
        source=(Path(__file__).parent/'Verify_HeatDriveECC_SplitObservation.m').read_text(encoding='utf-8')
        self.assertIn('native=slice_traces(native,a,b);source_traces=slice_traces(source_traces,a,b);',source)
        self.assertNotIn("setModelParameter('SimscapeLogDataHistory'",source)


if __name__ == '__main__':unittest.main()
