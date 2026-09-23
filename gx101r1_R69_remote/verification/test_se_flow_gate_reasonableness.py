import json
import tempfile
import unittest
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_SEFlowGateReasonableness import audit_arm


class SEFlowGateReasonablenessTests(unittest.TestCase):
    def test_transition_is_not_called_settled(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            observations = root / "observations.mat"
            execution = root / "execution.json"
            time = np.arange(10001, dtype=float) * 0.001
            with h5py.File(observations, "w") as handle:
                signals = handle.create_group("signals")
                for name in (
                    "mass_flow_v1_cold_inlet_kgps",
                    "mass_flow_v4_hot_inlet_kgps",
                ):
                    group = signals.create_group(name)
                    group.create_dataset("time_s", data=time.reshape(1, -1))
                    group.create_dataset("values", data=np.full((1, time.size), 0.0032))
            execution.write_text(
                json.dumps(
                    {
                        "diagnostic_branch_overrides": {
                            "se_stage4_pressure_pi_transition_start_s": 0.0,
                            "se_stage4_pressure_pi_transition_duration_s": 10.0,
                        }
                    }
                ),
                encoding="utf-8",
            )
            result = audit_arm(
                observations,
                json.loads(execution.read_text(encoding="utf-8")),
                0.0032,
                0.15,
                0.30,
                0.15,
                0.05,
            )
            stage4 = result["stages"]["stage4"]
            self.assertTrue(stage4["instantaneous_tracking_gate_pass"])
            self.assertTrue(stage4["controller_transition"]["transition_covers_window"])
            self.assertEqual(
                stage4["tracking_gate_interpretation"],
                "non_settled_transition_window",
            )
            self.assertEqual(
                stage4["transport_gate_decision"],
                "not_defined_by_current_contract",
            )


if __name__ == "__main__":
    unittest.main()
