"""Read-only byte-exact physical trajectory coverage for possible raw retirement."""
import argparse
import hashlib
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201CyclePackage import read
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def dataset_prefix(source, replacement, samples, chunk_samples=8192):
    if (source.dtype!=replacement.dtype or source.shape[:-1]!=replacement.shape[:-1]
            or source.shape[-1]!=samples or replacement.shape[-1]<samples
            or source.dtype.kind not in 'fiu'):
        raise ValueError('Incompatible trace shape or type')
    old_hash=hashlib.sha256();new_hash=hashlib.sha256()
    different=0;first=None;last=None;finite=True
    for start in range(0,samples,chunk_samples):
        stop=min(samples,start+chunk_samples)
        old=np.ascontiguousarray(source[...,start:stop])
        new=np.ascontiguousarray(replacement[...,start:stop])
        old_hash.update(old.tobytes());new_hash.update(new.tobytes())
        finite=finite and bool(np.isfinite(old).all() and np.isfinite(new).all())
        mask=np.any(old.view(np.uint8).reshape(old.shape+(old.dtype.itemsize,)) !=
                    new.view(np.uint8).reshape(new.shape+(new.dtype.itemsize,)),axis=-1)
        changed=np.flatnonzero(np.any(mask.reshape(-1,stop-start),axis=0))
        if changed.size:
            different+=int(np.count_nonzero(mask))
            if first is None:first=int(start+changed[0])
            last=int(start+changed[-1])
    return dict(bitwise_exact=different==0,finite=finite,different_scalar_values=different,
        first_different_sample_index=first,last_different_sample_index=last,
        source_chunk_order_sha256=old_hash.hexdigest().upper(),
        replacement_prefix_chunk_order_sha256=new_hash.hexdigest().upper(),
        chunk_samples=chunk_samples)


def physical_coverage(source_path,replacement_path):
    records=[];not_timeseries=[]
    with h5py.File(source_path) as source,h5py.File(replacement_path) as replacement:
        n=source['physical/time_s'].shape[-1]
        def inspect(name,item):
            if not isinstance(item,h5py.Dataset):return
            key='physical/'+name
            if not item.shape or item.shape[-1]!=n:
                not_timeseries.append(key);return
            if key not in replacement:raise ValueError('Missing replacement trajectory: '+key)
            result=dataset_prefix(item,replacement[key],n)
            records.append(dict(path=key,shape=list(item.shape),dtype=str(item.dtype),**result))
        source['physical'].visititems(inspect)
        if not records or not any(r['path']=='physical/time_s' for r in records):
            raise ValueError('Missing time trajectory')
        return dict(source_samples=n,source_end_time_s=float(source['physical/time_s'][0,-1]),
            replacement_samples=replacement['physical/time_s'].shape[-1],
            time_series_count=len(records),exact_time_series_count=sum(r['bitwise_exact'] for r in records),
            all_physical_time_series_bitwise_exact=all(r['bitwise_exact'] for r in records),
            all_physical_time_series_finite=all(r['finite'] for r in records),
            non_timeseries_fields_requiring_separate_retention=not_timeseries,records=records)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    if args.output.exists():raise FileExistsError('Do not overwrite evidence')
    repo=Path(__file__).resolve().parents[1]
    contract=read(repo/'verification/runtime_c180_recovery_contract.json')
    replacement=repo/contract['result_relative_path'];replacement_hash=sha256(replacement)
    if replacement_hash!=contract['result_sha256']:raise ValueError('C180 replacement changed')
    prefix=repo/'outputs/qian_coupled_runtime_strict_coldstart_gate3_20260904'
    sources=[('qian2019_table2_table4_simscape_40cycle_20260904_183855',
              '80C12F151242EB9ED079319776AE45B2F835F9940A881954A8731A5A7B0D7DF1'),
             ('qian2019_table2_table4_simscape_60cycle_20260904_204717',
              '91C799777FBF750E9803B7D6971AECA144099D7756B15B38FBDC6A2D22BA3E19')]
    cases=[]
    for name,expected in sources:
        source=prefix/name/'physical_simscape_result.mat'
        if sha256(source)!=expected:raise ValueError('Historical source changed')
        result=physical_coverage(source,replacement)
        cases.append(dict(source_path=str(source.relative_to(repo)),source_sha256=expected,
            source_bytes=source.stat().st_size,**result))
    result=dict(schema='heatdrive_ecc_raw_prefix_coverage_v1',replacement_path=str(replacement.relative_to(repo)),
        replacement_sha256=replacement_hash,cases=cases,raw_deletion_authorized=False,
        metadata_and_summary_compacted=False,historical_manifest_migration_complete=False,
        reason='Physical-prefix coverage alone does not retire metadata, byte-level file provenance or existing contracts.')
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps([{k:v for k,v in c.items() if k not in ('records','non_timeseries_fields_requiring_separate_retention')}
                      for c in cases],indent=2))


if __name__=='__main__':main()
