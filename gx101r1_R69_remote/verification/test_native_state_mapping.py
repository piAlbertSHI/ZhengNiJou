import unittest
import numpy as np

from Explore_HeatDriveECC_NativeStateMapping import digest


class NativeMappingDigestTests(unittest.TestCase):
    def test_signed_zero_has_one_numeric_identity(self):
        self.assertEqual(digest([0.,1.]),digest([-0.,1.]))

    def test_dtype_and_list_storage_do_not_change_identity(self):
        self.assertEqual(digest([1.,2.,3.]),digest(np.array([1,2,3],dtype=np.int64)))

    def test_real_value_changes_remain_distinct(self):
        self.assertNotEqual(digest([1.,2.]),digest([1.,np.nextafter(2.,3.)]))

    def test_matching_does_not_modify_input(self):
        values=np.array([-0.,1.,2.]);before=values.view(np.uint64).copy()
        digest(values)
        np.testing.assert_array_equal(values.view(np.uint64),before)


if __name__=='__main__':
    unittest.main()
