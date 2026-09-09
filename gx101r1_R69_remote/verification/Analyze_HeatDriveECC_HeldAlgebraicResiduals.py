"""Compare recorded inventory identities with reference-snapshot property tables."""
import argparse
import copy
import json
from pathlib import Path
import h5py
import numpy as np
from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_ColdPassivePSObserver import read, sha256, CHAMBERS, BUFFERS
from Audit_HeatDriveECC_TLDomainInventory import resolve_domains
from Audit_HeatDriveECC_NativeAccumulation import energy_tables


def reference_domains(topology):
    # These aliases describe TL port continuity only, not storage equations.
    graph=copy.deepcopy(topology)
    changes=[]
    for b in graph['blocks']:
        name=b['block_path'].rsplit('/',1)[-1]
        if name in CHAMBERS:
            if b['source_file']!='ecc_inventory.conservative_chamber':
                raise ValueError('Unexpected reference chamber source')
            replacement='foundation.thermal_liquid.elements.constant_volume_chamber'
        elif name in BUFFERS:
            if b['source_file']!='ecc_buffer_coupled.conservative_buffer':
                raise ValueError('Unexpected reference buffer source')
            replacement='fluids.thermal_liquid.tanks_accumulators.tank'
        else:
            continue
        changes.append(dict(block_path=b['block_path'],source=b['source_file'],graph_only_alias=replacement))
        b['source_file']=replacement
    if len(changes)!=6:raise ValueError('Incomplete reference replacement graph')
    assignment,count=resolve_domains(graph)
    if count!=2:raise ValueError('Reference topology no longer has two TL domains')
    return assignment,changes


def residual_stats(values):
    v=np.asarray(values,dtype=float)
    if v.ndim!=1 or v.size<2 or not np.isfinite(v).all():
        raise ValueError('Require finite full identity residual series')
    return dict(maximum_absolute=float(np.max(abs(v))),initial=float(v[0]),final=float(v[-1]),
                maximum_change_from_initial=float(np.max(abs(v-v[0]))))


