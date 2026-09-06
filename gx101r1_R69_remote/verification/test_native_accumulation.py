import unittest

import numpy as np

from Audit_HeatDriveECC_NativeAccumulation import energy_tables, path_integral
from test_tl_domain_inventory import parameters


class NativeAccumulationTests(unittest.TestCase):
    def table_parameters(self):
        p = parameters()
        p.update(u_parameterization_1D="1", u_TLU_4="[0;400]", u_TLU_4_unit="kJ/kg",
                 rho_TLU_4="[1000;1000]")
        return p

    def test_reference_energy_and_cp(self):
        tables = energy_tables(self.table_parameters())
        coords = [[300, 1e6], [350, 1e6], [400, 1e6]]
        np.testing.assert_allclose(tables["u"](coords), [0, 200000, 400000], atol=1e-9)
        np.testing.assert_allclose(tables["cp"](coords), [4000] * 3, atol=1e-9)
        np.testing.assert_allclose(tables["alpha"](coords), [0] * 3, atol=1e-12)

    def test_reference_values_nonuniform_grid(self):
        p = self.table_parameters()
        p.update(T_TLU="[300;325;400]", rho_TLU_4="[1000;1000;1000]", u_TLU_4="[0;100;400]")
        tables = energy_tables(p)
        coords = [[300, 1e6], [325, 1e6], [400, 1e6]]
        np.testing.assert_allclose(tables["cp"](coords), [4000] * 3, atol=1e-9)

    def test_inactive_cp_vector_is_not_used(self):
        p = self.table_parameters()
        p.update(cp_TLU_5="[9;8;7;6;5]", cp_TLU_5_unit="kJ/kg/K")
        self.assertAlmostEqual(float(energy_tables(p)["cp"]([[350, 1e6]])[0]), 4000)

    def test_bad_mode_and_shape_rejected(self):
        for key, value in [("u_parameterization_1D", "2"), ("u_TLU_4", "[0]"),
                           ("u_TLU_4", "[400;0]")]:
            p = self.table_parameters()
            p[key] = value
            with self.assertRaises(ValueError):
                energy_tables(p)

    def test_path_orientation_and_pressure_work(self):
        self.assertAlmostEqual(path_integral([1e6] * 3, [.001, .002, .003]), 2000)
        self.assertAlmostEqual(path_integral([1e6] * 3, [.003, .002, .001]), -2000)
        self.assertAlmostEqual(path_integral([1e6] * 3, [.001, .003, .001]), 0)

    def test_nonmatching_path_rejected(self):
        for coeff, coord in [([1, 2], [0]), ([1, float("nan")], [0, 1]), ([[1, 2]], [[0, 1]])]:
            with self.assertRaises(ValueError):
                path_integral(coeff, coord)


if __name__ == "__main__":
    unittest.main()
