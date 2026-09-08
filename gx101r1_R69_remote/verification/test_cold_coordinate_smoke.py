import unittest
import numpy as np
from Audit_HeatDriveECC_ColdCoordinateSmoke import compare_initial,ledger


class ColdCoordinateTests(unittest.TestCase):
    def test_strict_match_not_relaxed(self):
        self.assertTrue(compare_initial(300,300)['within_strict_comparison'])
        self.assertFalse(compare_initial(300.000001,300)['within_strict_comparison'])
        with self.assertRaises(ValueError):compare_initial(np.nan,300)

    def test_open_be_inventory(self):
        result=ledger([0,.001,.002],[1,1.001,1.002],[10,10.002,10.004],[0,1,1],[0,2,2])
        self.assertTrue(result['mass_closure_pass']);self.assertTrue(result['energy_closure_pass'])

    def test_interior_energy_error_not_hidden(self):
        result=ledger([0,.001,.002],[1,1,1],[10,11,10],[0,0,0],[0,0,0])
        self.assertFalse(result['energy_closure_pass'])

    def test_nonfinite_and_duplicate_grid_rejected(self):
        with self.assertRaises(ValueError):ledger([0,0],[1,1],[0,0],[0,0],[0,0])
        with self.assertRaises(ValueError):ledger([0,1],[1,1],[0,np.nan],[0,0],[0,0])


if __name__=='__main__':unittest.main()
