"""Compare strict full-OP executions, retaining numerical differences as evidence."""
import argparse
import json
from pathlib import Path

import numpy as np
from scipy.io import loadmat

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from HeatDriveECC_TraceColumns import unpack
from Review_HeatDriveECC_CoupledCVPacket import on_grid
from Run_HeatDriveECC_ConservativeTransport import write_json


def comparisons(reference,resumed,start,stop):
    a=loadmat(reference,simplify_cells=True);b=loadmat(resumed,simplify_cells=True)
    clock=np.arange(round(start/.001),round(stop/.001)+1)*.001;rows=[]
    for group in ('native','workspace','source','state'):
        x=unpack(a[group+'_packet']);y=unpack(b[group+'_packet'])
        if set(x)!=set(y):raise ValueError('State or physical trace ownership differs: '+group)
        for key in sorted(x):
            if x[key]['unit']!=y[key]['unit']:raise ValueError('Observation units changed')
            left=on_grid(x[key],clock);right=on_grid(y[key],clock)
            if left.shape!=right.shape:raise ValueError('State/signal channels changed')
            difference=abs(left-right)
            rows.append(dict(group=group,path=key[0],state_name=key[1],unit=x[key]['unit'],channels=left.shape[1],
                samples=len(clock),max_abs_difference=float(difference.max()),
                max_relative_difference=float(np.max(difference/np.maximum(np.maximum(abs(left),abs(right)),1e-12))),
                exact_value_bits=bool(np.array_equal(left.view(np.uint64),right.view(np.uint64)))))
    return rows


def review(source,new_process,output):
    record_path=source/'state_interface_roundtrip.json';r=json.loads(record_path.read_text(encoding='utf-8'))
    if not r['execution_complete'] or r['production_recovery_allowed'] or r['source_OP_edited']:
        raise ValueError('Invalid full-OP execution contract')
    for path,digest in ((r['reference_file'],r['reference_sha256']),(r['restored_file'],r['restored_sha256']),
                        (r['operating_point_path'],r['operating_point_sha256']),
                        (r['saved_runtime_model_path'],r['saved_runtime_model_sha256'])):
        if sha256(Path(path))!=digest:raise ValueError('A persisted state/model/observation changed')
    rows=comparisons(Path(r['reference_file']),Path(r['restored_file']),r['snapshot_s'],r['reference_stop_s'])
    groups={g:sum(v['group']==g for v in rows) for g in ('native','workspace','source','state')}
    if groups['state']!=r['source_public_state_groups']:raise ValueError('Logged Dataset coverage differs from saved full OP')
    result=dict(schema='heatdrive_ecc_shared_endpoint_OP_review_v1',source_record_sha256=sha256(record_path),
        reader_sha256=sha256(Path(__file__)),source_OP_sha256=r['operating_point_sha256'],
        strict_checksum_policy=r['strict_checksum_policy'],window_s=[r['snapshot_s'],r['reference_stop_s']],
        compared_group_counts=groups,same_model_comparisons=rows,
        same_model_actual_all_value_bits_exact=all(v['exact_value_bits'] for v in rows),
        new_process_executed=False,production_recovery_allowed=False,
        periodicity_or_all_mechanism_or_Table4_qualified=False)
    if new_process:
        n=json.loads((new_process/'new_process_restore.json').read_text(encoding='utf-8'))
        if not n['execution_complete'] or n['source_OP_sha256']!=r['operating_point_sha256']:
            raise ValueError('Wrong new-process state identity')
        if sha256(Path(n['observation_path']))!=n['observation_sha256']:raise ValueError('New-process observation changed')
        start=n['actual_tout_first_s'];stop=n['actual_tout_last_s']
        if start!=r['snapshot_s'] or not start<stop<=r['reference_stop_s']:raise ValueError('Incorrect absolute restore interval')
        new=comparisons(Path(r['reference_file']),Path(n['observation_path']),start,stop)
        result.update(new_process_executed=True,new_process_comparisons=new,
            new_process_comparison_window_s=[start,stop],new_process_full_cycle_covered=stop-start>=10-1e-9,
            new_process_observation_profile=n.get('observation_profile','reference_cycle'),
            new_process_actual_all_value_bits_exact=all(v['exact_value_bits'] for v in new))
    output.mkdir(parents=True,exist_ok=False);write_json(output/'shared_endpoint_OP_review.json',result)
    print(json.dumps(dict(output=str(output),groups=groups,same_model_bits_exact=result['same_model_actual_all_value_bits_exact'],
        new_process_executed=result['new_process_executed'],new_process_bits_exact=result.get('new_process_actual_all_value_bits_exact'),
        numerical_differences_are_retained_not_hidden=True)))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',type=Path,required=True)
    p.add_argument('--new-process',type=Path);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();review(a.source.resolve(),a.new_process.resolve() if a.new_process else None,a.output.resolve())