def analyze(repo):
    root=repo/'outputs_storage_audit'
    source=root/'conservative_buffer_coupled_cycle_20260909/conservative'
    metadata_path=source/'inventory_metadata.json';metadata=read(metadata_path)
    topology_path=source/'tl_connectivity.json';assignment,aliases=reference_domains(read(topology_path))
    audit_path=root/'hybrid_held_moderate_control_audit_20260910/held_interval_audit.json';audit=read(audit_path)
    if sha256(audit_path)!='48ECCCA5D663B1F423CA838D5A84F7EECD9A74D59B4564079B4F941FC8E7A2F9':
        raise ValueError('Moderate-control audit changed')
    for relative,expected in audit['input_sha256'].items():
        if sha256(repo/relative)!=expected:raise ValueError('Recorded trajectory dependency changed')
    tables={b['block_path']:energy_tables(b['parameters']) for b in metadata['settings_tables']}
    parameters={b['block_path']:b['mask_parameters'] for b in metadata['storage_blocks']}
    raw=root/'specific_inventory_hybrid_held_moderate_control_20260910/observations.mat'
    result=[]
    with h5py.File(raw) as f:
        rows=named_rows(f,f['native'])
        for name in sorted(CHAMBERS|BUFFERS):
            path='heatdrive_ecc_coupled_se21/'+name;p=parameters[path];table=tables[assignment[path]]
            t=rows[path,'stored_mass']['time_s'][:].ravel()
            def get(n,u):
                row=rows[path,n]
                if not np.array_equal(t,row['time_s'][:].ravel()):raise ValueError('Identity data unaligned')
                v=scalar_series(row,u)
                if v.shape!=t.shape or not np.isfinite(v).all():raise ValueError('Invalid identity data')
                return v
            def param(n,u):
                r=p[n]
                if r['unit']!=u or not np.isfinite(r['value']):raise ValueError('Unexpected parameter units')
                return r['value']
            m=get('stored_mass','kg');e=get('stored_energy','J');rho=get('rho_I','kg/m^3')
            u=get('u_I','J/kg');temp=get('T_I','K');pressure=get('p_I','Pa')
            coords=np.column_stack((temp,pressure));lookup_rho=table['rho'](coords);lookup_u=table['u'](coords)
            if name in CHAMBERS:
                volume=param('volume','m^3')
                identities={'M_minus_rho_V_kg':m-rho*volume,'U_minus_M_u_J':e-m*u}
            else:
                volume=get('volume','m^3');level=get('level','m');capacity=get('auxiliary_capacity','J/K')
                area=param('tank_area','m^2');pe=param('p_environment','Pa');g=param('gravity','m/s^2')
                tr=param('reference_temperature','K');depth=param('auxiliary_depth','m')
                energy_terms=[get(n,'J') for n in ('fluid_internal_energy','environment_pv_energy','gravitational_energy','auxiliary_energy')]
                c_ref=float((area*depth*table['rho']([[tr,pe]])*table['cp']([[tr,pe]]))[0])
                identities={'M_minus_rho_V_kg':m-rho*volume,
                    'U_minus_recorded_extended_energy_J':e-sum(energy_terms),
                    'fluid_internal_energy_minus_M_u_J':energy_terms[0]-m*u,
                    'environment_energy_minus_p_V_J':energy_terms[1]-pe*volume,
                    'gravity_energy_minus_M_g_h_over_2_J':energy_terms[2]-m*g*level/2,
                    'auxiliary_energy_minus_C_delta_T_J':energy_terms[3]-capacity*(temp-tr),
                    'U_minus_reconstructed_extended_energy_J':e-(m*u+pe*volume+m*g*level/2+capacity*(temp-tr)),
                    'volume_minus_area_level_m3':volume-area*level,
                    'internal_pressure_minus_environment_Pa':pressure-pe,
                    'bottom_pressure_minus_hydrostatic_Pa':get('p_A','Pa')-(pe+rho*g*level),
                    'auxiliary_capacity_minus_reference_lookup_J_K':capacity-c_ref}
            identities.update(rho_minus_reference_lookup_kg_m3=rho-lookup_rho,
                u_minus_reference_lookup_J_kg=u-lookup_u,
                reference_density_mismatch_as_inventory_kg=(rho-lookup_rho)*volume,
                reference_energy_mismatch_as_inventory_J=(u-lookup_u)*m)
            result.append(dict(block_path=path,reference_settings_path=assignment[path],sample_count=len(t),
                identity_residuals={k:residual_stats(v) for k,v in identities.items()},
                actual_mass_range_kg=[float(m.min()),float(m.max())],
                actual_energy_range_J=[float(e.min()),float(e.max())],
                measured_dynamic_balance=next(r for r in audit['local_balances'] if r['block_path']==path)))
    files=[metadata_path,topology_path,audit_path,raw,
           repo/'verification/simscape_inventory_specific/+ecc_inventory_specific/conservative_chamber.ssc',
           repo/'verification/simscape_buffer_coupled/+ecc_buffer_coupled/conservative_buffer.ssc']
    return dict(component_algebraic_residuals=result,reference_graph_aliases=aliases,
                geometry_and_tables_source='Saved cold reference metadata, not a fresh runtime parameter export',
                fresh_runtime_parameter_metadata_verified=False,unique_root_cause_verified=False,
                derivative_equations_audited_by_this_tool=False,
                local_balance_gate=audit['local_balance_gate'],production_recovery_allowed=False,
                full_system_first_law_verified=False,table4_reproduction_claim=False,
                input_sha256={str(p.relative_to(repo)):sha256(p) for p in files})


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output-root',type=Path,required=True);a=p.parse_args()
    if a.output_root.exists():raise FileExistsError('Never overwrite evidence')
    r=analyze(Path(__file__).resolve().parents[1]);a.output_root.mkdir(parents=True)
    (a.output_root/'algebraic_residuals.json').write_text(json.dumps(r,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in r.items() if k not in ('component_algebraic_residuals','reference_graph_aliases')},indent=2))
