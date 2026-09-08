"""Inventory components and boundary work must remain explicit."""
import unittest
from pathlib import Path
import numpy as np
from scipy.interpolate import RegularGridInterpolator

from Audit_HeatDriveECC_ConservativeBufferTrial import inventory
from Audit_HeatDriveECC_ColdCoordinateSmoke import ledger


class ConservativeBufferTests(unittest.TestCase):
    def test_coupled_variant_changes_only_thermal_port_location(self):
        root = Path(__file__).resolve().parent
        original = (root/'simscape_buffer/+ecc_buffer/conservative_buffer.ssc').read_text(encoding='utf-8')
        aligned = (root/'simscape_buffer_coupled/+ecc_buffer_coupled/conservative_buffer.ssc').read_text(encoding='utf-8')
        self.assertEqual(original.replace('% H:left', '% H:right'), aligned)

    def table(self):
        grid = (np.array([270., 330.]), np.array([1e5, 2e6]))
        return {'rho': RegularGridInterpolator(grid, np.full((2, 2), 1000.)),
                'u': RegularGridInterpolator(grid, np.array([[270000., 270000.], [330000., 330000.]])),
                'cp': RegularGridInterpolator(grid, np.full((2, 2), 1000.))}

    def get(self, t, m, depth=.001, g=10):
        return inventory(self.table(), np.asarray(t), np.asarray(m), 1e6, .001, g, 300, depth)

    def test_all_energy_terms(self):
        r = self.get([300.], [.1])
        self.assertAlmostEqual(r['parts']['fluid_internal_energy'][0], 30000)
        self.assertAlmostEqual(r['parts']['environment_pv_energy'][0], 100)
        self.assertAlmostEqual(r['parts']['gravitational_energy'][0], .05)
        self.assertAlmostEqual(r['parts']['auxiliary_energy'][0], 0)
        self.assertAlmostEqual(r['total'][0], 30100.05)
        self.assertAlmostEqual(r['port_pressure'][0], 1001000.)

    def test_auxiliary_capacity_is_nontransported(self):
        a = self.get([301.], [.1]); b = self.get([301.], [.2])
        self.assertEqual(a['capacity'], b['capacity'])
        self.assertEqual(a['parts']['auxiliary_energy'][0], b['parts']['auxiliary_energy'][0])

    def test_no_gravity_or_auxiliary(self):
        r = self.get([301.], [.1], depth=0, g=0)
        self.assertEqual(r['parts']['gravitational_energy'][0], 0)
        self.assertEqual(r['parts']['auxiliary_energy'][0], 0)

    def test_heating_and_cooling_inventory(self):
        hot = self.get([300., 301.], [.1, .1])
        cold = self.get([300., 299.], [.1, .1])
        self.assertAlmostEqual(np.diff(hot['total'])[0], 101.)
        self.assertAlmostEqual(np.diff(cold['total'])[0], -101.)

    def test_open_flow_environment_work_not_optional(self):
        r = self.get([300., 300.], [.1, .101])
        self.assertAlmostEqual(np.diff(r['parts']['environment_pv_energy'])[0], 1.)
        full = r['total']; energy = np.diff(full)[0]
        good = ledger([0, 1], [.1, .101], full, [.001, .001], [energy, energy])
        missing = ledger([0, 1], [.1, .101], full-r['parts']['environment_pv_energy'], [.001, .001], [energy, energy])
        self.assertTrue(good['energy_closure_pass'])
        self.assertFalse(missing['energy_closure_pass'])

    def test_nonphysical_inventory_rejected(self):
        with self.assertRaises(ValueError):
            self.get([300.], [0.])
        with self.assertRaises(ValueError):
            self.get([300.], [.1], depth=-.001)
        with self.assertRaises(ValueError):
            self.get([300., 301.], [.1])


if __name__ == '__main__':
    unittest.main()
