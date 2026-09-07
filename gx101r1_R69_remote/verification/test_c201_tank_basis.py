import copy
import unittest

from Audit_HeatDriveECC_C201TankBasis import geometry,metadata_matches


def row():
    return dict(block_path='tank',model_modes={'num_inlet':'enum.One','volume_spec':'enum.Constant'},
                mask_parameters={k:{'value':v,'unit':u} for k,v,u in (
                    ('tank_area',.001,'m^2'),('g',9.81,'m/s^2'),('inlet_height_A',0,'m'))})


class C201TankTests(unittest.TestCase):
    def test_geometry_requires_actual_modes_units_and_values(self):
        self.assertEqual(geometry(row()),[.001,9.81,0])
        for name,value in (('tank_area',0),('g',-1),('inlet_height_A',float('nan'))):
            r=row();r['mask_parameters'][name]['value']=value
            with self.assertRaises(ValueError):
                geometry(r)
        r=row();r['model_modes']['num_inlet']='enum.Two'
        with self.assertRaises(ValueError):
            geometry(r)
        r=row();r['mask_parameters']['tank_area']['unit']='mm^2'
        with self.assertRaises(ValueError):
            geometry(r)

    def test_metadata_extension_not_parameter_change(self):
        before=dict(source='archive',storage_blocks=[row()])
        after=copy.deepcopy(before)
        after['storage_blocks'][0]['mask_parameters']['additional']={'value':1}
        metadata_matches(before,after)
        after['storage_blocks'][0]['mask_parameters']['tank_area']['value']=.002
        with self.assertRaises(ValueError):
            metadata_matches(before,after)
        after=copy.deepcopy(before);after['source']='current'
        with self.assertRaises(ValueError):
            metadata_matches(before,after)


if __name__=='__main__':
    unittest.main()
