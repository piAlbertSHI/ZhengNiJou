"""Gate a real restored observation packet before its complete state may enter the split test."""
import argparse
import json
import re
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_ColdBufferCoupled import cycle_arm, port_contract
from Audit_HeatDriveECC_CoupledEnergyInventory import latent_decomposition, system_balance
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_TLDomainInventory import resolve_domains
from HeatDriveECC_ObservationWindow import window_indices


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def validate_manifest(manifest):
    start, stop = manifest['window_s']
    if (manifest['schema'] != 'heatdrive_ecc_split_observation_packet_v1' or
            not manifest['simulation_returned_without_error'] or manifest['source_state_edited'] or
            manifest['history_cap_cycles'] != 2 or manifest['state_history_cap_cycles'] != 11 or
            (not manifest['strict_vendor_restore'] and manifest.get('packet_role')!='runtime_boundary_cold_baseline') or manifest['production_recovery_allowed'] or
            manifest.get('packet_role','split_comparison') not in ('split_comparison','bounded_transient_observation','runtime_boundary_cold_baseline','runtime_boundary_transient','runtime_boundary_Tc_candidate','runtime_boundary_Tc_continuation') or
            start < 0 or stop-start not in (10, 20) or start % 10 or stop % 10):
        raise ValueError('Not a complete unchanged-model strict restored observation packet')
    if manifest.get('packet_role')=='bounded_transient_observation' and (
            stop-start!=20 or start<640 or stop>720 or
            not re.fullmatch('[A-F0-9]{64}',manifest.get('parent_complete_OP_sha256',''))):
        raise ValueError('Recording packets require the exact parent OP and bounded twenty-second interval')
    if manifest.get('packet_role')=='runtime_boundary_cold_baseline' and (
            [start,stop]!=[0,20] or manifest.get('source_snapshot_s')!=0 or
            manifest.get('independent_cold_start') is not True or manifest.get('parent_complete_OP_sha256')!='' or
            manifest.get('strict_vendor_restore') is not False or manifest.get('checksum_policy')!='error/error'):
        raise ValueError('The runtime family must start cold with no inherited complete state')
    if manifest.get('packet_role')=='runtime_boundary_transient' and (
            stop-start!=20 or start<20 or stop>2000 or manifest.get('independent_cold_start') is not False or
            manifest.get('source_snapshot_s')!=start or manifest.get('temperature_configurability')!='runtime' or
            manifest.get('prescribed_Tc_K')!=276.95 or manifest.get('command_horizon_cycles')!=200 or
            manifest.get('checksum_policy')!='error/error' or
            not re.fullmatch('[A-F0-9]{64}',manifest.get('parent_complete_OP_sha256',''))):
        raise ValueError('Runtime warmup requires an intact parent, same boundary and unchanged command horizon')
    if manifest.get('packet_role') in ('runtime_boundary_Tc_candidate','runtime_boundary_Tc_continuation'):
        t=manifest['boundary_trial'];Tc=t['candidate_Tc_K'];origin=t['transition_time_s']
        continuing=manifest['packet_role']=='runtime_boundary_Tc_continuation'
        if (t['schema']!='heatdrive_ecc_runtime_Tc_intervention_v1' or
                t['source_Tc_K']!=276.95 or not .001<abs(Tc-276.95)<=.1+1e-12 or
                t['minimum_transition_cycles']!=12 or t['source_state_edited'] or t['old_model_OP_imported'] or
                t['only_runtime_temperature_variable_changed'] is not True or
                stop-start!=20 or start<origin or origin<120 or origin%20 or (not continuing and stop>origin+200) or stop>2000 or
                manifest.get('independent_cold_start') is not False or manifest['source_snapshot_s']!=start or
                manifest.get('temperature_configurability')!='runtime' or manifest.get('prescribed_Tc_K')!=Tc or
                manifest.get('command_horizon_cycles')!=200 or manifest.get('checksum_policy')!='error/error' or
                any(not re.fullmatch('[A-F0-9]{64}',value) for value in
                    (manifest.get('parent_complete_OP_sha256',''),t['source_complete_OP_sha256'],
                     t['source_qualification_sha256'],t['plant_recipe_sha256'])) or
                (start==origin and manifest['parent_complete_OP_sha256']!=t['source_complete_OP_sha256'])):
            raise ValueError('Undeclared or incompatible fixed-Tc intervention')
        if continuing:
            c=manifest['continuation'];source=c['source_snapshot_s']
            if (c['temperature_unchanged'] is not True or source<400 or source%20 or
                    c['budget_stop_s']!=source+200 or start<source or stop>c['budget_stop_s'] or
                    any(not re.fullmatch('[A-F0-9]{64}',c[key]) for key in ('source_OP_sha256','source_qualification_sha256')) or
                    (start==source and manifest['parent_complete_OP_sha256']!=c['source_OP_sha256'])):
                raise ValueError('Continuation must preserve the qualified same-Tc state and its bounded budget')
    return start, stop


