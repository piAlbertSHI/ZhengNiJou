import unittest

from Audit_HeatDriveECC_ColdBufferCoupled import (
    CALIBRATION_MIRROR_PRODUCERS, ZERO_BASED_OFFSET_PRODUCERS,
    ENDPOINT_CHAMBER_PRODUCERS, INITIAL_FLUX_COMPENSATION_PRODUCERS,
    LAYERED_COLD_OBSERVATION_PRODUCER,
)
from Audit_HeatDriveECC_ColdPumpPressureProbes import PRODUCERS


class LayeredColdProducerTests(unittest.TestCase):
    def test_exact_identity_only(self):
        producer = LAYERED_COLD_OBSERVATION_PRODUCER
        self.assertEqual(len(producer), 40)
        for allowed in (CALIBRATION_MIRROR_PRODUCERS, ZERO_BASED_OFFSET_PRODUCERS,
                        ENDPOINT_CHAMBER_PRODUCERS, INITIAL_FLUX_COMPENSATION_PRODUCERS,
                        PRODUCERS):
            self.assertIn(producer, allowed)
            self.assertNotIn(producer[:7], allowed)
            self.assertNotIn(producer[:-1] + "0", allowed)


if __name__ == "__main__":
    unittest.main()
