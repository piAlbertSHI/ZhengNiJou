"""Retain exact logical MAT data using a verified C180 prefix and old endpoints.

Does not delete files or authorize recovery. Restored MAT containers have new file
hashes; their original logical datasets, metadata and endpoint bits are preserved.
"""
import argparse
import hashlib
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201CyclePackage import read
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def encoded(value,file=None):
    if isinstance(value,h5py.Reference):
        return ['reference',logical_hash(file[value]) if value else None]
    array=np.asarray(value)
    data=[encoded(v,file) for v in array.flat] if array.dtype.hasobject else array.tobytes().hex()
    return [array.dtype.str,list(array.shape),data]


def logical_hash(node,omitted=()):
    digest=hashlib.sha256()
    digest.update(json.dumps({k:encoded(v,node.file) for k,v in sorted(node.attrs.items())},sort_keys=True).encode())
    if isinstance(node,h5py.Group):
        digest.update(b'group')
        for name in sorted(node):
            child=node[name]
            if child.name.lstrip('/') in omitted:continue
            digest.update(json.dumps(name).encode());digest.update(logical_hash(child,omitted).encode())
    else:
        digest.update(json.dumps([node.dtype.str,list(node.shape)]).encode())
        if h5py.check_dtype(ref=node.dtype):
            for ref in node[...].flat:
                digest.update(logical_hash(node.file[ref],omitted).encode() if ref else b'null')
        elif node.dtype.hasobject:
            digest.update(json.dumps(encoded(node[...],node.file)).encode())
        else:
            digest.update(node[...].tobytes())
    return digest.hexdigest().upper()


def copy_attributes(source,target):
    for name,value in source.attrs.items():
        if isinstance(value,h5py.Reference) and value:
            references=target.file.require_group('#archive_attribute_refs#')
            key=str(len(references))
            source.file.copy(source.file[value],references,name=key,expand_refs=True)
            value=references[key].ref
        target.attrs[name]=value


def copy_without_traces(source,target,omitted):
    copy_attributes(source,target)
    for name in source:
        item=source[name]
        if item.name.lstrip('/') in omitted:continue
        if isinstance(item,h5py.Group):
            copy_without_traces(item,target.create_group(name),omitted)
        else:
            source.file.copy(item,target,name=name,expand_refs=True)


def reconstructed_chunks(replacement,endpoint,shape,chunk_samples):
    n=shape[-1]
    if replacement.dtype!=endpoint.dtype or list(endpoint.shape)!=shape[:-1]+[1]:
        raise ValueError('Endpoint shape/type changed')
    if list(replacement.shape[:-1])!=shape[:-1] or replacement.shape[-1]<n:
        raise ValueError('Replacement shape changed')
    for start in range(0,n,chunk_samples):
        stop=min(n,start+chunk_samples)
        values=np.ascontiguousarray(replacement[...,start:stop])
        if stop==n:values[...,-1:]=endpoint[...]
        yield start,stop,values


def validate_descriptor(descriptor,case,coverage):
    if (descriptor['source_sha256']!=case['source_sha256'] or descriptor['source_path']!=case['source_path']
            or descriptor['source_bytes']!=case['source_bytes'] or descriptor['traces']!=case['records']
            or descriptor['replacement_path']!=coverage['replacement_path']
            or descriptor['replacement_sha256']!=coverage['replacement_sha256']
            or not descriptor['exact_logical_data_preserved']
            or descriptor['original_mat_container_bytes_preserved'] or descriptor['production_recovery_allowed']
            or set(descriptor['metadata_logical_sha256'])!={'available_simulink_variables','options','physical','provenance','summary'}):
        raise ValueError('Incomplete or changed archive descriptor')


