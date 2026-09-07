"""Audit passive state observation and retain all named C200 recovery values."""
import argparse
import json
from pathlib import Path
import zipfile

import h5py
import numpy as np

from Audit_HeatDriveECC_C200RestoredSignals import compare
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field


def archived_source(root):
    archive = root/'c200_source.zip'
    source = root/'source'
    changed, count = [], 0
    old = '        if isfield(out, key) && isstruct(out.(key)) && isstruct(overrides.(key))'
    new = ('        if isfield(out, key) && isstruct(out.(key)) && isscalar(out.(key)) && ...\n'
           '                isstruct(overrides.(key)) && isscalar(overrides.(key))')
    with zipfile.ZipFile(archive) as z:
        for info in z.infolist():
            if info.is_dir():
                continue
            target = (source/info.filename).resolve()
            if not target.is_relative_to(source.resolve()):
                raise ValueError('Archive entry escapes source root')
            original, actual = z.read(info), target.read_bytes()
            count += 1
            if actual != original:
                if (info.filename != 'gx101r1_R69_remote/Build_HeatDriveECC_EighthRound_Defaults.m'
                        or original.decode('utf-8').replace('\r\n','\n').count(old)!=1
                        or actual.decode('utf-8').replace('\r\n','\n') != original.decode('utf-8').replace('\r\n','\n').replace(old,new)):
                    raise ValueError('Undeclared archived source change')
                changed.append(info.filename)
    if len(changed)!=1:
        raise ValueError('Expected exactly one nonphysical scalar-merge patch')
    return dict(archive_sha256=sha256(archive),archived_file_count=count,changed_files=changed,
                physical_equations_or_slx_changed=False)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite state evidence')
    root=args.repo/'outputs_storage_audit/c200_source_compatibility_20260907'
    source_audit=archived_source(root)
    left=root/'archived_source_probe_v3/restored_step_signals.mat'
    right=root/'archived_source_probe_v4/restored_step_signals.mat'
    registered=root/'archived_source_probe_v4/registered_states.mat'
    metadata_path=root/'archived_source_probe_v4/source_restore_audit.json'
    metadata=json.loads(metadata_path.read_text(encoding='utf-8-sig'))
    if (not metadata['strict_restore_pass'] or not metadata['observation_complete']
            or not metadata['registered_state_observation_requested'] or metadata['registered_state_group_count']!=73
            or metadata['final_logged_state_class']!='Simulink.SimulationData.Dataset' or metadata['partial_restore_executed']):
        raise ValueError('Unexpected observed restore contract')
    comparisons=[]
    with h5py.File(left) as a,h5py.File(right) as b:
        if set(a['signals'])!=set(b['signals']):
            raise ValueError('Physical observation coverage changed')
        for name in a['signals']:
            comparisons.append(dict(key=name,**compare(a['signals'][name]['values'][:],b['signals'][name]['values'][:])))
        def native(f):
            rows={}
            for ref in f['native'][:].flat:
                r=f[ref]
                key=text_field(r['block_path'])+'/'+text_field(r['state_name'])
                if key in rows:
                    raise ValueError('Duplicate native identity')
                rows[key]=(text_field(r['unit']),r['time_s'][:],r['values'][:])
            return rows
        x,y=native(a),native(b)
        if set(x)!=set(y):
            raise ValueError('Native state coverage changed')
        for key in x:
            if x[key][0]!=y[key][0] or not np.array_equal(x[key][1],y[key][1]):
                raise ValueError('Native unit or sample grid changed')
            comparisons.append(dict(key=key,**compare(x[key][2],y[key][2])))
    states=[]
    with h5py.File(registered) as f:
        for ref in f['observation']['states'][:].flat:
            r=f[ref]
            t,v=r['time_s'][:].reshape(-1),r['values'][:]
            if not np.array_equal(t,[2000,2000.001]) or v.shape[-1]!=2 or not np.isfinite(v).all():
                raise ValueError('Invalid registered state')
            states.append(dict(block_path=text_field(r['block_path']),state_name=text_field(r['state_name']),
                               channels=v.shape[0],initial_values=v[:,0].tolist(),final_values=v[:,1].tolist()))
    if len(states)!=73 or len({(r['block_path'],r['state_name']) for r in states})!=73:
        raise ValueError('Registered state identities incomplete')
    required=dict(ECC_Constitutive21_StateDelay=210,ECC_Constitutive21_SMA_TempDelay=21,ECC_Constitutive21_SE_TempDelay=21,
                  SEStage2PressurePI_Integrator=1,SEStage4PressurePI_Integrator=1,SMAPressurePI_Integrator=1,
                  SEStage2PressureFFTemperatureDelay=1,SEStage4PressureFFTemperatureDelay=1,
                  SEStage4PressureFFInletTemperatureDelay=1,SEStage4PressureFFOutletTemperatureDelay=1)
    selected=[]
    for name,channels in required.items():
        rows=[r for r in states if r['block_path'].endswith('/'+name)]
        if len(rows)!=1 or rows[0]['channels']!=channels:
            raise ValueError('Required memory state missing')
        selected.append(rows[0])
    solver=[r for r in states if r['block_path'].endswith('/Solver Configuration')]
    if len(solver)!=1 or solver[0]['channels']!=995:
        raise ValueError('Packed solver state inventory changed')
    result=dict(schema='heatdrive_ecc_c200_state_capture_v1',computation_complete=True,source=source_audit,
                all_observation_comparisons_pass=all(r['pass_endpoint_match'] for r in comparisons),
                observation_comparison_count=len(comparisons),maximum_observation_difference=max(r['max_abs_error'] for r in comparisons),
                registered_state_groups=73,registered_scalar_channels=sum(r['channels'] for r in states),
                required_memory_states=selected,all_registered_states=states,packed_solver_channels=995,
                packed_solver_semantic_mapping_verified=False,new_model_recovery_allowed=False,
                whole_model_first_law_verified=False,table4_reproduction_claim=False,
                input_sha256=dict(unobserved=sha256(left),observed=sha256(right),registered=sha256(registered),metadata=sha256(metadata_path)))
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('required_memory_states','all_registered_states','input_sha256')},indent=2))


if __name__=='__main__':
    main()
