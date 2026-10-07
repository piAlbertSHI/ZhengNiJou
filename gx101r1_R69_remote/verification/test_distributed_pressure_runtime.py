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

    def envelope_fixture(self):
        v=list(self.fixture())
        alpha=np.array([0,0,.0029,.2,1,1,1,.2,0,0.])
        v[4]=alpha*.0032
        v[6].update(schema='heatdrive_ecc_distributed_pressure_ff_v2',nominal_flow_kg_s=.0032,
                    pressure_envelope=dict(switch_pressure_MPa=-1e-6),
                    original_switch_prepressure_preserved=True,PI_target_used_as_pressure_envelope=False)
        idle=(1-alpha)*-1e-6
        v[5]=-v[4]*v[3]+idle
        return v+[alpha,idle]

    def test_original_pressure_envelope_and_prepressure_pass(self):
        _,gates=check_equations(*self.envelope_fixture())
        self.assertTrue(all(gates.values()))

    def test_zero_inactive_pressure_fails(self):
        v=self.envelope_fixture();v[8]=np.zeros(10)
        _,gates=check_equations(*v)
        self.assertFalse(gates['switch_prepressure'])

    def test_target_substituted_for_pressure_ramp_fails(self):
        v=self.envelope_fixture();v[4][2]=.0032*.4
        _,gates=check_equations(*v)
        self.assertFalse(gates['envelope_target'])

    def test_v2_missing_envelope_fails_closed(self):
        with self.assertRaises(ValueError):
            check_equations(*self.envelope_fixture()[:7])
