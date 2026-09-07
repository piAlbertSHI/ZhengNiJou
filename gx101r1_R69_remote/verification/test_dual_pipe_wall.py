import unittest

import numpy as np

from Audit_HeatDriveECC_DualChamberSwitchResult import audit_case
import test_dual_pipe as pipe_tests


class DualPipeWallTests(unittest.TestCase):
    def fixture(self):
        meta, t, p, table = pipe_tests.DualPipeTests().fixture()
        meta['wall_contract'] = dict(capacity_each_J_K=2, conductance_each_W_K=1, wall_cp_reference_J_kgK=500)
        for role in ('inlet', 'outlet'):
            p[role+'_wall'] = dict(T=340+t, Q=np.full_like(t, 2))
            p[role]['Q_H'] = np.full_like(t, -2)
        return meta, t, p, table

    def test_wall_energy_is_included_in_external_ledger(self):
        meta, t, p, table = self.fixture()
        row = audit_case(meta, t, p, table, finite_transition=True, pipe_model=True, wall_model=True)
        for role in ('inlet', 'outlet'):
            self.assertTrue(row['ledgers'][role+'_wall']['energy_closure_pass'])
        fluid = sum(row['ledgers'][role]['endpoint_energy_change_J'] for role in ('inlet','outlet'))
        self.assertAlmostEqual(row['ledgers']['external_total']['endpoint_energy_change_J'], fluid+4)
        self.assertFalse(row['dual_inventory_closure_pass'])

    def test_unmatched_initial_wall_is_rejected(self):
        meta, t, p, table = self.fixture()
        p['inlet_wall']['T'][0] = 300
        with self.assertRaises(ValueError):
            audit_case(meta, t, p, table, finite_transition=True, pipe_model=True, wall_model=True)

    def test_wall_heat_cannot_enter_adiabatic_contract(self):
        meta, t, p, table = self.fixture()
        with self.assertRaises(ValueError):
            audit_case(meta, t, p, table, finite_transition=True, pipe_model=True)


if __name__ == '__main__':
    unittest.main()
