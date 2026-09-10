import unittest
import numpy as np
from scipy.interpolate import RegularGridInterpolator
from Analyze_HeatDriveECC_HeldInventoryConditioning import inventory_scale, cell_gradient, chamber_jacobian


class InventoryConditioningTests(unittest.TestCase):
    def test_bilinear_gradient_analytic(self):
        t = np.array([1.,3.,8.]); p = np.array([2.,7.,11.]); a,b = np.meshgrid(t,p,indexing='ij')
        table = RegularGridInterpolator((t,p), 4+2*a-3*b+5*a*b)
        for side in ('left','right'):
            gradient, cell = cell_gradient(table, 2., 6., side)
            np.testing.assert_allclose(gradient, [32.,7.]); self.assertEqual(cell,[0,0])

    def test_both_knot_slopes_retained(self):
        t = np.array([1.,2.,3.]); p = np.array([1.,2.])
        table = RegularGridInterpolator((t,p), np.repeat([[1.],[2.],[4.]],2,axis=1))
        self.assertEqual(cell_gradient(table,2.,1.5,'left')[0][0],1)
        self.assertEqual(cell_gradient(table,2.,1.5,'right')[0][0],2)
        with self.assertRaises(ValueError): cell_gradient(table,.5,1.5,'left')
        with self.assertRaises(ValueError): cell_gradient(table,2.,1.5,'auto')

    def test_product_rule_and_volume_invariant_scaled_condition(self):
        t = np.array([1.,3.]); p = np.array([2.,4.]); a,b = np.meshgrid(t,p,indexing='ij')
        tables = dict(rho=RegularGridInterpolator((t,p),10+2*a+b),
                      u=RegularGridInterpolator((t,p),20+3*a-b))
        first = chamber_jacobian(tables,2.,3.,.01,'right')
        second = chamber_jacobian(tables,2.,3.,.1,'right')
        np.testing.assert_allclose(first['jacobian_M_U_wrt_T_p_SI'], [[.02,.01],[.97,.06]])
        np.testing.assert_allclose(first['scaled_jacobian'],second['scaled_jacobian'])
        self.assertAlmostEqual(first['condition_number_2'],second['condition_number_2'])

    def test_singular_mapping_not_reported_finite(self):
        grid = (np.array([1.,3.]),np.array([2.,4.]))
        tables = dict(rho=RegularGridInterpolator(grid,np.ones((2,2))),
                      u=RegularGridInterpolator(grid,np.ones((2,2))*2))
        r = chamber_jacobian(tables,2.,3.,1,'left')
        self.assertTrue(r['exact_zero_singular_value']); self.assertIsNone(r['condition_number_2'])

    def test_scales_do_not_claim_actual_error_weights(self):
        r=inventory_scale([1.,1.+1e-9],1e-15,1e-6)
        self.assertFalse(r['actual_compiled_error_weight_verified'])
        np.testing.assert_allclose(r['relative_term_over_closure_tolerance'],1e9,rtol=1e-15,atol=0)
        self.assertEqual(r['largest_float64_spacing'],np.spacing(1.))
        for values in ([1], [0,1], [1,float('nan')]):
            with self.assertRaises(ValueError): inventory_scale(values,1e-15,1e-6)
