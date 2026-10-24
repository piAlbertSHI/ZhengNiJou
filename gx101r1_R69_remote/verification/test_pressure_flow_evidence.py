import copy
import unittest

from Audit_HeatDriveECC_ColdPumpPressureProbes import flow_inventory_gate


def fixture(stop=200):
    start = max(0, stop - 20)
    execution = dict(execution_commit="a" * 40, simscape_log_window_start_s=start,
                     stop_time_s=stop)
    flow = dict(schema="heatdrive_ecc_cold_buffer_coupled_audit_v2",
                execution_commit=execution["execution_commit"],
                logged_window_start_s=start, logged_window_stop_s=stop,
                evidence_audit_pass=True, declared_window_numerical_gates_pass=True,
                local_inventory_conservation_pass=True, strict_initial_coordinate_match=True,
                production_recovery_allowed=False, full_cycle_completed=stop >= 10,
                source_storage_port_checks=[dict(arm=arm, passed=True)
                                            for arm in ("native", "conservative")])
    if stop < 10:
        flow.update(specific_inventory_onset_probe=True, cold_smoke_numerical_gates_pass=True)
    else:
        routes = [("SMA", i) for i in (1, 2, 3, 4)] + [("SE", 2), ("SE", 4)]
        flow["arms"] = [dict(arm=arm, selected_flow_gates=[
            dict(component=component, stage=stage, selected_flow_gate=True)
            for component, stage in routes]) for arm in ("native", "conservative")]
    return flow, execution


class PressureFlowEvidenceTests(unittest.TestCase):
    def test_complete_full_cycle(self):
        self.assertTrue(flow_inventory_gate(*fixture()))

    def test_explicit_short_onset(self):
        self.assertTrue(flow_inventory_gate(*fixture(1)))

    def test_missing_evidence_rejected(self):
        for field in ("schema", "source_storage_port_checks", "arms", "execution_commit",
                      "logged_window_start_s", "full_cycle_completed"):
            flow, execution = fixture()
            del flow[field]
            self.assertFalse(flow_inventory_gate(flow, execution), field)

    def test_empty_or_duplicate_routes_rejected(self):
        flow, execution = fixture()
        for rows in ([], flow["arms"][0]["selected_flow_gates"][:-1],
                     [flow["arms"][0]["selected_flow_gates"][0]] * 6):
            candidate = copy.deepcopy(flow)
            candidate["arms"][0]["selected_flow_gates"] = rows
            self.assertFalse(flow_inventory_gate(candidate, execution))

    def test_full_cycle_cannot_use_smoke_fallback(self):
        flow, execution = fixture(1)
        execution["stop_time_s"] = flow["logged_window_stop_s"] = 200
        self.assertFalse(flow_inventory_gate(flow, execution))

    def test_wrong_window_producer_or_failed_source_rejected(self):
        for field, value in (("logged_window_stop_s", 190), ("execution_commit", "b" * 40)):
            flow, execution = fixture()
            flow[field] = value
            self.assertFalse(flow_inventory_gate(flow, execution))
        flow, execution = fixture()
        flow["source_storage_port_checks"][0]["passed"] = False
        self.assertFalse(flow_inventory_gate(flow, execution))


if __name__ == "__main__":
    unittest.main()
