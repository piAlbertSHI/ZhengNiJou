import unittest

import numpy as np

from Audit_HeatDriveECC_DualChamberSwitchResult import spatial_identities
from Audit_HeatDriveECC_DualSwitchFailureMatrix import failure_metrics
from Audit_HeatDriveECC_NativeInventoryCatalog import convert


class DualChamberTests(unittest.TestCase):
    def test_dimensionless_opening_keeps_unit_contract(self):
        np.testing.assert_array_equal(convert([1,0],'1','1'),[1,0])
        with self.assertRaises(ValueError):
            convert([1],'1','K')

    def test_shared_junction_sums_all_branches(self):
        def ports(a,b):
            a,b = float(a),float(b)
            return dict(mdot_A=np.array([a]),mdot_B=np.array([b]),Phi_A=np.array([a]),Phi_B=np.array([b]))
        p = dict(inlet=ports(2,-2),outlet=ports(2,-2),pump=ports(2,-2),
                 inlet_reservoir=ports(0,0),outlet_reservoir=ports(0,0),
                 v1=ports(2,-2),v2=ports(0,0),v3=ports(2,-2),v4=ports(0,0))
        p['pump']['power'] = np.array([0])
        self.assertEqual(spatial_identities(p,'mdot'),0)
        self.assertEqual(spatial_identities(p,'Phi'),0)
        p['v2']['mdot_B'] += .1
        self.assertAlmostEqual(spatial_identities(p,'mdot'),.1)

    def test_invalid_terminal_sample_is_retained_not_accepted(self):
        t = np.array([.498,.499,.5])
        def trace(unit,values):
            return dict(unit=unit,time=t,value=np.array(values,dtype=float))
        traces = {'/V3/B/T':trace('K',[369,370,50]),'/V3/L':trace('1',[1,1,0]),
                  '/V3/A/T':trace('K',[369,370,365]),'/V3/A/p':trace('Pa',[2.5e6]*3),
                  '/V3/B/p':trace('Pa',[2.5e6]*3),'/V3/mdot_A':trace('kg/s',[.01,.01,-1e-6]),
                  '/V3/Phi_A':trace('W',[3000,3000,170]),'/Inlet/T_I':trace('K',[377]*3),
                  '/Outlet/T_I':trace('K',[370]*3)}
        meta = dict(production_recovery_allowed=False,separate_boundaries=True)
        row = failure_metrics(meta,traces)
        self.assertEqual(row['first_out_of_domain_temperature_K'],50)
        self.assertTrue(row['invalid_terminal_sample_retained'])
        self.assertFalse(row['valid_physical_solution_at_terminal_sample'])
        self.assertFalse(row['simulation_completion_pass'])
        traces['/V3/B/T']['value'][-1] = 300
        with self.assertRaises(ValueError):
            failure_metrics(meta,traces)


if __name__=='__main__':
    unittest.main()
