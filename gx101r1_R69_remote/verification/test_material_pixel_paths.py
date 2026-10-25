import unittest

import numpy as np

from Extract_HeatDriveECC_QianMaterialPaths import pixel_group
from Analyze_HeatDriveECC_PhaseReversals import sampled_turns


class PixelPathTests(unittest.TestCase):
    def test_two_black_curves_are_not_averaged_into_a_fake_measurement(self):
        selected, reason = pixel_group(np.array([10, 11, 12, 20, 21]))
        self.assertIsNone(selected)
        self.assertEqual(reason, "multiple_dark_ridges")

    def test_missing_pixels_do_not_become_guide_values(self):
        selected, reason = pixel_group(np.array([], dtype=int))
        self.assertIsNone(selected)
        self.assertEqual(reason, "no_dark_pixels")

    def test_long_annotation_stroke_is_rejected(self):
        selected, reason = pixel_group(np.arange(30))
        self.assertIsNone(selected)
        self.assertIn("vertical_stroke", reason)

    def test_single_ridge_retains_its_actual_pixels(self):
        pixels = np.array([10, 11, 12])
        selected, reason = pixel_group(pixels)
        np.testing.assert_array_equal(selected, pixels)
        self.assertIsNone(reason)

    def test_steep_real_curve_is_not_rejected_by_flat_curve_stroke_width(self):
        pixels = np.arange(30)
        selected, reason = pixel_group(pixels, max_vertical_pixels=35)
        np.testing.assert_array_equal(selected, pixels)
        self.assertIsNone(reason)

    def test_sampled_turn_retains_plateau_time_bracket_not_invented_root(self):
        events = sampled_turns(np.arange(5.), np.array([0., .3, .3, .3, .1]), 1e-9)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["time_bracket_s"], [1., 3.])
        self.assertEqual(events[0]["direction_before"], 1)
        self.assertEqual(events[0]["direction_after"], -1)

    def test_selected_increment_tolerance_does_not_create_a_turn(self):
        events = sampled_turns(np.arange(5.), np.array([0., .3, .3-1e-12, .5, .7]), 1e-9)
        self.assertEqual(events, [])


if __name__ == "__main__":
    unittest.main()
