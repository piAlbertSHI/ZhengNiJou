import unittest

from Audit_HeatDriveECC_GateSemantics import build


def fixture(*, complete=False, flow_pass=False):
    c200 = {
        "all_required_control_volume_observations_complete": complete,
        "contract_structure_complete": True,
        "conflict_detected": True,
        "_source_sha256": "C" * 64,
    }
    flow = {
        "periodic_steady_state": False,
        "table4_reproduction_claim": False,
        "_source_sha256": "F" * 64,
        "arms": [{
            "arm": "native",
            "full_device_first_law_verified": complete,
            "source_minus_actual_endpoint_storage_J": 1e-6,
            "selected_flow_gates": [{
                "component": "SE", "stage": 2, "selected_flow_gate": flow_pass,
            }],
        }],
    }
    pressure = {
        "pressure_range_gate": True,
        "hydraulic_diagnostic_gate": True,
        "_source_sha256": "P" * 64,
        "arms": [{"arm": "native"}],
    }
    state = {"contract_completeness_pass": True, "_source_sha256": "S" * 64}
    return c200, flow, pressure, state


class GateSemanticsTests(unittest.TestCase):
    def test_missing_runtime_terms_keep_endpoint_residual_diagnostic_only(self):
        result = build(*fixture(flow_pass=False))
        self.assertFalse(result["endpoint_residual_layer"]["hard_gate_applicable"])
        self.assertFalse(result["physical_seed_layer"]["mechanism_pass_for_finite_diagnostic"])
        self.assertFalse(result["claim_layer"]["table4_claim_allowed"])

    def test_complete_runtime_terms_promote_endpoint_residual_to_hard_gate(self):
        result = build(*fixture(complete=True, flow_pass=True))
        self.assertTrue(result["endpoint_residual_layer"]["hard_gate_applicable"])
        self.assertFalse(result["claim_layer"]["table4_claim_allowed"])


if __name__ == "__main__":
    unittest.main()
