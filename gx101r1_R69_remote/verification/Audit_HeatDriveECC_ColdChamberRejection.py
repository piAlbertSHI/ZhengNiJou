"""Read-only scientific rejection audit; never authorize a recovery chain."""
import argparse
import copy
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field
from Audit_HeatDriveECC_TLDomainInventory import resolve_domains


ROOT = 'heatdrive_ecc_coupled_se21/'
CHAMBERS = {ROOT+'SMA_PumpInletConnectingPipeVolume', ROOT+'SMA_PumpOutletConnectingPipeVolume'}


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def edges(data):
    vertices=data['vertices']
    return {(e['kind'], *sorted((vertices[e['a']-1]['key'], vertices[e['b']-1]['key'])))
            for e in data['edges']}


def check_topology(native, conservative):
    if edges(native)!=edges(conservative):
        raise ValueError('Physical edges changed')
    # This projection is only for hydraulic-domain assignment, not equations.
    projected=copy.deepcopy(conservative)
    changed=set()
    for block in projected['blocks']:
        if block['source_file']=='ecc_inventory.conservative_chamber':
            changed.add(block['block_path'])
            block['source_file']='foundation.thermal_liquid.elements.constant_volume_chamber'
    if changed!=CHAMBERS:
        raise ValueError('Unexpected custom component replacement set')
    a,ac=resolve_domains(native); b,bc=resolve_domains(projected)
    if ac!=2 or bc!=2 or a!=b:
        raise ValueError('Fluid domain assignment changed')
    return dict(physical_edges_identical=True, hydraulic_domains=ac,
                domain_assignment_identical=True, custom_projection_scope='two-port connectivity only')


def check_targets(targets, rows, volume, expected_hash):
    if len(targets)!=2 or {r['block_path'] for r in targets}!=CHAMBERS:
        raise ValueError('Wrong cold target coverage')
    for row in targets:
        p=row['block_path']
        if row['source_time_s']!=0 or row['source_sha256']!=expected_hash:
            raise ValueError('Target came from an unverified or nonzero-time source')
        rho=rows[p,'rho_I']; u=rows[p,'u_I']
        if text_field(rho['unit'])!='kg/m^3' or text_field(u['unit'])!='kJ/kg':
            raise ValueError('Wrong inventory target units')
        if rho['time_s'][0,0]!=0 or u['time_s'][0,0]!=0:
            raise ValueError('Nonzero cold time')
        mass=volume*float(rho['values'][0,0]); energy=mass*float(u['values'][0,0])*1000
        if not np.isclose(mass,row['stored_mass_kg'],atol=1e-15,rtol=0) or not np.isclose(energy,row['stored_energy_J'],atol=1e-10,rtol=0):
            raise ValueError('Cold inventory target does not equal the actual physical initial sample')


