import unittest

import numpy as np

from Audit_HeatDriveECC_Stage4ControllerDynamics import (
    alternating_mode,
    window_metrics,
)


class Stage4ControllerDynamicsTest(unittest.TestCase):
    def setUp(self):
        self.time = np.arange(0.0, 10.001, 0.001)

    def test_production_window_uses_raw_samples(self):
        flow = np.full(self.time.size, 0.0032)
        flow[(self.time >= 8.801) & (self.time <= 9.85)] *= 1.10
        result = window_metrics(self.time, flow)
        self.assertFalse(result["production_instantaneous_gate_pass"])
        self.assertEqual(result["reverse_flow_fraction"], 0.0)

    def test_alternating_mode_detects_command_and_flow_pair(self):
        flow = np.full(self.time.size, 0.0032)
        command = np.zeros(self.time.size)
        mask = (self.time >= 9.84) & (self.time <= 9.90)
        flow[mask & (np.arange(self.time.size) % 2 == 0)] = 0.0003
        flow[mask & (np.arange(self.time.size) % 2 == 1)] = 0.0061
        command[mask & (np.arange(self.time.size) % 2 == 0)] = -0.02
        command[mask & (np.arange(self.time.size) % 2 == 1)] = -0.33
        self.assertTrue(alternating_mode(self.time, flow, command)[
            "alternating_mode_detected"])


if __name__ == "__main__":
    unittest.main()
