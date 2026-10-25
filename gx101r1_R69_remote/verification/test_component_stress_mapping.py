import json
from pathlib import Path
import unittest

import fitz
import numpy as np

from Analyze_HeatDriveECC_ComponentStressMapping import stress_hull, red_pixels, implied_SE_mean, tau_upper_bound, tensile_intersection, read_image, TABLE2
from Extract_HeatDriveECC_QianMaterialPaths import extract_trace
from Reference_HeatDriveECC_TwoWayPhase import SingleCrystalMAS


class StressMappingTests(unittest.TestCase):
    def image(self):
        a = np.full((698, 1422, 3), 255, dtype=np.uint8)
        a[449:452, 133:1387] = [180, 15, 20]
        a[469:472, 133:1387] = [200, 25, 20]
        a[90:95, 133:1387] = [200, 25, 20]  # red legend, outside material stress band
        return a

    def test_two_red_branches_are_enclosed_not_averaged(self):
        hull = stress_hull(self.image(), [55., 56.], [133., 1387., 580., 18.])
        self.assertTrue(hull["available"])
        np.testing.assert_allclose(hull["stress_extent_MPa"], [(580-472)*800/562, (580-448)*800/562])

    def test_missing_column_is_not_interpolated(self):
        a = self.image()
        a[:, 714] = 255
        result = stress_hull(a, [55., 56.], [133., 1387., 580., 18.])
        self.assertFalse(result["available"])
        self.assertEqual(result["reason"], "missing_red_column")

    def test_blue_black_and_grey_are_not_red(self):
        a = np.array([[[0, 0, 255], [20, 20, 20], [100, 100, 100], [200, 20, 20]]], dtype=np.uint8)
        np.testing.assert_array_equal(red_pixels(a), [[False, False, False, True]])

    def test_expanded_temperature_box_never_narrows_stress_hull(self):
        a = self.image()
        small = stress_hull(a, [55., 56.], [133., 1387., 580., 18.])
        large = stress_hull(a, [54., 57.], [133., 1387., 580., 18.])
        self.assertLessEqual(large["stress_extent_MPa"][0], small["stress_extent_MPa"][0])
        self.assertGreaterEqual(large["stress_extent_MPa"][1], small["stress_extent_MPa"][1])

    def test_force_displacement_inverse_does_not_use_SE_end_average(self):
        c = TABLE2
        xa, xr = .4, .7
        s = c["E_Pa"]*c["transformation_strain"]*(c["L_SMA_m"]*(1-xa)-c["L_SE_m"]*xr)/(c["L_SMA_m"]+c["L_SE_m"]*c["area_SMA_m2"]/c["area_SE_m2"])/1e6
        r = implied_SE_mean([xa, xa], [s, s])
        np.testing.assert_allclose(r["unclipped_range"], [xr, xr], atol=2e-15)
        self.assertFalse(r["measured_SE_mean"])
        self.assertFalse(r["SMA_curve_is_known_axial_mean"])

    def test_incompatible_mean_hypothesis_is_reported_not_clipped_to_pass(self):
        r = implied_SE_mean([1., 1.], [100., 100.])
        self.assertLess(r["unclipped_range"][1], 0.)
        self.assertIsNone(r["physical_intersection"])

    def test_pixel_error_box_can_cross_zero_without_a_compressive_state(self):
        original = [-1.4234875444839858, 44.12811387900356]
        self.assertEqual(tensile_intersection(original), [0., original[1]])
        self.assertEqual(original[0], -1.4234875444839858)
        self.assertIsNone(tensile_intersection([-4., -1.]))

    def test_reverse_coefficient_does_not_require_forward_well_domain(self):
        m = SingleCrystalMAS(30e9, 30e9, 3e-26, .1)
        self.assertGreater(float(m.reverse_coefficient(300., 0., -1e8)), 0.)
        with self.assertRaises(ValueError):
            m.coefficients(300., 0., -1e8, -1e8)
        _, old = m.coefficients(330., 100e6, 150e6, 120e6)
        np.testing.assert_allclose(m.reverse_coefficient(330., 100e6, 120e6), old, rtol=3e-15)

    def test_coefficient_maximum_bound_over_rectangle(self):
        m = SingleCrystalMAS(30e9, 30e9, 3e-26, 1.)
        t = np.linspace(320., 350., 31)[:, None]
        s = np.linspace(10e6, 150e6, 31)[None, :]
        actual = m.reverse_coefficient(t, s, TABLE2["C_M_Pa_K"]*(t-TABLE2["SMA_T_Ms_K"]))
        bound = tau_upper_bound(3e-26, 350., 10., 1., 1.)
        self.assertLessEqual(float(actual.max()), bound*(1+1e-14))

    def test_tau_upper_bound_units_at_zero_barrier_coordinate(self):
        self.assertAlmostEqual(tau_upper_bound(3e-26, TABLE2["SMA_T_Ms_K"], 0., .5, 2.), .25)

    def test_custom_times_invalid_and_no_pixels_never_become_guides(self):
        white = np.full((735, 1541, 3), 255, dtype=np.uint8)
        with self.assertRaises(ValueError):
            extract_trace(white, "temperature", [.7, .6])
        with self.assertRaises(ValueError):
            extract_trace(white, "temperature", [np.nan])
        record = extract_trace(white, "temperature", [.6, .7])
        self.assertEqual(record["measured"], [])
        self.assertEqual(len(record["missing"]), 2)

    def test_custom_sampling_did_not_change_default_frozen_source_extraction(self):
        root = Path(__file__).resolve().parents[1]/"outputs_storage_audit"
        r = json.loads((root/"material_component_paths_20261026_r3/Q01_material_pixel_paths.json").read_text(encoding="utf-8"))
        with fitz.open(r["source"]) as d:
            for kind, height in (("phase", 805), ("temperature", 735)):
                original = next(v for v in r["traces"] if v["source_figure"] == (3 if kind == "phase" else 4))
                self.assertEqual(extract_trace(read_image(d, 6, (1541, height)), kind), original)

    def test_saved_hull_support_is_actual_red_source_not_legend_or_black_lines(self):
        root = Path(__file__).resolve().parents[1]/"outputs_storage_audit"
        r = json.loads((root/"material_stress_mapping_20261026_r2/component_stress_constraints.json").read_text(encoding="utf-8"))
        with fitz.open(r["input_dependencies"][0]["path"]) as d:
            image = read_image(d, 7, (1422, 698))
            mask = red_pixels(image)
            for p in r["pairs"]:
                for col, lo, hi in p["stress_hull"]["support_column_min_max_rows"]:
                    self.assertTrue(mask[lo, col])
                    self.assertTrue(mask[hi, col])
                    self.assertGreater(lo, 400)
                self.assertEqual(tensile_intersection(p["stress_extent_MPa_including_axis_shift"]), p["tensile_stress_intersection_MPa"])
        self.assertEqual(len(r["pairs"]), 16)


if __name__ == "__main__":
    unittest.main()
