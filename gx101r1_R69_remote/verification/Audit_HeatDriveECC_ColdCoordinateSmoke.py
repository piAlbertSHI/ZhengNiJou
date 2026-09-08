"""Audit measured cold coordinates and chamber ledgers without granting recovery."""
import argparse
import csv
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdChamberRejection import CHAMBERS, check_topology, read
from Audit_HeatDriveECC_ConservativeChamberResult import MASS_ATOL_KG, ENERGY_ATOL_J
from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_NativeWindowLedger import validate_grid
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field


PRODUCER='215185e228a504224541a413aea65a373c809ace'


def compare_initial(actual,expected):
    if not np.isfinite([actual,expected]).all():
        raise ValueError('Nonfinite coordinate')
    delta=abs(actual-expected);limit=1e-10+1e-11*abs(expected)
    return dict(actual=float(actual),expected=float(expected),abs_error=float(delta),
                limit=float(limit),within_strict_comparison=bool(delta<=limit))


def scalar_series(row,unit):
    native=text_field(row['unit']);values=np.asarray(row['values'][:],dtype=float).reshape(-1)
    if native==unit: return values
    return convert(values,native,unit)


def ledger(time,mass,energy,mass_flow,power):
    arrays=[np.asarray(x,dtype=float) for x in (time,mass,energy,mass_flow,power)]
    time,mass,energy,mass_flow,power=arrays
    if (any(x.shape!=time.shape for x in arrays) or time.ndim!=1 or time.size<2 or
            not np.isfinite(arrays).all() or np.any(np.diff(time)<=0) or np.any(mass<=0)):
        raise ValueError('Invalid open chamber ledger inputs')
    dm=np.r_[0,np.cumsum(mass_flow[1:]*np.diff(time))]-(mass-mass[0])
    de=np.r_[0,np.cumsum(power[1:]*np.diff(time))]-(energy-energy[0])
    return dict(mass_max_abs_residual_kg=float(abs(dm).max()),energy_max_abs_residual_J=float(abs(de).max()),
                mass_end_residual_kg=float(dm[-1]),energy_end_residual_J=float(de[-1]),
                mass_limit_kg=MASS_ATOL_KG,energy_limit_J=ENERGY_ATOL_J,
                mass_closure_pass=bool(np.all(abs(dm)<=MASS_ATOL_KG)),
                energy_closure_pass=bool(np.all(abs(de)<=ENERGY_ATOL_J)),
                integral_scheme='local backward Euler, every native interval, actual initial inventory')


