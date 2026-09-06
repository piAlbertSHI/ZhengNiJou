import unittest

import numpy as np
from scipy.interpolate import RegularGridInterpolator

from Audit_HeatDriveECC_DualChamberCoordinates import cell_gradient,coordinate_bridge


class CoordinateTests(unittest.TestCase):
    def table(self):
        t,p=np.array([300.,310.]),np.array([1e6,2e6])
        T,P=np.meshgrid(t-300,p-1e6,indexing='ij')
        rho=1000-2*T+1e-5*P+1e-6*T*P
        u=100000+4000*T+.001*P+.0001*T*P
        return {k:RegularGridInterpolator((t,p),v) for k,v in dict(rho=rho,u=u).items()}

    def test_exact_bilinear_cell_gradient(self):
        g,_=cell_gradient(self.table()['rho'],[[305,1.5e6]])
        np.testing.assert_allclose(g,[[-1.5,1.5e-5]],rtol=1e-12,atol=1e-16)

    def test_chain_bridge_explains_not_removes_inventory_error(self):
        table=self.table()
        point=np.array([[304.,1.4e6],[305.,1.5e6]])
        r,u=table['rho'](point),table['u'](point)
        dr,_=cell_gradient(table['rho'],point)
        du,_=cell_gradient(table['u'],point)
        delta=point[1]-point[0]
        dm=1e-6*np.sum(dr[1]*delta)
        de=1e-6*np.sum((dr*u[:,None]+du*r[:,None])[1]*delta)
        row=coordinate_bridge([0,1],point[:,0],point[:,1],1e-6,[0,dm],[0,de],table)
        self.assertLess(row['energy_coefficient_max_interval_error_J'],1e-12)
        self.assertAlmostEqual(row['endpoint_energy_bridge_J'],1e-6*(r[1]*u[1]-r[0]*u[0])-de,places=12)
        self.assertGreater(abs(row['endpoint_energy_bridge_J']),1e-5)
        self.assertFalse(row['diagnostic_correction_subtracted_from_physical_gate'])

    def test_extrapolation_and_invalid_time_rejected(self):
        with self.assertRaises(ValueError):
            cell_gradient(self.table()['rho'],[[290,1.5e6]])
        with self.assertRaises(ValueError):
            coordinate_bridge([0,0],[304,305],[1.4e6,1.5e6],1e-6,[0,0],[0,0],self.table())

    def test_unaccounted_heat_does_not_match_coordinate_equation(self):
        row=coordinate_bridge([0,1],[305,305],[1.5e6,1.5e6],1e-6,[0,0],[0,.2],self.table())
        self.assertAlmostEqual(row['energy_coefficient_max_interval_error_J'],.2)
        self.assertAlmostEqual(row['endpoint_energy_bridge_J'],0)
        self.assertFalse(row['diagnostic_correction_subtracted_from_physical_gate'])


if __name__=='__main__':
    unittest.main()