def audit(repo):
    roots=[repo/'outputs_storage_audit'/n for n in
           ('cold_chamber_smoke_20260908','cold_chamber_smoke_20260908_v2')]
    trials=[]; inputs={}
    for index,root in enumerate(roots):
        record=read(root/'cold_chamber_execution.json')
        expected=('8337923b22c00d7b90587242940a59e12b57b780',
                  'af01cafaa55c3e6d00509fc0197e09bc90bc6048')[index]
        if (record['execution_commit']!=expected or record['collection_pass'] or
                record['c200_state_imported'] or record['production_recovery_allowed'] or record['checkpoint_saved'] or
                record['full_device_first_law_verified'] or record['stop_time_s']!=.01 or record['start_time_s']!=0 or
                len(record['cases'])!=1 or record['cases'][0]['arm']!='native' or not record['error_message']):
            raise ValueError('Unexpected producer or rejection scope')
        if (root/'conservative/observations.mat').exists():
            raise ValueError('Unexpected successful conservative trajectory')
        topology=check_topology(read(root/'native/tl_connectivity.json'),read(root/'conservative/tl_connectivity.json'))
        if edges(read(root/'native/thermal_connectivity.json'))!=edges(read(root/'conservative/thermal_connectivity.json')):
            raise ValueError('Thermal edges changed')
        a=read(root/'native/inventory_metadata.json'); b=read(root/'conservative/inventory_metadata.json')
        if a['settings_tables']!=b['settings_tables'] or len(a['storage_blocks'])!=119 or len(b['storage_blocks'])!=119:
            raise ValueError('Missing inventory or different property tables')
        raw=root/'native/observations.mat'
        if sha256(raw)!=record['cases'][0]['observation_sha256']:
            raise ValueError('Native observation hash changed')
        with h5py.File(raw) as f:
            rows=named_rows(f,f['native'])
            if len(rows)!=1240:
                raise ValueError('Missing native traces')
            for row in rows.values():
                t=row['time_s'][:].reshape(-1); y=row['values'][:]
                if t.size!=11 or t[0]!=0 or abs(t[-1]-.01)>1e-15 or not np.isfinite(y).all():
                    raise ValueError('Incomplete finite smoke trajectory')
            if index==1:
                with h5py.File(root/'native/configuration.mat') as c:
                    volume=float(c['options/branch/sma_pump_manifold_volume_m3'][0,0])
                check_targets(read(root/'conservative/cold_inventory_targets.json'),rows,volume,sha256(raw))
        trials.append(dict(execution_commit=record['execution_commit'],collection_pass=False,
                           topology=topology,storage_count=119,native_trace_count=1240,native_samples=11,
                           conservative_valid_trajectory_available=False,initialization_target_test=index==1))
        for name in ('cold_chamber_execution.json','matlab_diary.log','native/observations.mat',
                     'native/configuration.mat','conservative/configuration.mat','native/inventory_metadata.json',
                     'conservative/inventory_metadata.json','native/tl_connectivity.json','conservative/tl_connectivity.json',
                     'native/thermal_connectivity.json','conservative/thermal_connectivity.json'):
            path=root/name; inputs[str(path.relative_to(repo))]=sha256(path)
        if index==1:
            for name in ('conservative/cold_inventory_targets.json','conservative/failed_output.mat'):
                path=root/name; inputs[str(path.relative_to(repo))]=sha256(path)
    with h5py.File(roots[0]/'native/observations.mat') as a,h5py.File(roots[1]/'native/observations.mat') as b:
        aa=named_rows(a,a['native']);bb=named_rows(b,b['native'])
        repeated=all(np.array_equal(v['time_s'][:],bb[k]['time_s'][:]) and
                     np.array_equal(v['values'][:],bb[k]['values'][:]) for k,v in aa.items())
    contract_path=repo/'verification/c200_mainline_freeze_contract.json'; contract=read(contract_path)
    for field in ('result','checkpoint'):
        path=repo/contract[field+'_relative_path']; digest=sha256(path)
        if digest!=contract[field+'_sha256']:
            raise ValueError('C200 authority changed')
        inputs[str(path.relative_to(repo))]=digest
    inputs[str(contract_path.relative_to(repo))]=sha256(contract_path)
    return dict(schema='heatdrive_ecc_cold_chamber_rejection_audit_v1',rejection_evidence_pass=True,
                native_repeated_bitwise_equal=repeated,trials=trials,full_cycle_completed=False,
                full_device_first_law_verified=False,production_recovery_allowed=False,
                table4_reproduction_claim=False,simulation_rerun=False,input_sha256=inputs,
                failure_mat_contains_serialized_simscape_node=False,
                missing_evidence='Actual failed initialization pressures were not recovered; no unique root cause established')


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path);args=parser.parse_args()
    result=audit(Path(__file__).resolve().parents[1])
    if args.output:
        if args.output.exists(): raise FileExistsError('Never overwrite evidence')
        args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k!='input_sha256'},ensure_ascii=False,indent=2))
    raise SystemExit(1)  # Scientific rejection remains visible even when evidence is complete.