def audit(repo):
    root=repo/'outputs_storage_audit/cold_chamber_public_coordinates_smoke_20260909'
    execution=read(root/'cold_chamber_execution.json')
    if (execution['execution_commit']!=PRODUCER or not execution['collection_pass'] or
            execution['production_recovery_allowed'] or execution['c200_state_imported'] or
            execution['checkpoint_saved'] or execution['start_time_s']!=0 or execution['stop_time_s']!=.01 or
            not execution['physical_pipe_energy_high_targets'] or len(execution['cases'])!=2):
        raise ValueError('Wrong experiment scope or producer')
    topo=check_topology(read(root/'native/tl_connectivity.json'),read(root/'conservative/tl_connectivity.json'))
    targets=read(root/'conservative/public_inventory_targets.json')
    source=root/'native/observations.mat'; candidate=root/'conservative/observations.mat'
    if targets['has_private_data'] or targets['source_time_s']!=0 or targets['source_sha256']!=sha256(source):
        raise ValueError('Invalid target provenance')
    for row in execution['cases']:
        if sha256(root/row['arm']/'observations.mat')!=row['observation_sha256']:
            raise ValueError('Raw observation changed')
    if len(targets['targets'])!=200 or sum(t['priority']=='High' for t in targets['targets'])!=125:
        raise ValueError('Incomplete target coverage')
    with h5py.File(root/'native/configuration.mat') as config:
        volume=float(config['options/branch/sma_pump_manifold_volume_m3'][0,0])
        if (float(config['options/simscape/local_solver_sample_time_s'][0,0])!=.001 or
                text_field(config['options/simscape/local_solver_choice'])!='NE_BACKWARD_EULER_ADVANCER'):
            raise ValueError('Ledger requires the declared local BE solver')
    comparisons=[];chambers=[]
    with h5py.File(source) as a,h5py.File(candidate) as b:
        aa=named_rows(a,a['native']);bb=named_rows(b,b['native'])
        if len(aa)!=1240 or len(bb)!=1242:
            raise ValueError('Incomplete native inventory')
        for rows in (aa,bb):
            for row in rows.values():
                t=row['time_s'][:].reshape(-1);validate_grid(t,0,.01,.001)
                if row['values'].shape!=(1,11) or not np.isfinite(row['values'][:]).all():
                    raise ValueError('Incomplete finite scalar trace')
        seen=set()
        for target in targets['targets']:
            key=target['block_path'],target['state_name'];unit=target['unit']
            if key in seen or target['source_time_s']!=0 or target['priority'] not in ('High','Low'):
                raise ValueError('Duplicate or invalid target')
            seen.add(key)
            if key[1] in ('stored_mass','stored_energy'):
                if key[0] not in CHAMBERS: raise ValueError('Unexpected inventory alias')
                expected=volume*scalar_series(aa[key[0],'rho_I'],'kg/m^3')[0]
                if key[1]=='stored_energy': expected*=scalar_series(aa[key[0],'u_I'],'J/kg')[0]
            else:
                expected=scalar_series(aa[key],unit)[0]
            if abs(target['value']-expected)>1e-12*max(1,abs(expected)):
                raise ValueError('Declared target differs from actual native cold t=0')
            actual=scalar_series(bb[key],unit)[0]
            comparisons.append(dict(path=target['path'],priority=target['priority'],unit=unit,
                                    **compare_initial(actual,expected)))
        for arm,rows in (('native',aa),('conservative',bb)):
            for p in sorted(CHAMBERS):
                get=lambda n,u:scalar_series(rows[p,n],u)
                t=rows[p,'rho_I']['time_s'][:].reshape(-1)
                mass=volume*get('rho_I','kg/m^3');energy=mass*get('u_I','J/kg')
                row=dict(arm=arm,block_path=p,**ledger(t,mass,energy,
                    get('mdot_A','kg/s')+get('mdot_B','kg/s'),get('Phi_A','W')+get('Phi_B','W')+get('Q_H','W')))
                if arm=='conservative':
                    row['stored_mass_alias_max_error_kg']=float(abs(mass-get('stored_mass','kg')).max())
                    row['stored_energy_alias_max_error_J']=float(abs(energy-get('stored_energy','J')).max())
                chambers.append(row)
        temp_delta=max(float(abs(v['values'][0,0]-aa[k]['values'][0,0])) for k,v in bb.items()
                       if k in aa and k[1] in ('T','T_I'))
    high=[r for r in comparisons if r['priority']=='High'];low=[r for r in comparisons if r['priority']=='Low']
    files=[root/'cold_chamber_execution.json',root/'matlab_diary.log',root/'conservative/public_inventory_targets.json',
           root/'conservative/cold_public_targets.mat']
    for arm in ('native','conservative'):
        files.extend(root/arm/name for name in ('observations.mat','configuration.mat','inventory_metadata.json',
                                               'tl_connectivity.json','thermal_connectivity.json'))
    contract_path=repo/'verification/c200_mainline_freeze_contract.json'; contract=read(contract_path)
    files.append(contract_path)
    for key in ('result','checkpoint'):
        p=repo/contract[key+'_relative_path']
        if sha256(p)!=contract[key+'_sha256']:raise ValueError('C200 authority changed')
        files.append(p)
    return dict(schema='heatdrive_ecc_cold_coordinate_smoke_audit_v1',evidence_audit_pass=True,
                execution_commit=PRODUCER,topology=topo,source_time_s=0,stop_time_s=.01,samples=11,
                primary_count=len(high),primary_strict_matching_count=sum(r['within_strict_comparison'] for r in high),
                auxiliary_count=len(low),auxiliary_strict_matching_count=sum(r['within_strict_comparison'] for r in low),
                strict_initial_coordinate_match=all(r['within_strict_comparison'] for r in comparisons),
                max_initial_temperature_difference_K=temp_delta,chamber_ledgers=chambers,
                chamber_ledger_is_not_full_system_closure=True,full_cycle_completed=False,
                full_device_first_law_verified=False,production_recovery_allowed=False,table4_reproduction_claim=False,
                initialization_inconsistency_warning_retained=True,
                input_sha256={str(p.relative_to(repo)):sha256(p) for p in files}),comparisons


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output-root',type=Path);args=p.parse_args()
    result,rows=audit(Path(__file__).resolve().parents[1])
    if args.output_root:
        args.output_root.mkdir(exist_ok=False,parents=True)
        (args.output_root/'cold_coordinate_audit.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
        with (args.output_root/'initial_coordinates.csv').open('w',newline='',encoding='utf-8') as f:
            writer=csv.DictWriter(f,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
    print(json.dumps({k:v for k,v in result.items() if k!='input_sha256'},indent=2))
    raise SystemExit(0 if result['strict_initial_coordinate_match'] else 1)
