"""Audit separately completed cold arms without manufacturing a final run receipt."""
import argparse
import hashlib
import json
import subprocess
import re
from pathlib import Path

import h5py

from Audit_HeatDriveECC_ColdBufferCoupled import cycle_arm, port_contract, CHAMBERS, BUFFERS
from Audit_HeatDriveECC_ColdChamberCycle import checked_rows
from Audit_HeatDriveECC_ColdChamberRejection import edges
from Audit_HeatDriveECC_ColdCoordinateSmoke import compare_initial, scalar_series
from Audit_HeatDriveECC_CompiledInventoryStates import decode_tags, component_inventory_preserved
from Audit_HeatDriveECC_DistributedPressureRuntime import audit_arm, read_json
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_TLDomainInventory import resolve_domains

PRODUCERS = {'native': '83306d76950a807fbfc68c3ffb8f34ca100d6fa1',
             'conservative': '41bf44c9a0e06be62da5719cf89320ebbda45f0e'}
INITIAL_SHA = '4AE82B42865AE1EAF3BC0D0467FBFD9CB954894A218C59AEEF59CC63122F3F83'


def audit(native, conservative, repo, expected_producers=None):
    producers=PRODUCERS if expected_producers is None else expected_producers
    if set(producers)!={'native','conservative'} or any(not re.fullmatch('[0-9a-f]{40}',c) for c in producers.values()):
        raise ValueError('Require exact explicitly selected producer commits')
    folders = {'native': native, 'conservative': conservative}
    metas = {a: read_json(p/'inventory_metadata.json') for a,p in folders.items()}
    if (metas['native']['settings_tables'] != metas['conservative']['settings_tables'] or
            metas['native']['storage_blocks'] != metas['conservative']['storage_blocks']):
        raise ValueError('Physical storage/initialization/property contracts differ')
    for name in ('tl_connectivity.json','thermal_connectivity.json'):
        if edges(read_json(native/name)) != edges(read_json(conservative/name)):
            raise ValueError('Physical edges differ: '+name)
    files = ('Build_HeatDriveECC_EighthRound_Defaults.m','Build_HeatDriveECC_EighthRound_Simulink_Model.m',
             'Integrate_HeatDriveECC_Constitutive21_Interface.m','heatdrive_ecc_coupled_se21.slx',
             'verification/Configure_HeatDriveECC_DistributedPressureFeedforward.m')
    source_hashes = {}
    for name in files:
        hashes = [hashlib.sha256(subprocess.check_output(['git','show',f'{c}:gx101r1_R69_remote/{name}'],cwd=repo)).hexdigest()
                  for c in producers.values()]
        if hashes[0] != hashes[1]:
            raise ValueError('Physical/control implementation differs: '+name)
        source_hashes[name] = hashes[0]
    envelope_file='verification/Build_HeatDriveECC_DistributedPressureEnvelope.m'
    present=[subprocess.run(['git','cat-file','-e',f'{c}:gx101r1_R69_remote/{envelope_file}'],
                           cwd=repo,capture_output=True).returncode==0 for c in producers.values()]
    if any(present):
        if not all(present): raise ValueError('Envelope implementation differs')
        hashes=[hashlib.sha256(subprocess.check_output(['git','show',f'{c}:gx101r1_R69_remote/{envelope_file}'],cwd=repo)).hexdigest()
                for c in producers.values()]
        if hashes[0]!=hashes[1]: raise ValueError('Pressure envelope implementation differs')
        source_hashes[envelope_file]=hashes[0]
    arms=[]; gates=[]; hashes={}
    for name,folder in folders.items():
        completion = read_json(folder/'arm_completion.json')
        if completion['arm'] != name or completion['execution_commit'] != producers[name]:
            raise ValueError('Unexpected completed-arm producer')
        public = read_json(folder/'public_inventory_targets.json')
        if public['source_sha256'] != INITIAL_SHA or public['source_time_s'] != 0 or len(public['targets']) != 204:
            raise ValueError('Different or incomplete t=0 initialization')
        topo=read_json(folder/'tl_connectivity.json')
        assignment,domains=resolve_domains(topo)
        if domains != 2:
            raise ValueError('Wrong fluid domain coverage')
        contracts={r['block_path']:r for r in read_json(folder/'buffer_replacement_contract.json')['buffers']}
        if set(contracts) != BUFFERS:
            raise ValueError('Buffer coverage missing')
        for c in contracts.values():
            port_contract(c)
        tags=[dict(block_name=r['block_name'],variable_name=r['variable_name'],**decode_tags(r))
              for r in read_json(folder/'compiled_inventory_tags.json')['node_metadata']]
        chamber_names={p.split('/',1)[1] for p in CHAMBERS}
        buffer_names={p.split('/',1)[1] for p in BUFFERS}
        compiled=(component_inventory_preserved([r for r in tags if r['block_name'] in chamber_names],chamber_names)
                  and component_inventory_preserved([r for r in tags if r['block_name'] in buffer_names],buffer_names,
                        variables={'mass_offset','stored_energy','T_I','p_I'},
                        differential_variables=('mass_offset','stored_energy')))
        runtime=audit_arm(folder)
        ledger=cycle_arm(folder,assignment,contracts,mass_formulation='zero_based_offset')
        local=[]
        for r in ledger['components']:
            if r['mask_type']=='Conservative Buffer (TL)':
                local.append(r['component_detail']['candidate_component_pass'])
            elif r['block_path'] in CHAMBERS:
                local.append(r['local_chamber_gate']['mass_closure_pass'] and r['local_chamber_gate']['energy_closure_pass'])
        local_pass=len(local)==6 and all(local)
        boundary=runtime['pressure_boundary']
        gate=(compiled and local_pass and runtime['distributed_controller_runtime_pass']
              and runtime['selected_flow_gates_pass'] and runtime['phase_bounds_pass'] and runtime['solid_energy_pass']
              and boundary['pressure_range_gate'] and boundary['hydraulic_diagnostic_gate'])
        gates.append(gate)
        arms.append(dict(arm=name,completed_arm_mechanism_subset_pass=gate,
            trajectory_compiled_inventory_gate=compiled,local_inventory_conservation_pass=local_pass,
            source_minus_actual_endpoint_storage_J=ledger['source_minus_actual_endpoint_storage_J'],
            declared_source_storage_scope_not_full_device=True,
            components=ledger['components'],source_ledger=ledger['source_ledger'],
            runtime=runtime))
        hashes[name]={f:sha256(folder/f) for f in ('arm_completion.json','observations.mat','configuration.mat',
            'distributed_pressure_ff_contract.json','public_inventory_targets.json','runtime_inventory_targets.json',
            'buffer_replacement_contract.json','compiled_inventory_tags.json')}
    comparisons=[]
    targets=read_json(conservative/'public_inventory_targets.json')['targets']
    with h5py.File(native/'observations.mat') as a, h5py.File(conservative/'observations.mat') as b:
        aa=checked_rows(a,'native',1262,10,0); bb=checked_rows(b,'native',1262,10,0)
        for t in targets:
            key=t['block_path'],t['state_name']
            comparisons.append(dict(path=t['path'],priority=t['priority'],unit=t['unit'],
                **compare_initial(scalar_series(bb[key],t['unit'])[0],scalar_series(aa[key],t['unit'])[0])))
    strict=len(comparisons)==204 and len({r['path'] for r in comparisons})==204 and all(r['within_strict_comparison'] for r in comparisons)
    return dict(schema='heatdrive_ecc_separate_completed_cold_arms_v1',
        completed_arm_roots={a:str(p.resolve()) for a,p in folders.items()},
        cold_initialization_observation_sha256=INITIAL_SHA,
        original_package_receipts_not_rewritten=True,arms=arms,source_sha256=source_hashes,
        input_sha256=hashes,initial_coordinate_comparisons=comparisons,
        strict_initial_coordinate_match=strict,
        initial_matching_counts={p:sum(r['within_strict_comparison'] for r in comparisons if r['priority']==p) for p in ('High','Low')},
        cold_mechanism_subset_pass=bool(strict and all(gates)),
        twenty_cycle_independent_cold_exploration_allowed=bool(strict and all(gates)),
        continuation_or_endpoint_seed_allowed=False,
        all_mechanism_gates_evaluated=False,whole_model_periodic_state_verified=False,
        full_device_first_law_verified=False,production_recovery_allowed=False,table4_reproduction_claim=False)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--native-arm-root',type=Path,required=True)
    p.add_argument('--conservative-arm-root',type=Path,required=True)
    p.add_argument('--repo',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--expected-native-producer')
    p.add_argument('--expected-conservative-producer')
    a=p.parse_args()
    if a.output.exists(): raise FileExistsError('Never overwrite evidence')
    if bool(a.expected_native_producer)!=bool(a.expected_conservative_producer):
        raise ValueError('Select both exact producers or retain the historical pair')
    producers=dict(native=a.expected_native_producer,conservative=a.expected_conservative_producer) if a.expected_native_producer else None
    result=audit(a.native_arm_root,a.conservative_arm_root,a.repo,producers)
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('arms','input_sha256','source_sha256','initial_coordinate_comparisons')},indent=2))
    return 0 if result['cold_mechanism_subset_pass'] else 1


if __name__=='__main__':
    raise SystemExit(main())
