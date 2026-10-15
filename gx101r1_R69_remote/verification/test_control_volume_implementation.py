import json
import tempfile
import unittest
from pathlib import Path

from Audit_HeatDriveECC_ControlVolumeImplementation import build, sha256


# Declaration snapshot only; unit tests must not require ignored runtime outputs.
BASE_CONTRACT = Path(__file__).resolve().parent / "fixtures" / "control_volume_contract_v2.json"


def cold_fixture(contract_hash: str, *, endpoint: float = 0.0, source_pass: bool = True) -> dict:
    arm = {
        "source_minus_actual_endpoint_storage_J": endpoint,
        "component_groups": {"Pipe (TL)": {"endpoint_energy_residual_J": endpoint}},
        "periodic_steady_state": True,
        "full_device_first_law_verified": True,
    }
    return {
        "contract_sha256": contract_hash,
        "result_sha256": "A" * 64,
        "logged_window_start_s": 0.0,
        "logged_window_stop_s": 10.0,
        "samples": 10001,
        "full_cycle_completed": True,
        "strict_initial_coordinate_match": True,
        "local_inventory_conservation_pass": True,
        "source_storage_port_checks": [{"passed": source_pass}],
        "arms": [dict(arm, arm="native"), dict(arm, source_minus_actual_endpoint_storage_J=0.0, arm="conservative")],
    }


class ControlVolumeImplementationTests(unittest.TestCase):
    def write_contract(self, directory: Path) -> Path:
        contract = json.loads(BASE_CONTRACT.read_text(encoding="utf-8"))
        contract.update(
            {
                "contract_role": "structure_only_not_recovery_source",
                "authority": {
                    "frozen_result_sha256": "0" * 64,
                    "frozen_checkpoint_sha256": "1" * 64,
                    "current_model_restore_allowed": False,
                    "rejected_results_may_resume": False,
                    "rejected_results_may_interpolate": False,
                },
                "sampling_contract": {
                    "cycle_period_s": 10,
                    "window_cycles": 10,
                    "complete_cycles_only": True,
                    "endpoint_extrapolation_allowed": False,
                    "native_log_required": True,
                },
            }
        )
        for equation in contract["equations"]:
            equation.update(
                {
                    "window_start_rule": "complete-cycle start",
                    "window_stop_rule": "complete-cycle end",
                    "endpoint_inclusion": "trapz",
                    "quadrature": "trapz",
                    "required_signals": equation["definition"],
                }
            )
        path = directory / "contract.json"
        path.write_text(json.dumps(contract), encoding="utf-8")
        return path

    def run_fixture(self, cold: dict, *, expected_result: str | None = None) -> dict:
        with tempfile.TemporaryDirectory() as directory:
            directory_path = Path(directory)
            contract_path = self.write_contract(directory_path)
            cold_path = directory_path / "cold.json"
            cold_path.write_text(json.dumps(cold), encoding="utf-8")
            return build(contract_path, cold_path, expected_result_sha256=expected_result)

    def test_matching_contract_and_prerequisites_can_reach_implementation_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            contract_path = self.write_contract(Path(directory))
            cold = cold_fixture(sha256(contract_path))
            cold_path = Path(directory) / "cold.json"
            cold_path.write_text(json.dumps(cold), encoding="utf-8")
            result = build(contract_path, cold_path, expected_result_sha256="A" * 64)
        self.assertTrue(result["contract_binding_pass"])
        self.assertTrue(result["cold_prerequisite_gate_pass"])
        self.assertTrue(result["eligibility"]["implementation_control_volume_pass"])

    def test_stale_contract_hash_cannot_be_bound_to_current_contract(self):
        result = self.run_fixture(cold_fixture("B" * 64), expected_result="A" * 64)
        self.assertFalse(result["contract_binding_pass"])
        self.assertFalse(result["eligibility"]["implementation_control_volume_pass"])
        self.assertTrue(
            any("different control-volume contract hash" in reason
                for reason in result["rejection_reasons"])
        )

    def test_failed_source_port_gate_cannot_be_hidden_by_endpoint_closure(self):
        with tempfile.TemporaryDirectory() as directory:
            contract_path = self.write_contract(Path(directory))
            cold = cold_fixture(sha256(contract_path), source_pass=False)
            cold_path = Path(directory) / "cold.json"
            cold_path.write_text(json.dumps(cold), encoding="utf-8")
            result = build(contract_path, cold_path, expected_result_sha256="A" * 64)
        self.assertFalse(result["cold_prerequisite_gate_pass"])
        self.assertFalse(result["eligibility"]["implementation_control_volume_pass"])

    def test_native_endpoint_residual_is_independent_of_conservative_arm(self):
        with tempfile.TemporaryDirectory() as directory:
            contract_path = self.write_contract(Path(directory))
            cold = cold_fixture(sha256(contract_path), endpoint=1e-6)
            cold_path = Path(directory) / "cold.json"
            cold_path.write_text(json.dumps(cold), encoding="utf-8")
            result = build(contract_path, cold_path, expected_result_sha256="A" * 64)
        self.assertFalse(result["native"]["endpoint_inventory_gate_pass"])
        self.assertFalse(result["native"]["endpoint_residual_gate_applicable"])
        self.assertTrue(result["native"]["endpoint_residual_hard_gate_pass"])
        self.assertTrue(result["eligibility"]["implementation_control_volume_pass"])

    def test_complete_boundary_evidence_promotes_endpoint_residual_to_hard_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            contract_path = self.write_contract(Path(directory))
            cold = cold_fixture(sha256(contract_path), endpoint=1e-6)
            cold["all_required_control_volume_observations_complete"] = True
            cold_path = Path(directory) / "cold.json"
            cold_path.write_text(json.dumps(cold), encoding="utf-8")
            result = build(contract_path, cold_path, expected_result_sha256="A" * 64)
        self.assertTrue(result["native"]["endpoint_residual_gate_applicable"])
        self.assertFalse(result["native"]["endpoint_residual_hard_gate_pass"])
        self.assertFalse(result["eligibility"]["implementation_control_volume_pass"])


if __name__ == "__main__":
    unittest.main()