def verify_case(repo,folder,replacement_hash=None):
    descriptor=read(folder/'archive.json')
    coverage_path=repo/'outputs_storage_audit/c40_c60_raw_prefix_coverage_20260908.json'
    coverage=read(coverage_path)
    candidates=[case for case in coverage['cases'] if case['source_sha256']==descriptor['source_sha256']]
    if len(candidates)!=1:raise ValueError('Unknown archived source')
    validate_descriptor(descriptor,candidates[0],coverage)
    verification=folder.parent/'archive_verification.json'
    if verification.exists() and sha256(coverage_path)!=read(verification)['coverage_audit_sha256']:
        raise ValueError('Frozen source coverage changed')
    replacement=(repo/descriptor['replacement_path']).resolve()
    if not replacement.is_relative_to(repo.resolve()):raise ValueError('Replacement escapes repository')
    if (replacement_hash or sha256(replacement))!=descriptor['replacement_sha256']:
        raise ValueError('Replacement file changed')
    for name in ('metadata.h5','endpoints.h5','matlab_header.bin'):
        if sha256(folder/name)!=descriptor['archive_files_sha256'][name]:
            raise ValueError('Archive file changed: '+name)
    with h5py.File(folder/'metadata.h5') as metadata,h5py.File(folder/'endpoints.h5') as endpoints,h5py.File(replacement) as later:
        for name,expected in descriptor['metadata_logical_sha256'].items():
            if logical_hash(metadata[name])!=expected:raise ValueError('Logical metadata changed')
        for record in descriptor['traces']:
            key=record['path'];digest=hashlib.sha256()
            for _,_,values in reconstructed_chunks(later[key],endpoints[key],record['shape'],record['chunk_samples']):
                digest.update(values.tobytes())
            if digest.hexdigest().upper()!=record['source_chunk_order_sha256']:
                raise ValueError('Reconstructed logical trace changed: '+key)
    return descriptor


def create_case(repo,root,case,coverage):
    source_path=repo/case['source_path'];cycles=int(case['source_end_time_s']/10)
    folder=root/f'c{cycles}'
    if folder.exists():raise FileExistsError('Do not overwrite archived evidence')
    if sha256(source_path)!=case['source_sha256']:raise ValueError('Original source changed')
    if any(not r['bitwise_exact'] and r['first_different_sample_index']!=case['source_samples']-1 for r in case['records']):
        raise ValueError('Differences are not restricted to endpoint')
    folder.mkdir(parents=True)
    omitted={r['path'] for r in case['records']}
    hashes={}
    with source_path.open('rb') as stream:header=stream.read(512)
    (folder/'matlab_header.bin').write_bytes(header)
    with h5py.File(source_path) as source,h5py.File(folder/'metadata.h5','w') as metadata,h5py.File(folder/'endpoints.h5','w') as endpoints:
        if source.userblock_size!=512:raise ValueError('Unexpected MATLAB header')
        for name in source:
            if name.startswith('#'):continue
            if name=='physical':copy_without_traces(source[name],metadata.create_group(name),omitted)
            else:source.copy(source[name],metadata,name=name,expand_refs=True)
            original_hash=logical_hash(source[name],omitted)
            if logical_hash(metadata[name])!=original_hash:raise ValueError('Metadata copy changed')
            hashes[name]=original_hash
        for record in case['records']:
            key=record['path'];item=source[key]
            dataset=endpoints.create_dataset(key,data=item[...,-1:])
            copy_attributes(item,dataset)
    descriptor=dict(schema='heatdrive_ecc_raw_prefix_archive_v1',source_path=case['source_path'],
        source_sha256=case['source_sha256'],source_bytes=case['source_bytes'],cycles=cycles,
        replacement_path=coverage['replacement_path'],replacement_sha256=coverage['replacement_sha256'],
        metadata_logical_sha256=hashes,traces=case['records'],
        archive_files_sha256={name:sha256(folder/name) for name in ('metadata.h5','endpoints.h5','matlab_header.bin')},
        exact_logical_data_preserved=True,original_mat_container_bytes_preserved=False,
        production_recovery_allowed=False,raw_deletion_authorized=False)
    (folder/'archive.json').write_text(json.dumps(descriptor,indent=2,allow_nan=False)+'\n',encoding='utf-8')


