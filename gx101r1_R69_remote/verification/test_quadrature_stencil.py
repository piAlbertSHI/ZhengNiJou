import unittest
from decimal import Decimal
from Audit_HeatDriveECC_QuadratureStencil import exact_stencil


class StencilTests(unittest.TestCase):
    def test_quadratic(self):
        for side,expected in [(0,Decimal(1)/3),(1,Decimal(26)/3)]:
            actual=Decimal(exact_stencil([0.,1.,3.],[0.,1.,9.],side)['integral_decimal'])
            self.assertLess(abs(actual-expected),Decimal('1e-26'))

    def test_constant_unequal(self):
        r=exact_stencil([0.,1e-5,1.00000000001e-5],[2.,2.,2.],0)
        self.assertLess(abs(float(r['integral_decimal'])-2e-5),1e-20)

    def test_duplicate(self):
        with self.assertRaises(ValueError):exact_stencil([0,0,1],[1,1,1],0)
