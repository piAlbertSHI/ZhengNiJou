"""Compare actually executed passive tail recording to the retained full C2."""
import argparse
import json
from pathlib import Path

import numpy as np

from Analyze_HeatDriveECC_CoupledCVBalance import load_case
from Analyze_HeatDriveECC_NativeConsistencyProbe import require_equal
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from HeatDriveECC_TraceColumns import load
from Review_HeatDriveECC_CoupledCVPacket import on_grid,verify_sources,verify_arm
from Run_HeatDriveECC_ConservativeTransport import write_json


def compare(reference,experiment,output):
    read=lambda p:json.loads(p.read_text(encoding='utf-8'))
    a=read(reference/'coupled_CV_execution.json');b=read(experiment/'coupled_CV_execution.json')
    for e in (a,b):
        if not e['collection_complete'] or e['checkpoint_loaded_or_saved'] or e['stop_time_s']!=20 or e['inventory_formulation']!='endpoint_inventory':
            raise ValueError('Need two complete independent cold C2 executions')
        verify_sources(e)
    ca=next(r for r in a['completed_arms'] if r['arm']=='shared');cb=b['completed_arms'][0]
    if len(b['completed_arms'])!=1 or cb['arm']!='shared':raise ValueError('Wrong logging trial arm')
    coverage=[verify_arm(reference,ca,20),verify_arm(experiment,cb,20)]
    x=load_case(reference,ca);y=load_case(experiment,cb)
    w=y['contract']['observation_window']
    if w['start_s']!=10 or w['stop_s']!=20 or 'observation_window' in x['contract']:
        raise ValueError('Require executed data-history truncation against unbounded C2')
    for name in ('system','fluid','geometry','material','equilibrium','solid','constitutive','branch','schedule'):
        require_equal(x['options'][name],y['options'][name],name)
    require_equal(x['contract']['storage_blocks'],y['contract']['storage_blocks'],'storage')
    require_equal(x['contract']['settings_tables'],y['contract']['settings_tables'],'properties')
    clock=y['time'];rows=[]
    for group in ('native','workspace','sources'):
        if set(x[group])!=set(y[group]):raise ValueError('Physical output ownership changed')
        for key in sorted(y[group]):
            left=on_grid(x[group][key],clock);right=on_grid(y[group][key],clock)
            if left.shape!=right.shape:raise ValueError('Physical signal channels changed')
            rows.append(dict(group=group,path=key[0],name=key[1],
                exact_value_bits=bool(np.array_equal(left.view(np.uint64),right.view(np.uint64))),
                max_abs_difference=float(abs(left-right).max())))
    coarse=load(experiment/'shared/coarse_CV_observations.mat')
    for row in coarse.values():
        source=row['state_name'].removeprefix('coarse_')
        old=on_grid(x['workspace'][x['model'],source],row['time_s'])
        rows.append(dict(group='coarse',path=row['block_path'],name=row['state_name'],
            exact_value_bits=bool(np.array_equal(old.view(np.uint64),row['values'].view(np.uint64))),
            max_abs_difference=float(abs(old-row['values']).max())))
    logging_sources={'Run_HeatDriveECC_SharedSMAColdInitial':b['source_sha256']['runner']}
    for name in ('Configure_HeatDriveECC_CVTailObservation','Capture_HeatDriveECC_CoupledCVPacket','Select_HeatDriveECC_TraceWindow'):
        logging_sources[name]=b['CV_source_sha256'][name]
    passed=all(r['exact_value_bits'] for r in rows)
    output.mkdir(parents=True,exist_ok=False)
    result=dict(schema='heatdrive_ecc_CV_tail_equivalence_v1',
        reference_execution_sha256=sha256(reference/'coupled_CV_execution.json'),
        experiment_execution_sha256=sha256(experiment/'coupled_CV_execution.json'),
        reference_root=str(reference),experiment_root=str(experiment),reader_sha256=sha256(Path(__file__)),
        coverage=coverage,comparison_window_s=[10,20],compared_traces=len(rows),comparisons=rows,
        runtime_logging_sources_sha256=logging_sources,passive_logging_equivalence_pass=passed,
        ten_cycle_or_full_hidden_state_periodicity_claimed=False,production_recovery_allowed=False)
    write_json(output/'passive_CV_tail_equivalence.json',result)
    print(json.dumps(dict(output=str(output),passive_logging_equivalence_pass=passed,traces=len(rows))))
    if not passed:raise ValueError('Measured logging comparison differs; diagnose retained evidence before C20')


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('reference','experiment','output'):p.add_argument('--'+name,type=Path,required=True)
    a=p.parse_args();compare(a.reference.resolve(),a.experiment.resolve(),a.output.resolve())
