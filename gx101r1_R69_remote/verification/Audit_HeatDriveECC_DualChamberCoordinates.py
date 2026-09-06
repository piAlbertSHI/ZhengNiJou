"""Explain observed TP-coordinate BE errors without changing inventory gates."""
import argparse
import json
from pathlib import Path

import numpy as np

from Audit_HeatDriveECC_DualChamberSwitchResult import read_case
from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def cell_gradient(table,points):
    points=np.asarray(points,dtype=float)
    if points.ndim != 2 or points.shape[1] != 2 or not np.isfinite(points).all():
        raise ValueError('Expected finite T,p pairs')
    columns=[]
    cells=[]
    for axis,grid in enumerate(table.grid):
        if np.any(points[:,axis]<grid[0]) or np.any(points[:,axis]>grid[-1]):
            raise ValueError('Derivative evaluation outside table domain')
        index=np.clip(np.searchsorted(grid,points[:,axis],side='right')-1,0,len(grid)-2)
        low,high=points.copy(),points.copy()
        low[:,axis],high[:,axis]=grid[index],grid[index+1]
        columns.append((table(high)-table(low))/(grid[index+1]-grid[index]))
        cells.append(index)
    return np.column_stack(columns),np.column_stack(cells)


def coordinate_bridge(time,temperature,pressure,volume,mass_flow,power,table):
    arrays=[np.asarray(a,dtype=float) for a in (time,temperature,pressure,mass_flow,power)]
    t,temp,p,mdot,q=arrays
    if (t.ndim!=1 or len(t)<2 or any(a.shape!=t.shape for a in arrays) or not np.isfinite(arrays).all()
            or np.any(np.diff(t)<=0) or not np.isfinite(volume) or volume<=0):
        raise ValueError('Invalid coordinate ledger inputs')
    point=np.column_stack((temp,p))
    rho,u=table['rho'](point),table['u'](point)
    drho,cells=cell_gradient(table['rho'],point)
    du,u_cells=cell_gradient(table['u'],point)
    if not np.array_equal(cells,u_cells):
        raise ValueError('Require common rho/u table cells')
    delta,dt=np.diff(point,axis=0),np.diff(t)
    coordinate_mass=volume*np.sum(drho[1:]*delta,axis=1)
    coordinate_energy=volume*np.sum((drho*u[:,None]+du*rho[:,None])[1:]*delta,axis=1)
    mass_bridge=np.diff(volume*rho)-coordinate_mass
    energy_bridge=np.diff(volume*rho*u)-coordinate_energy
    dm_error=coordinate_mass-mdot[1:]*dt
    du_error=coordinate_energy-q[1:]*dt
    crossed=np.any(np.diff(cells,axis=0)!=0,axis=1)
    return dict(mass_coefficient_max_interval_error_kg=float(np.max(abs(dm_error))),
                energy_coefficient_max_interval_error_J=float(np.max(abs(du_error))),
                mass_explanation_max_cumulative_error_kg=float(np.max(abs(np.cumsum(dm_error)))),
                energy_explanation_max_cumulative_error_J=float(np.max(abs(np.cumsum(du_error)))),
                endpoint_mass_bridge_kg=float(mass_bridge.sum()),endpoint_energy_bridge_J=float(energy_bridge.sum()),
                within_cell_mass_bridge_kg=float(mass_bridge[~crossed].sum()),
                crossing_cell_mass_bridge_kg=float(mass_bridge[crossed].sum()),
                within_cell_energy_bridge_J=float(energy_bridge[~crossed].sum()),
                crossing_cell_energy_bridge_J=float(energy_bridge[crossed].sum()),
                table_cell_crossing_count=int(crossed.sum()),table_cell_crossing_right_times_s=t[1:][crossed].tolist(),
                omitted_intervals=0,compiler_state_selection_directly_observed=False,
                diagnostic_correction_subtracted_from_physical_gate=False)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite coordinate evidence')
    base=args.repo/'outputs_storage_audit'
    audit_path=base/'dual_chamber_tight_20260907/tight_audit_v1.json'
    audit=json.loads(audit_path.read_text())
    topology_path=base/'tl_domain_energy_tables_20260906/tl_domain_metadata.json'
    if (audit['tested_dual_inventory_closure_verified'] or not audit['all_spatial_port_identities_pass']
            or sha256(topology_path)!=audit['input_sha256']['topology']):
        raise ValueError('Unchanged failed ledger and physical table are required')
    data=json.loads(topology_path.read_text(encoding='utf-8-sig'))
    water=next(r for r in data['settings_tables'] if r['block_path'].endswith('/SMA_ThermalLiquidSettings'))
    table=energy_tables(water['parameters'])
    rows=[]
    for i in range(7,13):
        path=audit_path.parent/'trial'/f'case_{i}.mat'
        if sha256(path)!=audit['input_sha256'][f'case_{i}']:
            raise ValueError('Native trajectory changed')
        meta,t,p=read_case(path,finite_transition=True)
        for role in ('inlet','outlet'):
            v=p[role]
            row=coordinate_bridge(t,v['T_I'],v['p_I'],meta['volume_each_m3'],v['mdot_A']+v['mdot_B'],
                                   v['Phi_A']+v['Phi_B']+v['Q_H'],table)
            row.update(case_index=i,role=role,power_mode=meta['power_mode'],local_step_s=meta['local_step_s'])
            rows.append(row)
    result=dict(schema='heatdrive_ecc_dual_chamber_coordinate_diagnosis_v1',cases=rows,
                source_audit_sha256=sha256(audit_path),all_intervals_retained=True,
                observed_TP_coordinate_equations_match=all(r['mass_coefficient_max_interval_error_kg']<=1e-15
                                                           and r['energy_coefficient_max_interval_error_J']<=1e-8 for r in rows),
                max_mass_coefficient_error_kg=max(r['mass_coefficient_max_interval_error_kg'] for r in rows),
                max_energy_coefficient_error_J=max(r['energy_coefficient_max_interval_error_J'] for r in rows),
                max_cumulative_energy_explanation_error_J=max(r['energy_explanation_max_cumulative_error_J'] for r in rows),
                compiler_state_selection_directly_observed=False,physical_inventory_gate_pass=False,
                production_recovery_allowed=False,whole_model_first_law_verified=False,table4_reproduction_claim=False)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k!='cases'},indent=2))


if __name__=='__main__':
    main()
