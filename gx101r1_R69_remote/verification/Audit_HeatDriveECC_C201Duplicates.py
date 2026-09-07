"""Authorize retirement only after exact all-sample equality, never by age."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_SegmentedEvidence import sha256,text_field


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite retirement evidence')
    base=args.repo.resolve()/'outputs_storage_audit'
    rows=[]
    for index in (1,2):
        old=base/'c201_fullcycle_20260907/nominal'/f'segment_{index:02d}.mat'
        new=base/'c201_bounded_20260907'/f'nominal_s{index:02d}'/f'segment_{index:02d}.mat'
        comparisons=0
        with h5py.File(old) as a,h5py.File(new) as b:
            groups=[(dict(a['signals']),dict(b['signals'])),(named_rows(a,a['native']),named_rows(b,b['native'])),
                    (named_rows(a,a['observation']['states']),named_rows(b,b['observation']['states']))]
            for x,y in groups:
                if set(x)!=set(y):
                    raise ValueError('Observation identities differ; preserve both files')
                for key in x:
                    for field in ('time_s','values'):
                        if not np.array_equal(x[key][field][:],y[key][field][:]):
                            raise ValueError('Nonidentical observation; preserve both files: '+str(key))
                    if 'unit' in x[key] and text_field(x[key]['unit'])!=text_field(y[key]['unit']):
                        raise ValueError('Units changed')
                    comparisons+=1
        if comparisons!=1474:
            raise ValueError('Unexpected comparison coverage')
        rows.append(dict(old_path=str(old),replacement_path=str(new),bytes=old.stat().st_size,
                         old_sha256=sha256(old),replacement_sha256=sha256(new),exact_groups=comparisons,
                         all_original_time_and_value_samples_equal=True))
    result=dict(schema='heatdrive_ecc_c201_duplicate_retirement_v1',retirement_authorized=True,
                protected_production_files_included=False,rows=rows,eligible_bytes=sum(r['bytes'] for r in rows),
                original_interruption_and_audit_records_must_be_retained=True)
    args.output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,indent=2))


if __name__=='__main__':
    main()
