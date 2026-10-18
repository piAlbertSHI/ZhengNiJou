import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import h5py
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from HeatDriveECC_KernelBackend import admission, audit_execution


class KernelBackendTests(unittest.TestCase):
    def fixture(self, root):
        path=root/'admission.json';path.write_text('{"fixture":true}',encoding='utf-8')
        function='HeatDriveECC_ConstitutiveStateVectorStep21_KernelCandidate'
        scope=dict(wrapper_name=function,wrapper_sha256='A'*64,kernel_sha256='B'*64)
        case=dict(execution_backend=dict(function=function,kernel_sha256='B'*64,wrapper_sha256='A'*64,
            admission_path=str(path),admission_sha256=sha256(path),old_backend_OP_imported=False))
        row=dict(actual_function=function,requested_function=function,actual_source_sha256='A'*64,
            function_matches_request=True,base_kernel_parameters_match=True,node_count=21,
            sample_time_s=.001,substeps=32,simulation_settings_changed=False,source_state_edited=False)
        record=dict(before=copy.deepcopy(row),after=copy.deepcopy(row))
        cfg=root/'configuration.mat'
        with h5py.File(cfg,'w') as f:
            f.create_dataset('options/constitutive/diagnostic_step_function',data=np.array([ord(c) for c in function],dtype='uint16')[:,None])
        return scope,case,record,cfg

    def test_real_frozen_admission_is_source_bound(self):
        r=admission(Path(__file__).parent/'constitutive_kernel_cold_admission_20261018.json')
        self.assertTrue(r['independent_cold_20cycle_admitted'])
        self.assertFalse(r['old_backend_OP_import_allowed'])

    def test_actual_before_after_binding_not_just_option_metadata(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);scope,case,record,cfg=self.fixture(root)
            (root/'execution_backend.json').write_text(json.dumps(record),encoding='utf-8')
            with patch('HeatDriveECC_KernelBackend.admission',return_value=scope),h5py.File(cfg) as f:
                self.assertTrue(audit_execution(root,case,f)['actual_before_and_after_binding_verified'])
                for when in ('before','after'):
                    for key,value in (('actual_function','wrong'),('base_kernel_parameters_match',False),
                                      ('substeps',16),('actual_source_sha256','0'*64)):
                        bad=copy.deepcopy(record);bad[when][key]=value
                        (root/'execution_backend.json').write_text(json.dumps(bad),encoding='utf-8')
                        with self.assertRaisesRegex(ValueError,'Actual interpreted backend'):
                            audit_execution(root,case,f)

    def test_old_state_import_cannot_be_declared_as_independent_cold(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);scope,case,record,cfg=self.fixture(root)
            case['execution_backend']['old_backend_OP_imported']=True
            with h5py.File(cfg) as f:
                with self.assertRaisesRegex(ValueError,'cross-backend'):
                    audit_execution(root,case,f)

    def test_legacy_case_has_no_new_physical_gate(self):
        self.assertIsNone(audit_execution(Path('unused'),{},None))


if __name__=='__main__':
    unittest.main()
