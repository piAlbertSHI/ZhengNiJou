import unittest
import json
import tempfile
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_ChamberRestrictedFlow import port_identities, pump_power_contract
from Audit_HeatDriveECC_ChamberOpenFlowResult import read_case


class RestrictedFlowTests(unittest.TestCase):
    def test_five_role_reader_requires_explicit_restricted_contract(self):
        groups = dict(chamber=dict(T_I='K',p_I='Pa',rho_I='kg/m^3',u_I='J/kg',mdot_A='kg/s',mdot_B='kg/s',
                                  Phi_A='W',Phi_B='W',Q_H='W',stored_mass='kg',stored_energy='J'),
                      flow_source=dict(mdot_A='kg/s',mdot_B='kg/s',Phi_A='W',Phi_B='W',power='W',rho_A='kg/m^3',rho_B='kg/m^3'),
                      hot_reservoir=dict(mdot_A='kg/s',Phi_A='W',p_I='Pa',T_I='K'),
                      cold_reservoir=dict(mdot_A='kg/s',Phi_A='W',p_I='Pa',T_I='K'),
                      outlet_restriction=dict(mdot_A='kg/s',mdot_B='kg/s',Phi_A='W',Phi_B='W'))
        def chars(parent,name,text):
            parent.create_dataset(name,data=np.array([ord(c) for c in text],dtype=np.uint16))
        meta = dict(formulation='conservative',local_step_s=1,boundary_mode='finite_outlet_restriction')
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)/'packet.mat'
            with h5py.File(path,'w') as f:
                chars(f,'record_json',json.dumps(meta))
                refs = f.create_dataset('packets',(len(groups),),dtype=h5py.ref_dtype)
                for i,(role,units) in enumerate(groups.items()):
                    block = f.create_group(role)
                    chars(block,'role',role)
                    traces = block.create_dataset('traces',(len(units),),dtype=h5py.ref_dtype)
                    for j,(name,unit) in enumerate(units.items()):
                        trace = block.create_group(name)
                        chars(trace,'name',name)
                        chars(trace,'unit',unit)
                        trace.create_dataset('time_s',data=[0,1])
                        trace.create_dataset('values',data=[1,1])
                        traces[j] = trace.ref
                    refs[i] = block.ref
            _,time,packets = read_case(path,restricted=True)
            self.assertEqual(len(packets),5)
            self.assertEqual(len(packets['flow_source']),7)
            np.testing.assert_array_equal(time,[0,1])
            with self.assertRaises(ValueError):
                read_case(path)
            with h5py.File(path,'a') as f:
                del f['record_json']
                del meta['boundary_mode']
                chars(f,'record_json',json.dumps(meta))
            with self.assertRaises(ValueError):
                read_case(path,restricted=True)

    def test_nonzero_pump_power_uses_port_density_and_signed_head(self):
        source = dict(rho_A=np.array([900.,1000.]),rho_B=np.array([1100.,1000.]),
                      mdot_A=np.array([.0002,-.0002]),power=np.array([.02,.02]))
        error = pump_power_contract(source,np.array([2e6,2e6]),np.array([2.1e6,1.9e6]))
        self.assertLess(error,1e-15)
        source['power'] *= -1
        self.assertGreater(pump_power_contract(source,np.array([2e6,2e6]),np.array([2.1e6,1.9e6])),.03)

    def test_nonfinite_density_rejected(self):
        source = dict(rho_A=np.array([np.nan]),rho_B=np.array([1000.]))
        with self.assertRaises(ValueError):
            pump_power_contract(source,np.array([1]),np.array([1]))

    def test_restriction_port_leak_not_hidden_by_external_totals(self):
        c = dict(mdot_A=np.array([2.]),mdot_B=np.array([-2.]),Phi_A=np.array([10.]),Phi_B=np.array([-10.]))
        s = dict(mdot_A=np.array([2.]),mdot_B=np.array([-2.]),Phi_A=np.array([9.]),Phi_B=np.array([-10.]),power=np.array([1.]))
        h = dict(mdot_A=np.array([-2.]),Phi_A=np.array([-9.]))
        cold = dict(mdot_A=np.array([2.]),Phi_A=np.array([10.]))
        r = dict(mdot_A=np.array([2.]),mdot_B=np.array([-2.]),Phi_A=np.array([10.]),Phi_B=np.array([-10.]))
        self.assertEqual(port_identities(c,s,h,cold,r),(0,0))
        r['Phi_A'] += 1
        self.assertEqual(port_identities(c,s,h,cold,r),(0,1))


if __name__ == '__main__':
    unittest.main()