def materialize(repo,folder,target,descriptor):
    if target.exists():raise FileExistsError('Do not overwrite restored MAT')
    replacement=repo/descriptor['replacement_path']
    with h5py.File(folder/'metadata.h5') as metadata,h5py.File(folder/'endpoints.h5') as endpoints,h5py.File(replacement) as later,h5py.File(target,'w',userblock_size=512) as output:
        for name in descriptor['metadata_logical_sha256']:
            metadata.copy(metadata[name],output,name=name,expand_refs=True)
        for record in descriptor['traces']:
            key=record['path'];end=endpoints[key]
            dataset=output.create_dataset(key,shape=record['shape'],dtype=end.dtype,compression='gzip',compression_opts=1)
            copy_attributes(end,dataset)
            for start,stop,values in reconstructed_chunks(later[key],end,record['shape'],record['chunk_samples']):
                dataset[...,start:stop]=values
    with target.open('r+b') as stream:stream.write((folder/'matlab_header.bin').read_bytes())
    with h5py.File(target) as output:
        omitted={r['path'] for r in descriptor['traces']}
        for name,expected in descriptor['metadata_logical_sha256'].items():
            if logical_hash(output[name],omitted)!=expected:raise ValueError('Materialized metadata changed')
        for record in descriptor['traces']:
            digest=hashlib.sha256();dataset=output[record['path']]
            for start in range(0,record['shape'][-1],record['chunk_samples']):
                digest.update(dataset[...,start:start+record['chunk_samples']].tobytes())
            if digest.hexdigest().upper()!=record['source_chunk_order_sha256']:
                raise ValueError('Materialized trace changed')
    return dict(path=str(target),sha256=sha256(target),bytes=target.stat().st_size,logical_data_verified=True,
                original_mat_container_hash_preserved=False)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    modes=parser.add_mutually_exclusive_group(required=True)
    modes.add_argument('--create',action='store_true');modes.add_argument('--verify',action='store_true')
    modes.add_argument('--materialize',type=int,choices=(40,60))
    args=parser.parse_args();repo=Path(__file__).resolve().parents[1]
    base=repo/'outputs_storage_audit';root=base/'c40_c60_prefix_archive_20260908_v3'
    coverage_path=base/'c40_c60_raw_prefix_coverage_20260908.json';coverage=read(coverage_path)
    replacement_hash=sha256(repo/coverage['replacement_path'])
    if replacement_hash!=coverage['replacement_sha256']:raise ValueError('Replacement changed')
    if args.create:
        if root.exists():raise FileExistsError('Do not overwrite archive root')
        for case in coverage['cases']:create_case(repo,root,case,coverage)
    descriptors=[verify_case(repo,root/f'c{cycles}',replacement_hash) for cycles in (40,60)]
    summary=dict(archive_verification_pass=True,source_raw_bytes=sum(d['source_bytes'] for d in descriptors),
        archive_bytes=sum(p.stat().st_size for p in root.rglob('*') if p.is_file()),
        cases=[dict(cycles=d['cycles'],source_sha256=d['source_sha256'],traces=len(d['traces'])) for d in descriptors],
        production_recovery_allowed=False,original_mat_container_bytes_preserved=False,deleted_bytes=0)
    if args.create:
        summary['coverage_audit_sha256']=sha256(coverage_path)
        (root/'archive_verification.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
    if args.materialize:
        folder=root/f'c{args.materialize}';descriptor=next(d for d in descriptors if d['cycles']==args.materialize)
        restored=materialize(repo,folder,folder/'restored_validation.mat',descriptor)
        (folder/'materialized_validation.json').write_text(json.dumps(restored,indent=2)+'\n',encoding='utf-8')
        summary['materialized']=restored
    print(json.dumps(summary,indent=2))


if __name__=='__main__':main()
