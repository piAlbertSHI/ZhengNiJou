from pathlib import Path
import tempfile
import unittest

import h5py
import numpy as np

from Analyze_HeatDriveECC_FamilyParameterBridge import value


class FamilyParameterBridgeTests(unittest.TestCase):
    def test_scalar_matlab_character_and_missing_are_distinct(self):
        with tempfile.TemporaryDirectory() as directory:
            with h5py.File(Path(directory)/'fields.h5', 'w') as f:
                f.create_dataset('pressure', data=[[.85]])
                d = f.create_dataset('mode', data=np.array([[ord(c)] for c in 'runtime'], dtype='uint16'))
                d.attrs['MATLAB_class'] = np.bytes_('char')
                self.assertEqual(value(f, 'pressure')['value'], .85)
                self.assertEqual(value(f, 'mode')['value'], 'runtime')
                self.assertEqual(value(f, 'absent'), dict(present=False))

    def test_array_is_not_silently_compared_as_a_scalar(self):
        with tempfile.TemporaryDirectory() as directory:
            with h5py.File(Path(directory)/'fields.h5', 'w') as f:
                f.create_dataset('array', data=[[1., 2.]])
                with self.assertRaises(ValueError):
                    value(f, 'array')


if __name__ == '__main__':
    unittest.main()
