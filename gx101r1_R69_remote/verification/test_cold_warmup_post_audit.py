import unittest

from Audit_HeatDriveECC_ColdWarmupPostAudit import controller_probes_pass, readiness


def fixture(count):
    return {
        "schema": "heatdrive_ecc_stage4_controller_probe_audit_v1",
        "provenance_gate": True, "case_probe_gate": True, "coverage_gate": True,
        "arms": [{"arm": name, "contract_gate": True, "signal_gate": True,
                  "probe_count": count} for name in ("native", "conservative")],
    }


class ColdWarmupPostAuditTests(unittest.TestCase):
    def test_pending_boundary_evidence_is_not_mechanism_failure(self):
        result = readiness(True, False, False)
        self.assertTrue(result["controlled_operating_condition_pass"])
        self.assertEqual(result["next_stage"], "collect_periodic_and_full_boundary_evidence")
        self.assertFalse(result["performance_evidence_complete"])

    def test_measured_tracking_failure_must_be_repaired_before_performance(self):
        self.assertEqual(readiness(False, True, True)["next_stage"],
                         "repair_controlled_operating_condition")

    def test_complete_boundary_still_requires_paired_endpoints(self):
        self.assertEqual(readiness(True, True, True)["next_stage"],
                         "review_performance_window_and_paired_endpoints")
    def test_complete_v4_is_not_rejected_for_having_extra_probes(self):
        self.assertTrue(controller_probes_pass(fixture(24)))

    def test_legacy_contract_is_supported(self):
        self.assertTrue(controller_probes_pass(fixture(17)))

    def test_missing_arm_and_unknown_schema_size_are_rejected(self):
        value = fixture(24)
        value["arms"].pop()
        self.assertFalse(controller_probes_pass(value))
        self.assertFalse(controller_probes_pass(fixture(25)))

    def test_failed_coverage_is_not_hidden_by_probe_count(self):
        value = fixture(24)
        value["coverage_gate"] = False
        self.assertFalse(controller_probes_pass(value))
