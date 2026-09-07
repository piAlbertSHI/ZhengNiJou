"""Audit complete sample coverage and boundaries without granting production use."""
import argparse
from collections import Counter
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_C200RestoredSignals import compare
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field


def grid(time, values, start, stop):
    time=np.asarray(time).reshape(-1)
    expected=start+np.arange(round((stop-start)/.001)+1)*.001
    if (time.shape!=expected.shape or not np.allclose(time,expected,rtol=0,atol=1e-9)
            or values.ndim!=2 or values.shape[1]!=len(time) or not np.isfinite(values).all()):
        raise ValueError('Incomplete, off-grid or nonfinite samples')


def inspect(path):
    index=int(path.stem.rsplit('_',1)[1])
    start,stop={1:(2000,2004),2:(2004,2008),3:(2008,2010)}[index]
    first,last,units={},{},{}
    with h5py.File(path) as f:
        groups=[('signal',dict(f['signals'])),('native',named_rows(f,f['native'])),
                ('state',named_rows(f,f['observation']['states']))]
        if tuple(len(rows) for _,rows in groups)!=(161,1240,73):
            raise ValueError('Incomplete observed identity coverage')
        if 'source_traces' in f:
            sources=named_rows(f,f['source_traces'])
            metadata=f['boundary_metadata']
            if (len(sources)!=162 or int(metadata['source_count'][0,0])!=49
                    or any(bool(metadata[k][0,0]) for k in ('physical_model_modified','production_recovery_allowed',
                        'full_device_first_law_verified','complete_cycle_verified'))):
                raise ValueError('Invalid boundary observation scope')
            counts=Counter()
            declared=set()
            for ref in metadata['blocks'][:].flat:
                block=f[ref];block_path=text_field(block['block_path'])
                counts[text_field(block['source_file'])]+=1
                for trace_ref in block['trace_names'][:].flat:
                    declared.add((block_path,text_field(f[trace_ref])))
            if (dict(counts)!={'foundation.thermal.sources.controlled_heat_flow':43,
                    'foundation.thermal.sources.temperature':3,'foundation.thermal_liquid.sources.pressure_source':3}
                    or declared!=set(sources)):
                raise ValueError('Source metadata does not cover recorded identities')
            groups.append(('source',sources))
        for prefix,rows in groups:
            for key,row in rows.items():
                name=prefix+'/'+(key if isinstance(key,str) else '/'.join(key))
                values=row['values'][:]
                grid(row['time_s'][:],values,start,stop)
                first[name],last[name]=values[:,0],values[:,-1]
                units[name]=text_field(row['unit']) if 'unit' in row else ''
    return dict(index=index,start_s=start,stop_s=stop,sample_count=round((stop-start)/.001)+1,
                first=first,last=last,units=units,sha256=sha256(path))


def boundary(previous, current):
    if (previous['stop_s']!=current['start_s'] or set(previous['last'])!=set(current['first'])
            or previous['units']!=current['units']):
        raise ValueError('Unpaired boundary identities, units or times')
    rows=[dict(identity=k,**compare(previous['last'][k],current['first'][k])) for k in sorted(current['first'])]
    return dict(compared_groups=len(rows),pass_boundary=all(r['pass_endpoint_match'] for r in rows),
                failed_groups=[r for r in rows if not r['pass_endpoint_match']],
                exact_all=all(r['max_abs_error']==0 for r in rows))


def audit(root, prior_root=None, interrupted=False):
    paths=sorted(root.glob('segment_*.mat'))
    if not paths:
        raise ValueError('No observed segments')
    previous=None
    inputs={}
    if prior_root is not None:
        prior=sorted(prior_root.glob('segment_*.mat'))
        previous=inspect(prior[-1])
        inputs['predecessor_segment']=previous['sha256']
    summaries=[]
    boundaries=[]
    for path in paths:
        current=inspect(path)
        if previous is not None:
            boundaries.append(boundary(previous,current))
        elif current['index']!=1:
            raise ValueError('Missing predecessor for a later segment')
        summaries.append({k:v for k,v in current.items() if k not in ('first','last','units')})
        inputs[path.name]=current['sha256']
        previous=current
    coverage_pass=all(row['pass_boundary'] for row in boundaries)
    continuation=False
    if not interrupted:
        outer=json.loads((root/'source_restore_audit.json').read_text(encoding='utf-8-sig'))
        produced=json.loads((root/'cycle_observation_audit.json').read_text(encoding='utf-8-sig'))
        if (not outer['strict_restore_pass'] or not outer['observation_complete'] or outer['error_message']
                or not produced['computation_complete'] or not produced['diagnostic_resume_allowed']
                or produced['production_recovery_allowed'] or produced['full_scientific_gates_pass']):
            raise ValueError('Segment producer did not finish its bounded job')
        has_sources=any(k.startswith('source/') for k in current['last'])
        if (bool(produced.get('boundary_observation_requested',False))!=has_sources
                or bool(outer.get('boundary_observation_requested',False))!=has_sources):
            raise ValueError('Undeclared boundary observation mode')
        for key,value in produced['artifact_sha256'].items():
            p=root/produced['artifact_names'][key]
            if p.parent.resolve()!=root.resolve() or sha256(p)!=value:
                raise ValueError('Changed producer artifact')
            inputs[p.name]=value
        with h5py.File(root/'final_observation_tail.mat') as f:
            row=f['last']
            identities=[text_field(f[ref]) for ref in row['identities'][:].flat]
            values=[f[ref][:].reshape(-1) for ref in row['values'][:].flat]
            expected_count=1636 if has_sources else 1474
            if len(identities)!=expected_count or len(set(identities))!=expected_count or set(identities)!=set(current['last']):
                raise ValueError('Incomplete saved observation tail')
            if not all(np.array_equal(v,current['last'][k]) for k,v in zip(identities,values)):
                raise ValueError('Saved tail does not match raw observation')
        continuation=coverage_pass
    return dict(schema='heatdrive_ecc_c201_segment_audit_v1',data_audit_pass=coverage_pass,
                segments=summaries,boundaries=boundaries,diagnostic_continuation_eligible=continuation,
                interrupted_without_final_record=interrupted,production_recovery_allowed=False,
                whole_model_first_law_verified=False,full_scientific_gates_pass=False,
                input_sha256=inputs)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-root',type=Path,required=True)
    parser.add_argument('--prior-root',type=Path)
    parser.add_argument('--interrupted',action='store_true')
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite segment evidence')
    result=audit(args.run_root,args.prior_root,args.interrupted)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k!='input_sha256'},indent=2))
    if not result['data_audit_pass']:
        raise SystemExit(1)


if __name__=='__main__':
    main()
