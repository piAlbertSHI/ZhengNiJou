import tempfile
from pathlib import Path
import unittest

import h5py
import numpy as np

from Audit_HeatDriveECC_C201BoundaryCycle import parameter_dict,integral_summary


class FullBoundaryTests(unittest.TestCase):
    def test_matlab_empty_parameter_structure(self):
        with tempfile.TemporaryDirectory() as folder,h5py.File(Path(folder)/'test.mat','w') as f:
            d=f.create_dataset('empty',data=[1,1])
            d.attrs['MATLAB_class']=np.bytes_('struct');d.attrs['MATLAB_empty']=1
            self.assertEqual(parameter_dict(d),{})
            d.attrs['MATLAB_class']=np.bytes_('double')
            with self.assertRaises(ValueError):
                parameter_dict(d)

    def test_be_and_trapezoid_not_conflated(self):
        summary=integral_summary([0,2,4],[0,1,2])
        self.assertEqual(summary['BE_energy_J'],6)
        self.assertEqual(summary['trapezoid_energy_J'],4)
        self.assertEqual(summary['BE_mean_W'],3)

    def test_invalid_integral_inputs(self):
        for values,time in (([0],[0]),([0,1],[0,0]),([0,1],[0,1,2]),([0,float('nan')],[0,1])):
            with self.assertRaises(ValueError):
                integral_summary(values,time)


if __name__=='__main__':
    unittest.main()
