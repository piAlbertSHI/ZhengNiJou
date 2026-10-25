import tempfile
from pathlib import Path
import unittest

import numpy as np

from Analyze_HeatDriveECC_ConservativeTransport import nested_metrics, saved_inventory_check, read_case
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Reference_HeatDriveECC_ConservativeTransport import Bed
from Run_HeatDriveECC_ConservativeTransport import SAMPLES_S


class TransportDirectionReviewTests(unittest.TestCase):
    def test_nested_average_not_front_interpolation(self):
        n = 3
        coarse = np.zeros((len(SAMPLES_S), 2*n+1))
        fine = np.zeros((len(SAMPLES_S), 4*n+1))
        fine[:, :6] = [-1., 1., -2., 2., -3., 3.]
        row = nested_metrics(coarse, fine, n)
        self.assertEqual(row["fields"]["fluid"]["max_over_saved_times_mean_abs_difference_K"], 0.)
        self.assertFalse(row["interpolation_used"])

    def test_pointwise_and_mean_errors_are_reported_separately(self):
        n = 3
        coarse = np.zeros((len(SAMPLES_S), 2*n+1))
        fine = np.zeros((len(SAMPLES_S), 4*n+1))
        fine[:, :2] = 3.
        field = nested_metrics(coarse, fine, n)["fields"]["fluid"]
        self.assertEqual(field["max_over_saved_times_mean_abs_difference_K"], 1.)
        self.assertEqual(field["max_over_saved_times_pointwise_difference_K"], 3.)

    def test_energy_pass_cannot_hide_temperature_bound_violation(self):
        bed = Bed(3, 1., 1., 1., 1., 0., 1., 1., 1., 0., 0.)
        values = np.zeros((len(SAMPLES_S), 7))
        values[1, :3] = [-1., 0., 1.]
        checked = saved_inventory_check(values, bed, "SMA")
        self.assertTrue(checked["saved_time_energy_pass"])
        self.assertEqual(checked["saved_time_fluid_bound_violation_K"], 1.)

    def test_changed_raw_and_imported_initial_states_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root/"case.npz"
            values = np.zeros((len(SAMPLES_S), 7))
            values[0, 0] = 1.
            np.savez(path, time_s=SAMPLES_S, temperature_deviations_and_energy=values, cell_centers_m=np.arange(3))
            row = {"file": path.name, "bytes": path.stat().st_size, "sha256": sha256(path)}
            with self.assertRaisesRegex(ValueError, "non-cold"):
                read_case(root, row, 3)
            row["sha256"] = "0"*64
            with self.assertRaisesRegex(ValueError, "changed"):
                read_case(root, row, 3)

    def test_text_bounds_ignore_undrawn_ticks_but_reject_visible_overflow(self):
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        from Analyze_HeatDriveECC_ConservativeTransport import assert_rendered_text_bounds
        fig, ax = plt.subplots(figsize=(4, 3), layout="constrained")
        try:
            ax.plot([0., 1.], [0., 1.])
            ax.set_xlim(0., 1.)
            ax.set_xticks([-.2, 0., .5, 1., 1.2])
            ax.set_xlim(0., 1.)
            assert_rendered_text_bounds(fig)
            fig.text(-.2, .5, "actually outside")
            with self.assertRaisesRegex(ValueError, "Rendered text outside"):
                assert_rendered_text_bounds(fig)
        finally:
            plt.close(fig)


if __name__ == "__main__":
    unittest.main()
