import unittest

from Audit_HeatDriveECC_10sSeedGate import classify, late_convergence_gate, only_stage4_tracking_failed


def _flow(pass_value=True):
    solid = {
        "all_node_phase_min": 0.0,
        "all_node_phase_max": 1.0,
        "selected_solid_energy_gate": pass_value,
    }
    gates = [{"component": material, "stage": stage, "selected_flow_gate": pass_value}
             for material, stages in (("SMA", (1,2,3,4)), ("SE", (2,4))) for stage in stages]
    return {
        "schema": "heatdrive_ecc_cold_buffer_coupled_audit_v2",
        "evidence_audit_pass": pass_value,
        "declared_window_numerical_gates_pass": pass_value,
        "trajectory_compiled_inventory_gate": pass_value,
        "local_inventory_conservation_pass": pass_value,
        "strict_initial_coordinate_match": pass_value,
        "production_recovery_allowed": False,
        "source_storage_port_checks": [{"passed": pass_value}, {"passed": pass_value}],
        "arms": [
            {"arm": "native", "selected_flow_gates": gates,
             "selected_solid_balances": {"SMA": solid, "SE": solid}},
            {"arm": "conservative", "selected_flow_gates": gates,
             "selected_solid_balances": {"SMA": solid, "SE": solid}},
        ],
    }


def _pressure(pass_value=True):
    return {
        "schema": "heatdrive_ecc_cold_pump_pressure_probe_audit_v1",
        "provenance_gate": pass_value,
        "flow_and_inventory_gate": pass_value,
        "pressure_range_gate": pass_value,
        "hydraulic_diagnostic_gate": pass_value,
        "production_recovery_allowed": False,
        "table4_reproduction_claim": False,
        "arms": [dict(arm=arm, probe_contract_gate=pass_value,
                      probe_signal_gate=pass_value, pressure_range_gate=pass_value,
                      hydraulic_diagnostic_gate=pass_value)
                 for arm in ("native", "conservative")],
    }


def _execution():
    return {
        "schema": "heatdrive_ecc_independent_cold_chamber_v2",
        "collection_pass": True,
        "start_time_s": 0,
        "stop_time_s": 10,
        "cycle_count": 1,
        "c200_state_imported": False,
        "checkpoint_saved": False,
        "production_recovery_allowed": False,
        "cases": [{"arm": "native"}, {"arm": "conservative"}],
    }


class TenSecondSeedGateTests(unittest.TestCase):
    def test_late_window_cannot_authorize_missing_or_unrelated_arms(self):
        execution = _execution()
        for i, case in enumerate(execution["cases"]):
            case["observation_sha256"] = str(i) * 64
        audits = [{
            "schema": "heatdrive_ecc_se_flow_gate_reasonableness_v1",
            "gate_thresholds_unchanged": True,
            "input_contract": {"late_window_fraction": .20},
            "arm": {"observations_sha256": str(i) * 64,
                    "stages": {"stage4": {"late_convergence_tracking_pass": True,
                                           "reverse_flow_fraction": 0.0,
                                           "near_zero_flow_fraction": 0.0}}},
        } for i in range(2)]
        self.assertTrue(late_convergence_gate(audits, execution))
        self.assertFalse(late_convergence_gate(audits[:1], execution))
        self.assertFalse(late_convergence_gate([audits[0], audits[0]], execution))
        audits[1]["arm"]["stages"]["stage4"]["reverse_flow_fraction"] = .01
        self.assertFalse(late_convergence_gate(audits, execution))

    def test_missing_flow_rows_cannot_be_called_stage4_only_failure(self):
        flow = _flow()
        flow["arms"][0]["selected_flow_gates"] = []
        self.assertFalse(only_stage4_tracking_failed(flow))
        self.assertFalse(classify(flow, _pressure(), _execution())["diagnostic_20cycle_seed_eligible"])

    def test_missing_solid_material_cannot_pass_phase_gate(self):
        flow = _flow()
        del flow["arms"][0]["selected_solid_balances"]["SE"]
        self.assertFalse(classify(flow, _pressure(), _execution())["diagnostic_20cycle_seed_eligible"])

    def test_empty_source_port_checks_cannot_pass(self):
        flow = _flow()
        flow["source_storage_port_checks"] = []
        self.assertFalse(classify(flow, _pressure(), _execution())["diagnostic_20cycle_seed_eligible"])

    def test_pass_authorizes_only_fresh_20_cycle_seed(self):
        result = classify(_flow(), _pressure(), _execution())
        self.assertTrue(result["diagnostic_20cycle_seed_eligible"])
        self.assertFalse(result["periodic_steady_state"])
        self.assertFalse(result["production_recovery_allowed"])
        self.assertFalse(result["outer_solve_eligible"])

    def test_any_failed_gate_rejects_seed(self):
        result = classify(_flow(False), _pressure(), _execution())
        self.assertFalse(result["diagnostic_20cycle_seed_eligible"])
        self.assertIn("10 s flow/inventory/initial-coordinate gate failed",
                      result["rejection_reasons"])

    def test_wrong_window_is_rejected(self):
        execution = _execution()
        execution["stop_time_s"] = 0.2
        with self.assertRaises(ValueError):
            classify(_flow(), _pressure(), execution)

    def test_flow_failure_is_not_an_independent_pressure_failure(self):
        pressure = _pressure()
        pressure["flow_and_inventory_gate"] = False
        result = classify(_flow(False), pressure, _execution())
        self.assertTrue(result["pressure_and_hydraulic_gate"])
        self.assertFalse(result["diagnostic_20cycle_seed_eligible"])
        self.assertNotIn("independent pressure/probe/hydraulic gate failed",
                         result["rejection_reasons"])

    def test_missing_probe_evidence_still_rejects_pressure(self):
        pressure = _pressure()
        del pressure["arms"][0]["probe_signal_gate"]
        result = classify(_flow(), pressure, _execution())
        self.assertFalse(result["pressure_and_hydraulic_gate"])
        self.assertFalse(result["diagnostic_20cycle_seed_eligible"])


if __name__ == "__main__":
    unittest.main()
