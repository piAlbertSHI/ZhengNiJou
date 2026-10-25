import json
from pathlib import Path
import unittest

import fitz
import numpy as np

from Extract_HeatDriveECC_QianMaterialPaths import pixel_group
from Analyze_HeatDriveECC_PhaseReversals import sampled_turns
from Analyze_HeatDriveECC_MaterialRateBounds import interval_bound


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

    def test_log_bound_matches_exact_one_way_decay(self):
        a = {"image_time_s": 0., "pixel_ordinate_extent_plus_one": [.8, .8]}
        b = {"image_time_s": .5, "pixel_ordinate_extent_plus_one": [.8*np.exp(-2.), .8*np.exp(-2.)]}
        result = interval_bound(a, b, 0., "M_to_A")
        self.assertAlmostEqual(result["interval_average_coefficient_lower_bound_per_s"], 4.)

    def test_wider_pixel_boxes_make_rate_bound_weaker_not_stronger(self):
        a = {"image_time_s": 0., "pixel_ordinate_extent_plus_one": [.7, .9]}
        b = {"image_time_s": .5, "pixel_ordinate_extent_plus_one": [.1, .3]}
        result = interval_bound(a, b, .02, "M_to_A")
        self.assertLess(result["interval_average_coefficient_lower_bound_per_s"], np.log(.8/.2)/.5)

    def test_rising_phase_bound_uses_remaining_austenite(self):
        a = {"image_time_s": 0., "pixel_ordinate_extent_plus_one": [.2, .2]}
        b = {"image_time_s": .5, "pixel_ordinate_extent_plus_one": [1-.8*np.exp(-2.), 1-.8*np.exp(-2.)]}
        self.assertAlmostEqual(interval_bound(a, b, 0., "A_to_M")["interval_average_coefficient_lower_bound_per_s"], 4.)

    def test_positive_opposing_flux_respects_integral_bound(self):
        from Reference_HeatDriveECC_TwoWayPhase import frozen_coefficient_step
        a = {"image_time_s": 0., "pixel_ordinate_extent_plus_one": [.8, .8]}
        value = float(frozen_coefficient_step(.8, 2., 7., .2))
        b = {"image_time_s": .2, "pixel_ordinate_extent_plus_one": [value, value]}
        lower = interval_bound(a, b, 0., "M_to_A")["interval_average_coefficient_lower_bound_per_s"]
        self.assertGreater(lower, 0.)
        self.assertLess(lower, 7.)

    def test_actual_registered_measurements_are_black_source_pixels_not_filled_guides(self):
        root = Path(__file__).resolve().parents[1]/"outputs_storage_audit/material_component_paths_20261026_r3"
        record = json.loads((root/"Q01_material_pixel_paths.json").read_text(encoding="utf-8"))
        document = fitz.open(record["source"])
        images = document[6].get_images(full=True)
        for trace in record["traces"]:
            height = 805 if trace["quantity"] == "SMA_xM" else 735
            reference = next(row[0] for row in images if row[2:4] == (1541, height))
            pixmap = fitz.Pixmap(document, reference)
            pixels = np.frombuffer(pixmap.samples, dtype=np.uint8).reshape(height, 1541, 3)
            x0, x20, y0, ytop = trace["axes_pixels_x0_x20_y0_ytop"]
            for point in trace["measured"]:
                color = pixels[int(round(point["pixel_y_median"])), point["pixel_x"]]
                self.assertLess(color.max(), 135)
                self.assertAlmostEqual(point["value"], (y0-point["pixel_y_median"])*trace["axis_ordinate_top"]/(y0-ytop))
                if trace["quantity"] == "SMA_xM":
                    self.assertGreater(point["pixel_ordinate_extent_plus_one"][0], 0.)
                    self.assertLess(point["pixel_ordinate_extent_plus_one"][1], 1.)
        self.assertEqual([len(row["measured"]) for row in record["traces"]], [20, 135])


if __name__ == "__main__":
    unittest.main()
