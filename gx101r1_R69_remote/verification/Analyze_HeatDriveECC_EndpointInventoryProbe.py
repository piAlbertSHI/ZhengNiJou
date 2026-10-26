"""Read explicit shared cold inventory without granting production/periodic gates."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

import numpy as np

from Analyze_HeatDriveECC_CoupledCVBalance import load_case,storage,sources,balance_window,native_value
from Audit_HeatDriveECC_NativeInventoryCatalog import convert
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Review_HeatDriveECC_CoupledCVPacket import verify_sources,verify_arm
from Run_HeatDriveECC_ConservativeTransport import write_json


def initial_target_value(data,target):
    units={'K':('K',1.),'kg':('kg',1.),'J':('J',1.),'m':('m',1.),'kJ/kg':('J/kg',1000.),'MPa':('Pa',1e6)}
    unit=target['unit']
    if unit not in units:raise ValueError('Unsupported cold public target unit')
    row=data['native'][target['block_path'],target['state_name']]
    if not np.array_equal(row['time_s'],data['time']) or row['time_s'][0]!=0:
        raise ValueError('A cold target needs the actual zero-time native sample')
    value=float(row['values'][0,0])
    if row['unit']==unit:return value
    base,factor=units[unit]
    return float(convert(value,row['unit'],base))/factor


def analyze(root,output):
    read=lambda p:json.loads(p.read_text(encoding='utf-8'))
    e=read(root/'coupled_CV_execution.json');duration=e['stop_time_s']
    if not e['collection_complete'] or e['checkpoint_loaded_or_saved'] or e['inventory_formulation']!='endpoint_inventory':
        raise ValueError('Not a complete fresh endpoint inventory experiment')
    if len(e['completed_arms'])!=1 or e['completed_arms'][0]['arm']!='shared':raise ValueError('Require declared shared arm')
    verify_sources(e);case=e['completed_arms'][0];coverage=verify_arm(root,case,duration)
    data=load_case(root,case);components=storage(data);boundary=sources(data)
    construction=read(root/'shared/endpoint_inventory_construction.json')
    if (construction['public_targets_have_private_data'] or construction['private_state_or_checkpoint_loaded']
            or construction['initial_flux_compensation_applied'] or construction['old_topology_empirical_calibration_reused']):
        raise ValueError('Cold initialization imported a state or old calibration')
    source_folders={'conservative_chamber.ssc':'simscape_inventory_endpoint/+ecc_inventory_endpoint/',
                    'conservative_buffer.ssc':'simscape_buffer_coupled_offset/+ecc_buffer_coupled_offset/'}
    for row in construction['source_components']:
        path=Path(row['path']);relative='gx101r1_R69_remote/verification/'+source_folders[path.name]+path.name
        blob=subprocess.check_output(['git','show',e['execution_commit']+':'+relative])
        if hashlib.sha256(blob).hexdigest().upper()!=row['sha256']:raise ValueError('Compiled physical source not bound to execution commit')
    reference=Path(construction['reference_root']);reference_raw=reference/'shared/native_CV_observations.mat'
    if sha256(reference_raw)!=construction['reference_cold_native_sha256']:raise ValueError('Cold reference changed')
    targets=construction['public_targets']
    if len(targets)!=162 or sum(r['priority']=='High' for r in targets)!=104:raise ValueError('Wrong public target set')
    target_errors=[]
    for row in targets:
        actual=initial_target_value(data,row)
        target_errors.append(dict(path=row['path'],priority=row['priority'],unit=row['unit'],
                                  requested=row['value'],observed=actual,difference=actual-row['value']))
    window=balance_window(data,components,boundary,0,duration)
    equation_checks=[]
    for row in data['contract']['storage_blocks']:
        kind=row['mask_type'];path=row['block_path']
        if kind not in ('Endpoint Buffer','Endpoint Chamber'):continue
        v=lambda n,u:native_value(data,path,n,u)
        M=v('stored_mass','kg');U=v('stored_energy','J');rho=v('rho_I','kg/m^3');u=v('u_I','J/kg')
        T=v('T_I','K');P=v('p_I','Pa');table=data['tables'][data['assignment'][path]];coords=np.column_stack((T,P))
        if max(abs(table['rho'](coords)-rho))>1e-7 or max(abs(table['u'](coords)-u))>1e-6:
            raise ValueError('New inventory silently changed its declared property domain')
        if kind=='Endpoint Buffer':
            extended=sum((v(n,'J') for n in ('fluid_internal_energy','environment_pv_energy','gravitational_energy','auxiliary_energy')),np.zeros_like(T))
            eos_mass=M-rho*v('volume','m^3')
        else:
            extended=M*u
            volume=float(convert(row['mask_parameters']['volume']['value'],row['mask_parameters']['volume']['unit'],'m^3'))
            eos_mass=M-rho*volume
        c=next(r for r in components if r['path']==path);dt=np.diff(data['time'])
        energy=dt*c['power'][1:]-np.diff(U);mass=dt*c['mdot'][1:]-np.diff(M)
        equation_checks.append(dict(path=path,kind=kind,
            mass_equation_max_interval_abs_kg=float(abs(mass).max()),mass_equation_net_residual_kg=float(mass.sum()),
            energy_equation_max_interval_abs_J=float(abs(energy).max()),energy_equation_net_residual_J=float(energy.sum()),
            explicit_energy_state_definition_max_abs_J=float(abs(U-extended).max()),
            mass_EOS_max_abs_kg=float(abs(eos_mass).max()),temperature_range_K=[float(T.min()),float(T.max())],
            pressure_range_Pa=[float(P.min()),float(P.max())]))
    output.mkdir(parents=True,exist_ok=False)
    result=dict(schema='heatdrive_ecc_shared_endpoint_inventory_probe_v1',producer_commit=e['execution_commit'],
        execution_sha256=sha256(root/'coupled_CV_execution.json'),reader_sha256=sha256(Path(__file__)),
        coverage=coverage,duration_s=duration,initial_public_target_errors=target_errors,
        original_SMA_pipe_temperature_1e6_threshold_pass=case['initial_pipe_temperature_match_original_1e6_threshold'],
        endpoint_state_equation_checks=equation_checks,thermal_network_balance=window,
        auxiliary_gravity_environment_pv_are_in_buffer_state_not_external_heat=True,
        diagnostic_raw_is_not_OP_or_production_seed=True,all_mechanism_gates_evaluated=False,
        periodic_steady_state=False,production_recovery_allowed=False,Table4_reproduction_claim=False)
    write_json(output/'endpoint_inventory_probe.json',result)
    print(json.dumps(dict(output=str(output),coverage_pass=True,duration_s=duration,
                         native_equation_residual_J=window['BE_identified_native_equation_residual_J'],
                         production_recovery_allowed=False)))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('root','output'):p.add_argument('--'+name,type=Path,required=True)
    a=p.parse_args();analyze(a.root.resolve(),a.output.resolve())
