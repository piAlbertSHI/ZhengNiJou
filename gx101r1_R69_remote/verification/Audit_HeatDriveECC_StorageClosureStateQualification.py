"""Bind new C2 state and numerical ledgers; no periodic or production authority."""
import argparse
import copy
import json
from pathlib import Path

import h5py
import numpy as np

from Analyze_HeatDriveECC_ManifoldStorageClosure import compare_metadata
from Analyze_HeatDriveECC_SECommutationInventory import partition
from Analyze_HeatDriveECC_SEReferenceCounterfactual import controller_contract
from Audit_HeatDriveECC_ColdBufferCoupled import cycle_arm, port_contract
from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_CompiledInventoryStates import decode_tags, component_inventory_preserved
from Audit_HeatDriveECC_CoupledEnergyInventory import ROOT, latent_decomposition, system_balance
from Audit_HeatDriveECC_DistributedPressureRuntime import audit_arm as runtime_audit
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_TLDomainInventory import resolve_domains


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def compare_c2_configs(old, new):
    old, new = copy.deepcopy(old), copy.deepcopy(new)
    intervention = new.pop('diagnostic_inventory_options')
    if set(intervention) != {'storage_closure', 'cold_followup_audit_path'} or \
            intervention['storage_closure'] != 'pressure_only_density':
        raise ValueError('An undeclared inventory intervention changed')
    for config in (old, new):
        config.pop('output_root')
        if (config['duration_s'] != 20 or config['cycle_count'] != 2 or
                config['diagnostic_state_options'] != {'mode': 'restore_preflight', 'command_horizon_cycles': 200}):
            raise ValueError('Require matched C2 and fixed command horizon')
    if old != new:
        raise ValueError('A control, physical or initial input changed beyond the density law')


def verify_restore_record(restore):
    if (not restore['same_model_restore_preflight_pass'] or restore['checksum_policy'] != 'error/error' or
            restore['source_state_edited'] or restore['partial_state_restore_used'] or
            restore['complete_cycle_resume_verified'] or restore['snapshot_time_s'] != 20 or
            restore['comparison_stop_s'] != 20.001 or len(restore['state_comparisons']) != 74 or
            len(restore['signal_comparisons']) != 201 or
            not all(row['values_exact'] and row['clock_pass'] for row in restore['state_comparisons']) or
            not all(row['values_exact'] for row in restore['signal_comparisons'])):
        raise ValueError('Missing, relaxed or overstated same-model disk restore')


