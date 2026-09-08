from pathlib import Path
import tempfile
import unittest

import h5py
import numpy as np

from Archive_HeatDriveECC_RawPrefixes import copy_without_traces,logical_hash,reconstructed_chunks


class RawArchiveTests(unittest.TestCase):
    def test_original_endpoint_replaces_later_boundary(self):
        later=np.array([[1.,2.,99.,100.]])
        endpoint=np.array([[3.]])
        data=np.concatenate([a for _,_,a in reconstructed_chunks(later,endpoint,[1,3],2)],axis=-1)
        np.testing.assert_array_equal(data,[[1.,2.,3.]])

    def test_preserve_signed_zero_endpoint(self):
        result=list(reconstructed_chunks(np.array([[1.,0.]]),np.array([[-0.]]),[1,2],2))[0][2]
        self.assertTrue(np.signbit(result[0,-1]))

    def test_wrong_endpoint_dtype_rejected(self):
        with self.assertRaises(ValueError):
            list(reconstructed_chunks(np.ones((1,3)),np.ones((1,1),dtype=np.float32),[1,3],2))

    def test_copy_reference_attribute_and_reference_dataset(self):
        with tempfile.TemporaryDirectory() as temp:
            with h5py.File(Path(temp)/'a.h5','w') as source,h5py.File(Path(temp)/'b.h5','w') as target:
                field=source.create_dataset('#refs#/field',data=np.array([97],dtype='uint16'))
                source.create_group('physical').attrs['MATLAB_fields']=field.ref
                source.create_dataset('physical/time_s',data=[[0.,1.,2.]])
                names=source.create_dataset('physical/names',(1,),dtype=h5py.ref_dtype)
                names[0]=field.ref
                copy_without_traces(source['physical'],target.create_group('physical'),{'physical/time_s'})
                self.assertEqual(logical_hash(source['physical'],{'physical/time_s'}),logical_hash(target['physical']))
                self.assertNotIn('time_s',target['physical'])
                target[target['physical'].attrs['MATLAB_fields']][0]=98
                self.assertNotEqual(logical_hash(source['physical'],{'physical/time_s'}),logical_hash(target['physical']))

    def test_variable_length_field_names_hash_values_not_addresses(self):
        with tempfile.TemporaryDirectory() as temp:
            with h5py.File(Path(temp)/'a.h5','w') as source,h5py.File(Path(temp)/'b.h5','w') as target:
                field=source.create_dataset('names',(2,),dtype=h5py.vlen_dtype(np.dtype('S1')))
                field[0]=np.array([b'a',b'b']);field[1]=np.array([b'c'])
                source.copy(field,target,name='names')
                self.assertEqual(logical_hash(field),logical_hash(target['names']))
                self.assertEqual(logical_hash(field),logical_hash(field))


if __name__=='__main__':unittest.main()
