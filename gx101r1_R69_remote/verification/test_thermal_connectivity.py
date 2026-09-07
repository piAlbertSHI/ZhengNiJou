import copy
import unittest

from Audit_HeatDriveECC_ThermalConnectivity import wire_nets


class ThermalConnectivityTests(unittest.TestCase):
    def topology(self):
        domain = 'foundation.thermal.thermal'
        return dict(schema='heatdrive_ecc_thermal_connectivity_v1', domain=domain,
                    primitive_internal_connections_inferred=False, source_model_modified=False,
                    vertices=[dict(key='r:A', handle=10, block_path='r', domain=domain),
                              dict(key='r:B', handle=20, block_path='r', domain=domain)],
                    blocks=[dict(block_path='r', vertex_indices=[1, 2])], edges=[],
                    port_connectivity=[dict(vertex_index=i, destination_handles=[], destination_indices=[]) for i in (1, 2)])

    def test_resistance_is_not_a_wire(self):
        self.assertEqual(wire_nets(self.topology()), [['r:A'], ['r:B']])

    def test_missing_wire_evidence_rejected(self):
        t = self.topology()
        t['edges'] = [dict(a=1, b=2, kind='physical_wire_net')]
        with self.assertRaises(ValueError):
            wire_nets(t)

    def test_destination_handle_must_match(self):
        t = self.topology()
        t['edges'] = [dict(a=1, b=2, kind='physical_wire_net')]
        t['port_connectivity'][0].update(destination_indices=[2], destination_handles=[10])
        with self.assertRaises(ValueError):
            wire_nets(t)
        t['port_connectivity'][0]['destination_handles'] = [20]
        self.assertEqual(wire_nets(t), [['r:A', 'r:B']])

    def test_unknown_edges_and_cross_domain_rejected(self):
        t = self.topology()
        changed = copy.deepcopy(t)
        changed['vertices'][1]['domain'] = 'fluid'
        with self.assertRaises(ValueError):
            wire_nets(changed)
        t['edges'] = [dict(a=1, b=2, kind='conduction')]
        with self.assertRaises(ValueError):
            wire_nets(t)

    def test_duplicate_ownership_rejected(self):
        t = self.topology()
        t['blocks'][0]['vertex_indices'] = [1, 1, 2]
        with self.assertRaises(ValueError):
            wire_nets(t)


if __name__ == '__main__':
    unittest.main()
