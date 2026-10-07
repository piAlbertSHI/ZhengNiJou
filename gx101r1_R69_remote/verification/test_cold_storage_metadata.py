import copy
import unittest
from Audit_HeatDriveECC_CompletedColdArms import compare_storage_metadata


class ColdStorageMetadataTests(unittest.TestCase):
    def fixture(self):
        return [dict(block_path='model/buffer',mask_parameters={
            'length':dict(value=.2,expression='0.2',unit='m'),
            'reference_temperature':dict(value=393.15,expression='393.15',unit='K')},
            initialization_parameters=dict(stored_mass='0.09028074776276282'))]

    def test_solver_roundoff_in_initialization_not_physical_failure(self):
        a=self.fixture();b=copy.deepcopy(a)
        b[0]['initialization_parameters']['stored_mass']='0.09028074776267636'
        b[0]['mask_parameters']['reference_temperature']['value']+=1.2e-10
        r=compare_storage_metadata(a,b)
        self.assertEqual(len(r['initialization_roundoff_differences']),2)

    def test_changed_geometry_still_rejected(self):
        a=self.fixture();b=copy.deepcopy(a);b[0]['mask_parameters']['length']['value']+=1e-13
        with self.assertRaises(ValueError):compare_storage_metadata(a,b)

    def test_changed_units_still_rejected(self):
        a=self.fixture();b=copy.deepcopy(a);b[0]['mask_parameters']['reference_temperature']['unit']='degC'
        with self.assertRaises(ValueError):compare_storage_metadata(a,b)

    def test_changed_initial_state_still_rejected(self):
        a=self.fixture();b=copy.deepcopy(a);b[0]['initialization_parameters']['stored_mass']='0.09029'
        with self.assertRaises(ValueError):compare_storage_metadata(a,b)

    def test_nonliteral_initialization_not_silently_evaluated(self):
        a=self.fixture();b=copy.deepcopy(a);b[0]['initialization_parameters']['stored_mass']='mass_command'
        with self.assertRaises(ValueError):compare_storage_metadata(a,b)