def reviewed_mechanism(original, proof, manifest_hash):
    checks = original['checks']
    failed = [name for name, value in checks.items() if not value]
    if (failed != ['qian_numerical_time_step_contract'] or
            proof['schema'] != 'heatdrive_ecc_observation_provenance_review_v1' or
            not proof['mechanism_pass'] or not proof['other_72_predicates_unchanged'] or
            proof['simulation_executed'] or proof['operating_point_loaded'] or proof['source_state_edited'] or
            proof['production_recovery_allowed'] or not proof['reference_comparison_only'] or
            proof['input_sha256']['original_manifest'] != manifest_hash or
            set(proof['metadata_fields_added']) != {'solver', 'fixed_step_s', 'simulation_mode'} or
            proof['actual_configuration']['solver'] != 'ode3' or
            proof['actual_configuration']['fixed_step_s'] != .001 or
            proof['actual_configuration']['simulation_mode'] not in ('normal', 'accelerator') or
            set(proof['checks']) != set(checks) or not all(proof['checks'].values()) or
            any(proof['checks'][name] != value for name, value in checks.items() if name not in failed)):
        raise ValueError('Only a source-bound missing-provenance review may qualify this reference')
    return dict(checks=proof['checks'], passed=proof['mechanism_pass'])


def audit(root, review_path=None):
    manifest = read(root/'packet_manifest.json')
    start, stop = validate_manifest(manifest)
    arm = root/'native'
    entries = manifest['input_files']
    required = {'native/observations.mat', 'native/configuration.mat', 'native/inventory_metadata.json',
                'native/tl_connectivity.json', 'native/thermal_connectivity.json',
                'native/buffer_replacement_contract.json', 'mechanism.json', 'observed_states.mat'}
    if len(entries) != len(required) or {row['path'] for row in entries} != required:
        raise ValueError('Missing or duplicate packet evidence role')
    for entry in entries:
        relative, expected = entry['path'], entry['sha256']
        path = (root/relative).resolve()
        if not path.is_relative_to(root.resolve()) or sha256(path) != expected:
            raise ValueError('Changed or escaped packet input: '+relative)
    if sha256(root/'comparison_only_complete_op.mat') != manifest['complete_OP_sha256']:
        raise ValueError('Complete comparison state changed')
    mechanism = read(root/'mechanism.json')
    if review_path is not None:
        proof = read(review_path)
        if Path(proof['source_packet_root']).resolve() != root or proof['input_sha256']['original_mechanism'] != sha256(root/'mechanism.json'):
            raise ValueError('Review is not bound to this actual packet')
        mechanism = reviewed_mechanism(mechanism, proof, sha256(root/'packet_manifest.json'))
    checks = mechanism['checks']
    if (len(checks) != 73 or any(type(value) is not bool for value in checks.values()) or
            not mechanism['passed'] or not all(checks.values())):
        raise ValueError('Original mechanism failed; do not propagate this packet')
    domains, count = resolve_domains(read(arm/'tl_connectivity.json'))
    if count != 2:
        raise ValueError('Fluid domain assignment changed')
    contracts = {row['block_path']: row for row in read(arm/'buffer_replacement_contract.json')['buffers']}
    for contract in contracts.values():
        port_contract(contract)
    ledger = cycle_arm(arm, domains, contracts, start=start, stop=stop,
                       mass_formulation='zero_based_offset', pressure_only_density=True)
    local = []
    for row in ledger['components']:
        if 'component_detail' in row:
            local.append(row['component_detail']['candidate_component_pass'])
        elif 'local_chamber_gate' in row:
            gate = row['local_chamber_gate']
            local.append(gate['mass_closure_pass'] and gate['energy_closure_pass'])
    with h5py.File(arm/'observations.mat') as f, h5py.File(arm/'configuration.mat') as cfg:
        if manifest.get('packet_role') in ('runtime_boundary_Tc_candidate','runtime_boundary_Tc_continuation'):
            if (float(cfg['options/system/Tchex_K'][0,0])!=manifest['prescribed_Tc_K'] or
                    float(cfg['plant_build_options/system/Tchex_K'][0,0])!=276.95):
                raise ValueError('Candidate analysis temperature must differ only by the declared runtime input')
        row = f['signals/ECC_constitutive21_output']
        indices = window_indices(row['time_s'][:], start, stop)
        time = row['time_s'][:].ravel()[indices]
        state = row['values'][:, indices]
        phase = np.vstack([state[a:b].mean(axis=0) for a, b in ((42, 63), (63, 84))])
        commands = sum(f['signals/'+name+'/values'][:, indices].sum(axis=0)
                       for name in ('ECC_Q_SMA_constitutive_W', 'ECC_Q_SE_constitutive_W'))
        coefficients = np.array([float(cfg['options/equilibrium/'+mass][0, 0])*
                                 float(cfg['options/material/'+material+'/Delta_h_J_per_kg'][0, 0])
                                 for mass, material in (('m_a_kg', 'SMA'), ('m_r_kg', 'SE'))])
        latent = latent_decomposition(time, commands, phase, coefficients)
    balance = system_balance({key: value['BE_energy_J'] for key, value in ledger['source_ledger'].items()},
                             ledger['actual_endpoint_storage_plus_pdv_J'], latent)
    passed = (len(local) == 6 and all(local) and balance['model_equation_energy_closure_pass'] and
              ledger['storage_count'] == 119 and ledger['source_count'] == 49 and
              all(row['selected_flow_gate'] for row in ledger['selected_flow_gates']))
    return dict(schema='heatdrive_ecc_split_observation_packet_gate_v1', window_s=[start, stop],
        gate_pass=bool(passed), original_mechanism_count=73, original_mechanism_pass=True,
        six_local_inventory_gates=local, modeled_energy_balance=balance,
        storage_count=ledger['storage_count'], source_count=ledger['source_count'],
        flow_gates=ledger['selected_flow_gates'],
        complete_state_is_only_for_current_split_comparison=manifest.get('packet_role','split_comparison')=='split_comparison',
        bounded_recording_scope_only=manifest.get('packet_role')=='bounded_transient_observation',
        runtime_boundary_transient_scope_only=manifest.get('packet_role')=='runtime_boundary_transient',
        ten_cycle_periodicity_claim=False, production_recovery_allowed=False, outer_solve_eligible=False,
        input_sha256=dict(manifest=sha256(root/'packet_manifest.json'),
                          mechanism_review=sha256(review_path) if review_path else ''))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--packet-root', required=True, type=Path)
    parser.add_argument('--mechanism-review', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    output = args.output or args.packet_root/'packet_gate.json'
    if output.exists():
        raise FileExistsError('Never overwrite a split observation gate')
    result = audit(args.packet_root.resolve(), args.mechanism_review)
    output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result['gate_pass'] else 1)
