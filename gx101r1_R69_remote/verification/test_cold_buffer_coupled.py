"""Cold integration must reject lost signals and incomplete time grids."""
import copy
import unittest
from unittest.mock import patch

import numpy as np

from Audit_HeatDriveECC_ColdBufferCoupled import port_contract
from Audit_HeatDriveECC_ColdChamberCycle import checked_rows


class ColdBufferCoupledTests(unittest.TestCase):
    def contract(self):
        return dict(original_conserving_ports=[
            dict(name='A', interface_type='Domain', side='LConn', index=1,
                 domain='foundation.thermal_liquid.thermal_liquid', connected=True),
            dict(name='H', interface_type='Domain', side='RConn', index=1,
                 domain='foundation.thermal.thermal', connected=False)],
            removed_unconnected_outputs=[dict(name=n, interface_type='Output', domain='', connected=False)
                                         for n in ('L_out', 'T_out', 'V_out')])

    def test_explicit_unconnected_outputs(self):
        port_contract(self.contract())

    def test_each_connected_output_rejected(self):
        for i in range(3):
            c = self.contract(); c['removed_unconnected_outputs'][i]['connected'] = True
            with self.assertRaises(ValueError): port_contract(c)

    def test_missing_or_unknown_output_rejected(self):
        c = self.contract(); c['removed_unconnected_outputs'].pop()
        with self.assertRaises(ValueError): port_contract(c)
        c = self.contract(); c['removed_unconnected_outputs'][0]['name'] = 'control'
        with self.assertRaises(ValueError): port_contract(c)

    def test_thermal_connection_cannot_disappear(self):
        c = self.contract(); c['original_conserving_ports'][1]['connected'] = True
        with self.assertRaises(ValueError): port_contract(c)

    def test_domain_or_side_change_rejected(self):
        for field, value in [('side', 'LConn'), ('domain', 'wrong'), ('index', 2)]:
            c = self.contract(); c['original_conserving_ports'][1][field] = value
            with self.assertRaises(ValueError): port_contract(c)

    def rows(self, stop):
        t = np.arange(round(stop/.001)+1)*.001
        return {('buffer', 'T_I'): {'time_s': t.reshape(1, -1), 'values': np.ones((1, t.size))}}

    @patch('Audit_HeatDriveECC_ColdChamberCycle.named_rows')
    def test_short_and_default_cycle_grids(self, named):
        named.return_value = self.rows(.01)
        checked_rows({'native': None}, 'native', 1, stop=.01)
        with self.assertRaises(ValueError): checked_rows({'native': None}, 'native', 1)
        named.return_value = self.rows(10)
        checked_rows({'native': None}, 'native', 1)

    @patch('Audit_HeatDriveECC_ColdChamberCycle.named_rows')
    def test_nonfinite_or_missing_sample_rejected(self, named):
        rows = self.rows(.01); rows['buffer', 'T_I']['values'][0, 5] = np.nan
        named.return_value = rows
        with self.assertRaises(ValueError): checked_rows({'native': None}, 'native', 1, stop=.01)
        rows = copy.deepcopy(self.rows(.01)); rows['buffer', 'T_I']['time_s'][0, 5] += .0002
        named.return_value = rows
        with self.assertRaises(ValueError): checked_rows({'native': None}, 'native', 1, stop=.01)


if __name__ == '__main__':
    unittest.main()
