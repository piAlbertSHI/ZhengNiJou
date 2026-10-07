import unittest
import numpy as np
from Audit_HeatDriveECC_DistributedPressureRuntime import check_equations


class DistributedRuntimeTests(unittest.TestCase):
    def fixture(self):
        live=np.tile(np.arange(10.)+300,(21,1))
        delayed=np.concatenate((np.full((21,1),303.15),live[:,:-1]),axis=1)
        contract=dict(property_temperature_K=[290,330],kinematic_viscosity_m2_s=[9e-6,1e-6],
                      segment_coefficients_MPa_per_kgps_per_m2ps=np.full(21,1e5).tolist())
        nu=np.interp(delayed,[290,330],[9e-6,1e-6])
        resistance=np.sum(nu*1e5,axis=0)
        target=np.full(10,.0032)
        return live,delayed,nu,resistance,target,-target*resistance,contract

    def test_exact_equations_pass(self):
        _,gates=check_equations(*self.fixture())
        self.assertTrue(all(gates.values()))

    def test_future_temperature_fails(self):
        values=list(self.fixture()); values[1]=values[0].copy()
        _,gates=check_equations(*values)
        self.assertFalse(gates['delay'])

    def test_legacy_reference_multiplier_fails(self):
        values=list(self.fixture()); values[5]=values[5]*.85
        _,gates=check_equations(*values)
        self.assertFalse(gates['command'])

    def test_nonfinite_rejected(self):
        values=list(self.fixture()); values[0][0,0]=np.nan
        with self.assertRaises(ValueError):
            check_equations(*values)
