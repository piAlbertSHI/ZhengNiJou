"""Verify same-run complete CV acquisition before interpreting mechanism/performance.

This is an observation-coverage audit, not an admission/periodicity gate.
No absent SMA channel is synthesized and no hidden state is reconstructed.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import subprocess

import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_SMAFlowCoordinates import liquid_wire_labels
from Audit_HeatDriveECC_ThermalConnectivity import wire_nets
from Audit_HeatDriveECC_TLDomainInventory import resolve_domains
from Audit_HeatDriveECC_NativeWindowLedger import validate_grid
from HeatDriveECC_TraceColumns import load
from Run_HeatDriveECC_ConservativeTransport import write_json


CORE_FIELDS={
    'Pipe (TL)':{'T_I','p_I','rho_I','u_I','h_I','mdot_A','mdot_B','Phi_A','Phi_B','Q_H'},
    'Tank (TL)':{'T_I','p_I','rho_I','u_I','h_I','mass','volume','mdot_A','Phi_A','Q_H'},
    'Constant Volume Chamber (TL)':{'T_I','p_I','rho_I','u_I','h_I','mdot_A','mdot_B','Phi_A','Phi_B','Q_H'},
    'Thermal Mass':{'T','Q'},
    'Endpoint Chamber':{'T_I','p_I','rho_I','u_I','stored_mass','stored_energy','mdot_A','mdot_B','Phi_A','Phi_B','Q_H'},
    'Endpoint Buffer':{'T_I','p_I','rho_I','u_I','stored_mass','stored_energy','mass_offset','volume','mdot_A','Phi_A','Q_H',
                       'fluid_internal_energy','environment_pv_energy','gravitational_energy','auxiliary_energy','auxiliary_capacity'},
}


def on_grid(row,clock):
    """Select actually recorded physical samples, not interpolated/held states."""
    t=row['time_s'];v=row['values']
    ix=np.searchsorted(t,clock+2e-14,side='right')-1
    if np.any(ix<0) or np.any(abs(t[ix]-clock)>2e-14):
        raise ValueError('Missing actual workspace sample on native clock')
    return v[ix]


def verify_sources(execution):
    fixed={'runner':'verification/Run_HeatDriveECC_SharedSMAColdInitial.m',
           'applicator':'verification/Apply_HeatDriveECC_SharedSMAFluidDiagnostic.m',
           'observer':'verification/'+execution['observer_function_name']+'.m',
           'observer_delegate':'verification/HeatDriveECC_ProcessLocalTimeObserver.m'}
    rows=[(fixed[k],v) for k,v in execution['source_sha256'].items()]
    for name,value in execution['CV_source_sha256'].items():
        if not re.fullmatch(r'[A-Za-z0-9_]+',name):raise ValueError('Invalid source identifier')
        relative=('' if name.startswith('Instrument_') else 'verification/')+name+'.m'
        rows.append((relative,value))
    for path,expected in rows:
        code=subprocess.check_output(['git','show',execution['execution_commit']+':gx101r1_R69_remote/'+path])
        if hashlib.sha256(code).hexdigest().upper()!=expected:
            raise ValueError('Runtime producer source hash differs from its Git identity')


def expected_storage_types(c,variant):
    if variant not in ('dual','shared'):raise ValueError('Unknown coupled topology')
    expected={'Pipe (TL)':67 if variant=='dual' else 46,'Tank (TL)':4,'Constant Volume Chamber (TL)':2,'Thermal Mass':46}
    if c['schema']=='heatdrive_ecc_endpoint_CV_inventory_v1':
        if variant!='shared' or c['storage_formulation']!='endpoint_inventory':raise ValueError('Wrong endpoint CV topology')
        expected={'Pipe (TL)':46,'Endpoint Buffer':4,'Endpoint Chamber':2,'Thermal Mass':46}
        root_model=c['storage_paths'][0].split('/')[0]
        named_buffers={root_model+'/'+n for n in ('ColdFluidBuffer','HotFluidBuffer','SHEXFluidBuffer','SMAHotFluidBuffer')}
        named_chambers={root_model+'/'+n for n in ('SMA_PumpInletConnectingPipeVolume','SMA_PumpOutletConnectingPipeVolume')}
        if set(c['endpoint_buffer_paths'])!=named_buffers or set(c['endpoint_chamber_paths'])!=named_chambers:
            raise ValueError('Endpoint identities cannot be inferred from a count')
        for row in c['storage_blocks']:
            if row['block_path'] in named_buffers and (row['mask_type']!='Endpoint Buffer' or row['source_file']!='ecc_buffer_coupled_offset.conservative_buffer'):
                raise ValueError('Wrong endpoint buffer source or ownership')
            if row['block_path'] in named_chambers and (row['mask_type']!='Endpoint Chamber' or row['source_file']!='ecc_inventory_endpoint.conservative_chamber'):
                raise ValueError('Wrong endpoint chamber source or ownership')
    elif c['schema']!='heatdrive_ecc_coupled_CV_inventory_v1':raise ValueError('Unsupported CV inventory schema')
    return expected


def verify_arm(root,case,duration):
    folder=root/case['arm'];record=case['CV_packet']
    files={'native':'native_CV_observations.mat','workspace':'workspace_CV_observations.mat','source':'source_CV_observations.mat','options':'CV_options.mat'}
    deps=[]
    for role,name in files.items():
        path=folder/name
        if sha256(path)!=record[role+'_sha256']:raise ValueError('Published raw CV file changed')
        deps.append({'path':str(path),'sha256':sha256(path),'bytes':path.stat().st_size})
    metadata_paths={'contract':'CV_contract.json','tl_topology':'CV_tl_topology.json','thermal_topology':'CV_thermal_topology.json'}
    bound='contract_file_sha256' in record
    if duration>=10 and not bound:raise ValueError('A cycle packet needs runtime-bound metadata hashes')
    for role,name in metadata_paths.items():
        p=folder/name
        if bound and sha256(p)!=record['contract_file_sha256'][role]:raise ValueError('CV metadata changed')
        deps.append({'path':str(p),'sha256':sha256(p),'bytes':p.stat().st_size})
    c=json.loads((folder/'CV_contract.json').read_text(encoding='utf-8'))
    tl=json.loads((folder/'CV_tl_topology.json').read_text(encoding='utf-8'))
    th=json.loads((folder/'CV_thermal_topology.json').read_text(encoding='utf-8'))
    assignment,domain_count=resolve_domains(tl)
    wires=liquid_wire_labels(tl);wire_nets(th)
    if domain_count!=2:raise ValueError('SMA/SE property domains were merged or split')
    variant=case['arm'];expected=expected_storage_types(c,variant)
    blocks=c['storage_blocks'];paths=[r['block_path'] for r in blocks]
    if len(set(paths))!=len(paths) or Counter(r['mask_type'] for r in blocks)!=expected or set(paths)!=set(c['storage_paths']):
        raise ValueError('Wrong topology-specific storage coverage')
    model=paths[0].split('/')[0]
    for component,group,count in (('SMA','Hold',21),('SMA','Cooldown',21 if variant=='dual' else 0),('SE','Hold',21)):
        actual={p for p in paths if re.search('/'+component+'/'+group+r'Pipe_\d{3}$',p)}
        required={f'{model}/{component}/{group}Pipe_{i:03}' for i in range(1,count+1)}
        if actual!=required:raise ValueError('Missing or unexpected regenerator coordinate')
    native=load(folder/files['native']);workspace=load(folder/files['workspace']);sources=load(folder/files['source'])
    if {p for p,n in native}!=set(paths):raise ValueError('Saved native stream ownership differs from exact inventory')
    clock=np.arange(round(duration/.001)+1)*.001
    for b in blocks:
        leaves={name for p,name in native if p==b['block_path']}
        if not CORE_FIELDS[b['mask_type']]<=leaves:raise ValueError('Missing actual mass/energy state or port')
        for name in CORE_FIELDS[b['mask_type']]:
            validate_grid(native[b['block_path'],name]['time_s'],0,duration,.001)
    required=set(c['required_workspace_variables'])
    if not required<={name for p,name in workspace}:raise ValueError('Required measured signal not saved')
    if len({p for p,n in sources})!=49:raise ValueError('Incomplete constitutive/external/pump source set')
    pump=c['pump_pressure_contract']['probes'];pressure=[]
    if len(pump)!=6:raise ValueError('Need six distinct A/B pressure probes')
    for p in pump:
        source=model+'/'+p['source_block'];sensor=model+'/'+p['sensor_block']
        if wires[source+':'+p['source_port_name']]!=wires[sensor+':A']:raise ValueError('Pump probe is on the wrong physical face')
        v=on_grid(workspace[model,p['workspace_variable']],clock).ravel()
        pressure.append({'source':source,'face':p['source_port_name'],'min_max_MPa':[float(v.min()),float(v.max())]})
    hexrows=[];seen=set();channel_paths={}
    for p in c['hex_port_probes']:
        match=re.fullmatch(r'cv_(shex|hhex_sma|hhex_se|chex)_([ab])_(T_K|P_Pa)',p['workspace_variable'])
        if not match:raise ValueError('Unregistered HEX probe quantity/channel')
        tag,face,quantity=match.groups();identity=(tag,face,quantity)
        if identity in seen or face.upper()!=p['port_name']:raise ValueError('Duplicate/misnamed actual HEX port')
        seen.add(identity);channel_paths.setdefault(tag,set()).add(p['block_path'])
        sensor=p.get('sensor_block',p['block_path'].rsplit('/',1)[0]+'/CV_'+tag+'_'+face+'_Sensor')
        if wires[p['block_path']+':'+p['port_name']]!=wires[sensor+':A']:raise ValueError('HEX probe on wrong named face')
        unit='K' if quantity=='T_K' else 'Pa'
        if p['unit']!=unit or p['quantity']!=('T' if unit=='K' else 'Pa'):raise ValueError('Absolute probe unit/port mismatch')
        v=on_grid(workspace[model,p['workspace_variable']],clock).ravel()
        hexrows.append({'tag':tag,'pipe':p['block_path'],'face':face.upper(),'unit':unit,'min_max':[float(v.min()),float(v.max())],
                        'settings_path':assignment[p['block_path']]})
    expected_hex={(tag,face,quantity) for tag in ('shex','hhex_sma','hhex_se','chex') for face in ('a','b') for quantity in ('T_K','P_Pa')}
    if seen!=expected_hex or any(len(v)!=1 for v in channel_paths.values()):raise ValueError('Missing exchanger face or ambiguous channel')
    errors={}
    for component in ('SMA','SE'):
        actual=np.column_stack([native[f'{model}/{component}/Subsystem2/NodeMass_{i:02}','T']['values'][:,0] for i in range(1,22)])
        measured=on_grid(workspace[model,component+'_Tx21_internal'],clock)
        if actual.shape!=measured.shape:raise ValueError('Spatial/time signal layout changed')
        errors[component]=float(np.max(abs(actual-measured)))
    pi=c.get('PI_memory_probes',[])
    if duration==20 and len(pi)!=3:raise ValueError('C2 requires explicit three-route PI memory observation')
    for p in pi:
        if p['controller_parameters_modified']:raise ValueError('Observation altered the controller')
        on_grid(workspace[model,p['workspace_variable']],clock)
    return {'arm':variant,'same_run_CV_capture_coverage_pass':True,'runtime_metadata_hashes_bound':bound,
            'component_count':len(paths),'type_counts':expected,'native_trace_count':len(native),'workspace_signal_count':len(workspace),
            'source_trace_count':len(sources),'source_count':49,'native_grid_sample_count':len(clock),'hydraulic_domain_count':domain_count,
            'pump_absolute_pressure_probes':pressure,'hex_absolute_port_probes':hexrows,'PI_memory_probe_count':len(pi),
            'solid_workspace_native_max_difference_K':errors,'input_dependencies':deps,
            'all_mechanism_energy_periodic_or_twenty_cycle_seed_qualified':False,'complete_hidden_state_or_OP_saved':False}


def review(root,output):
    p=root/'coupled_CV_execution.json';e=json.loads(p.read_text(encoding='utf-8'))
    if e['schema']!='heatdrive_ecc_coupled_CV_execution_v1' or not e['collection_complete'] or e['checkpoint_loaded_or_saved']:
        raise ValueError('Require a complete fresh same-run coupled CV package')
    verify_sources(e)
    result={'schema':'heatdrive_ecc_coupled_CV_capture_review_v1','producer_commit':e['execution_commit'],'reader_sha256':sha256(Path(__file__)),
            'execution_path':str(p),'execution_sha256':sha256(p),'duration_s':e['stop_time_s'],
            'arms':[verify_arm(root,c,e['stop_time_s']) for c in e['completed_arms']],
            'capture_complete_not_a_mechanism_gate':True,'production_recovery_or_Table4_claim':False}
    output.mkdir(parents=True,exist_ok=False);write_json(output/'coupled_CV_capture_review.json',result)
    print(json.dumps({'output':str(output),'arms':len(result['arms']),'coverage_pass':True,'mechanism_qualified':False}))
    return result


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--root',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();review(a.root.resolve(),a.output.resolve())