def audit(root, c1_audit_path, baseline_state_audit_path):
    manifest = read(root / 'storage_state_execution.json')
    if (manifest['status'] != 'collected_requires_inventory_and_complete_cycle_restore_audit' or
            manifest['existing_OP_imported'] or manifest['production_recovery_allowed']):
        raise ValueError('Incomplete or incorrectly initialized C2 study')
    folder = Path(manifest['candidate_root']).resolve()
    if folder != root / 'candidate':
        raise ValueError('C2 case root escaped the study')
    arm = folder / 'native'
    execution = read(folder / 'cold_chamber_execution.json')
    if (sha256(folder / 'cold_chamber_execution.json') != manifest['candidate_execution_sha256'] or
            sha256(root / 'candidate_config.json') != manifest['candidate_config_sha256'] or
            execution['error_message'] or not execution['requested_arm_collection_pass'] or
            not execution['checkpoint_saved'] or not execution['state_restore_preflight_pass'] or
            execution['start_time_s'] != 0 or execution['stop_time_s'] != 20 or execution['cycle_count'] != 2 or
            execution['c200_state_imported'] or execution['production_recovery_allowed'] or
            execution['cases'][0]['observation_sha256'] != sha256(arm / 'observations.mat')):
        raise ValueError('Changed or incomplete C2 execution')
    c1 = read(c1_audit_path)
    if (manifest['source_cold_contract']['source_audit_sha256'] != sha256(c1_audit_path) or
            not c1['candidate_numerical_inventory_qualification'] or
            not c1['initial_coordinates']['actual_initial_coordinates_match']):
        raise ValueError('Unbound or failed C1 source')
    baseline = read(baseline_state_audit_path)
    old_folder = Path(baseline['source_root']) / 'coherent'
    compare_c2_configs(read(old_folder.parent / 'coherent_config.json'), read(root / 'candidate_config.json'))
    reference_temperatures = compare_metadata(read(old_folder / 'native/inventory_metadata.json'),
                                             read(arm / 'inventory_metadata.json'))
    old_case = baseline['cases'][1]
    if (not old_case['physical_input_hashes_verified'] or not old_case['full_mechanism_pass'] or
            sha256(old_folder / 'native/observations.mat') != old_case['source_observation_sha256']):
        raise ValueError('C2 full-density control observations changed')
    mechanism = read(arm / 'cold_mechanism_audit.json')
    if (not mechanism['mechanism_pass'] or len(mechanism['checks']) != 73 or
            not all(value is True for value in mechanism['checks'].values()) or
            sha256(arm / 'cold_mechanism_observation.mat') != mechanism['observation_sha256']):
        raise ValueError('Full original mechanism checks failed or changed')
    capture = read(arm / 'diagnostic_state_capture.json')
    restore = read(arm / 'state_restore_preflight.json')
    verify_restore_record(restore)
    if (capture['snapshot_time_s'] != 20 or
            restore['source_operating_point_sha256'] != capture['operating_point_sha256'] or
            sha256(arm / 'diagnostic_complete_operating_point.mat') != capture['operating_point_sha256'] or
            sha256(arm / 'diagnostic_state_observation.mat') != capture['history_sha256']):
        raise ValueError('Intact complete OP/history changed')
    topology = read(arm / 'tl_connectivity.json')
    assignment, domains = resolve_domains(topology)
    if domains != 2:
        raise ValueError('The two fluid domains changed')
    contracts = {row['block_path']: row for row in read(arm / 'buffer_replacement_contract.json')['buffers']}
    for contract in contracts.values():
        port_contract(contract)
    ledger = cycle_arm(arm, assignment, contracts, mass_formulation='zero_based_offset',
                       stop=20, pressure_only_density=True)
    local = [row['component_detail']['candidate_component_pass'] if 'component_detail' in row else
             row['local_chamber_gate']['mass_closure_pass'] and row['local_chamber_gate']['energy_closure_pass']
             for row in ledger['components'] if 'component_detail' in row or 'local_chamber_gate' in row]
    if len(local) != 6 or not all(local):
        raise ValueError('C2 local inventory conservation failed')
    tags = read(arm / 'compiled_inventory_tags.json')
    names = {'SMA_PumpInletConnectingPipeVolume', 'SMA_PumpOutletConnectingPipeVolume'}
    tag_rows = [dict(block_name=row['block_name'], variable_name=row['variable_name'], **decode_tags(row))
                for row in tags['node_metadata'] if row['block_name'] in names]
    if not component_inventory_preserved(tag_rows, names):
        raise ValueError('C2 chamber mass/energy lost their retained differential states')
    runtime = runtime_audit(arm, 0, 20)
    time = np.arange(20001) * .001
    budgets = {}
    with h5py.File(arm / 'observations.mat') as f, h5py.File(arm / 'configuration.mat') as cfg:
        rows = named_rows(f, f['native'])
        ramp = float(cfg['options/branch/stage_command_ramp_s'][0, 0])
        for name in ('SHEXFluidBuffer', 'SMAHotFluidBuffer', 'ColdFluidBuffer', 'HotFluidBuffer'):
            budgets[name] = partition(time, scalar_series(rows[ROOT + name, 'stored_mass'], 'kg'),
                                      scalar_series(rows[ROOT + name, 'mdot_A'], 'kg/s'), ramp)
        state = f['signals/ECC_constitutive21_output/values'][:]
        phase = np.vstack([state[a:b].mean(axis=0) for a, b in ((42, 63), (63, 84))])
        command = sum(f['signals/' + name + '/values'][:].sum(axis=0)
                      for name in ('ECC_Q_SMA_constitutive_W', 'ECC_Q_SE_constitutive_W'))
        coefficients = np.array([float(cfg['options/equilibrium/' + mass][0, 0]) *
            float(cfg['options/material/' + material + '/Delta_h_J_per_kg'][0, 0])
            for mass, material in (('m_a_kg', 'SMA'), ('m_r_kg', 'SE'))])
        latent = latent_decomposition(time, command, phase, coefficients)
        signals = {name: f['signals/' + name + '/values'][:].ravel() for name in
            ('distributed_pressure_envelope', 'distributed_target_flow_kg_s', 'stage4_target_flow_command',
             'stage4_integrator_output_gate', 'stage4_integrator_state')}
        controller = controller_contract(time, signals, read(arm / 'se_reference_contract.json'))
    balance = system_balance({name: data['BE_energy_J'] for name, data in ledger['source_ledger'].items()},
                             ledger['actual_endpoint_storage_plus_pdv_J'], latent)
    if not balance['model_equation_energy_closure_pass']:
        raise ValueError('C2 modeled heat/latent balance failed')
    summaries = [dict(buffer=name, cycle=cycle, total_mass_change_kg=sum(
        row['endpoint_mass_change_kg'] for row in stages if row['global_cycle'] == cycle))
        for name, stages in budgets.items() for cycle in (1, 2)]
    comparison = []
    for row in summaries:
        if row['cycle'] != 2:
            continue
        previous = next(old['total_mass_change_kg'] for old in baseline['cases'][1]['mass_summaries']
                        if old['buffer'] == row['buffer'] and old['cycle'] == 2)
        comparison.append(dict(buffer=row['buffer'], full_density_C2_mass_change_kg=previous,
                               pressure_only_C2_mass_change_kg=row['total_mass_change_kg']))
    files = ('observations.mat', 'configuration.mat', 'inventory_metadata.json', 'tl_connectivity.json',
             'thermal_connectivity.json', 'buffer_replacement_contract.json', 'compiled_inventory_tags.json',
             'cold_mechanism_audit.json', 'cold_mechanism_observation.mat', 'diagnostic_state_capture.json',
             'diagnostic_complete_operating_point.mat', 'diagnostic_state_observation.mat',
             'state_restore_preflight.json', 'restore_preflight_comparison.mat', 'se_reference_contract.json',
             'pressure_only_inverse_density_map_1.json', 'pressure_only_inverse_density_map_2.json')
    return dict(schema='heatdrive_ecc_storage_closure_state_qualification_audit_v1', study_root=str(root),
        source_root=str(folder), execution_commit=execution['execution_commit'],
        manifest_sha256=sha256(root / 'storage_state_execution.json'),
        source_cold_audit_sha256=sha256(c1_audit_path), baseline_state_audit_sha256=sha256(baseline_state_audit_path),
        execution_sha256=sha256(folder / 'cold_chamber_execution.json'),
        candidate_config_sha256=sha256(root / 'candidate_config.json'),
        source_operating_point_sha256=capture['operating_point_sha256'], source_history_sha256=capture['history_sha256'],
        full_mechanism_checks_passed=73, full_mechanism_pass=True, local_inventory_gates=local,
        local_inventory_pass=True, differential_inventory_states_preserved=True,
        modeled_energy_balance=balance, runtime_mechanism_subset=runtime, controller_equations=controller,
        inventory_ledger=ledger, mass_summaries=summaries, stage_mass_partitions=budgets,
        C2_full_density_vs_pressure_only_mass_comparison=comparison,
        storage_reference_temperatures_K=reference_temperatures,
        same_model_state_roundtrip_pass=True, state_groups_exact=74, signals_exact=201,
        complete_cycle_restore_verified=False, periodic_steady_state=False,
        rebuilt_cycle_test_allowed=True, diagnostic_warmup_continuation_allowed=False,
        production_recovery_allowed=False, real_fluid_EOS_claim=False, table4_reproduction_claim=False,
        outer_solve_eligible=False, input_sha256={name: sha256(arm / name) for name in files})


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--study-root', type=Path, required=True)
    parser.add_argument('--c1-audit', type=Path, required=True)
    parser.add_argument('--baseline-state-audit', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Never overwrite C2 state evidence')
    result = audit(args.study_root.resolve(), args.c1_audit.resolve(), args.baseline_state_audit.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    print(json.dumps({key: result[key] for key in ('full_mechanism_checks_passed', 'local_inventory_pass',
        'source_operating_point_sha256', 'C2_full_density_vs_pressure_only_mass_comparison',
        'modeled_energy_balance', 'rebuilt_cycle_test_allowed')}))
