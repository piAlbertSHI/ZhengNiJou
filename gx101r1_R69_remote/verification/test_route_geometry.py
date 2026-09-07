import unittest

from Audit_HeatDriveECC_RouteGeometryResult import route_paths,value
from Audit_HeatDriveECC_PipeAblation import expected_contract


class RouteGeometryTests(unittest.TestCase):
    def topology(self):
        return dict(vertices=[{},{}],edges=[],blocks=[
            dict(source_file='pump',block_path='m/SMA Pressure Source (TL)',vertex_indices=[1,2]),
            dict(source_file='valve',block_path='m/SMA_V1_path',vertex_indices=[1,2])])

    def test_intended_route_excludes_closed_valve(self):
        d=self.topology()
        self.assertEqual(route_paths(d,{1}),['m/SMA_V1_path'])
        with self.assertRaises(ValueError):
            route_paths(d,{2})

    def test_parallel_route_ambiguity_rejected(self):
        d=self.topology()
        d['blocks'].append(dict(source_file='valve',block_path='m/SMA_V2_path',vertex_indices=[1,2]))
        with self.assertRaises(ValueError):
            route_paths(d,{1,2})

    def test_pump_short_circuit_rejected(self):
        d=self.topology()
        d['edges']=[dict(a=1,b=2,kind='physical_wire_net')]
        with self.assertRaises(ValueError):
            route_paths(d,{1})

    def test_geometry_units_and_signs_remain_strict(self):
        d=dict(resolved={'length':dict(value=.2,unit='m')})
        self.assertEqual(value(d,'length','m'),.2)
        with self.assertRaises(ValueError):
            value(d,'length','mm')
        d['resolved']['length']['value']=-.2
        with self.assertRaises(ValueError):
            value(d,'length','m')

    def test_ablation_axes_are_independent(self):
        self.assertEqual(expected_contract('no_friction_short_port')[:2],(0,.0032))
        self.assertEqual(expected_contract('no_friction_long_port')[:2],(0,.1))
        self.assertEqual(expected_contract('friction_short_port')[:2],(1,.0032))
        with self.assertRaises(ValueError):
            expected_contract('almost_no_friction')


if __name__=='__main__':
    unittest.main()
