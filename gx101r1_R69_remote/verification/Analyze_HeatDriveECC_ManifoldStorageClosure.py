"""Compare real-EOS and pressure-only manifold inventory, without conflating model scopes."""
import argparse
import copy
import json
from pathlib import Path

import h5py
import numpy as np

from Analyze_HeatDriveECC_ManifoldCounterfactual import (COMMAND_NAMES, compare_commands,
    initial_coordinates, mass_budget)
from Audit_HeatDriveECC_ColdBufferCoupled import cycle_arm, port_contract
from Audit_HeatDriveECC_ColdChamberCycle import checked_rows, edges, read
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_CoupledEnergyInventory import (ROOT, BUFFER_NAMES, CHAMBER_NAMES,
    latent_decomposition, system_balance)
from Audit_HeatDriveECC_DistributedPressureRuntime import audit_arm as runtime_audit
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_TLDomainInventory import density_table, resolve_domains


def compare_configs(a, b):
    a, b = copy.deepcopy(a), copy.deepcopy(b)
    if a.pop('diagnostic_inventory_options') != {'volume_factor': 1} or \
            b.pop('diagnostic_inventory_options') != {'storage_closure': 'pressure_only_density'}:
        raise ValueError('Only the isolated nominal-volume inventory-density law may change')
    for config in (a, b):
        config.pop('output_root')
        if (config['cycle_count'] != 1 or config['duration_s'] != 10 or
                config['diagnostic_state_options'] != {'mode': 'off', 'command_horizon_cycles': 1} or
                config['diagnostic_arm'] != 'native' or not config['endpoint_all_arms']):
            raise ValueError('Require a matched state-free C1 diagnostic')
    if a != b:
        raise ValueError('A gain, geometric or thermal property input changed')


def compare_metadata(a, b):
    a, b = copy.deepcopy(a), copy.deepcopy(b)
    declarations = {}
    for block in b['storage_blocks']:
        if block['block_path'] in {ROOT + name for name in CHAMBER_NAMES}:
            parameter = block['mask_parameters'].pop('inventory_reference_temperature')
            if parameter['unit'] != 'K' or not np.isfinite(parameter['value']) or parameter['value'] <= 0:
                raise ValueError('Invalid initial inventory temperature declaration')
            declarations[block['block_path']] = parameter['value']
    if len(declarations) != 2 or a != b:
        raise ValueError('Metadata differs beyond the two declared storage reference temperatures')
    return declarations


def analyze_case(folder, pressure_only):
    arm = folder / 'native'
    metadata = read(arm / 'inventory_metadata.json')
    topology = read(arm / 'tl_connectivity.json')
    assignment, domains = resolve_domains(topology)
    if domains != 2:
        raise ValueError('Changed independent fluid domains')
    chamber_source = ('ecc_inventory_pressure_only.conservative_chamber' if pressure_only else
                      'ecc_inventory_endpoint.conservative_chamber')
    actual = {block['block_path'] for block in topology['blocks'] if block['source_file'] == chamber_source}
    if actual != {ROOT + name for name in CHAMBER_NAMES}:
        raise ValueError('Wrong actual chamber formulation')
    contracts = {row['block_path']: row for row in read(arm / 'buffer_replacement_contract.json')['buffers']}
    for contract in contracts.values():
        port_contract(contract)
    ledger = cycle_arm(arm, assignment, contracts, mass_formulation='zero_based_offset',
                       pressure_only_density=pressure_only)
    runtime = runtime_audit(arm, 0, 10)
    tables = {row['block_path']: density_table(row['parameters']) for row in metadata['settings_tables']}
    blocks = {row['block_path']: row for row in metadata['storage_blocks']}
    time = np.arange(10001) * .001
    density_scope = []
    with h5py.File(arm / 'observations.mat') as f, h5py.File(arm / 'configuration.mat') as cfg:
        rows = checked_rows(f, 'native', 1262)
        buffers = {name: {field: scalar_series(rows[ROOT + name, state], unit)
                   for field, state, unit in (('mass', 'stored_mass', 'kg'), ('mass_flow', 'mdot_A', 'kg/s'))}
                   for name in BUFFER_NAMES}
        chambers = {}
        for name in CHAMBER_NAMES:
            path = ROOT + name
            data = {field: scalar_series(rows[path, state], unit) for field, state, unit in
                    (('mass', 'stored_mass', 'kg'), ('temperature', 'T_I', 'K'),
                     ('pressure', 'p_I', 'Pa'), ('density', 'rho_I', 'kg/m^3'))}
            table = tables[assignment[path]]
            temperature = data['temperature']
            if pressure_only:
                reference = blocks[path]['mask_parameters']['inventory_reference_temperature']['value']
                if abs(temperature[0] - reference) > 1e-6:
                    raise ValueError('Inventory reference is not the measured initial temperature')
                data['density_table'] = lambda pts, ref=reference, tab=table: tab(
                    np.column_stack((np.full(len(pts), ref), np.asarray(pts)[:, 1])))
                actual_transport_rho = table(np.column_stack((temperature, data['pressure'])))
                density_scope.append(dict(chamber=name, reference_temperature_K=reference,
                    max_inventory_vs_transport_density_difference_kg_m3=float(
                        np.max(abs(data['density'] - actual_transport_rho))), real_fluid_EOS_claim=False))
            else:
                data['density_table'] = table
            data['volume'] = blocks[path]['mask_parameters']['volume']['value']
            chambers[name] = data
        state = f['signals/ECC_constitutive21_output/values'][:]
        phase = np.vstack([state[a:b].mean(axis=0) for a, b in ((42, 63), (63, 84))])
        command = sum(f['signals/' + name + '/values'][:].sum(axis=0)
                      for name in ('ECC_Q_SMA_constitutive_W', 'ECC_Q_SE_constitutive_W'))
        coefficients = np.array([float(cfg['options/equilibrium/' + mass][0, 0]) *
            float(cfg['options/material/' + material + '/Delta_h_J_per_kg'][0, 0])
            for mass, material in (('m_a_kg', 'SMA'), ('m_r_kg', 'SE'))])
        latent = latent_decomposition(time, command, phase, coefficients)
    budget = mass_budget(time, buffers, chambers)
    energy = system_balance({name: row['BE_energy_J'] for name, row in ledger['source_ledger'].items()},
                            ledger['actual_endpoint_storage_plus_pdv_J'], latent)
    return dict(storage_closure='pressure_only_density' if pressure_only else 'full_real_fluid_density',
                inventory_ledger=ledger, mass_budget=budget, model_energy_balance=energy,
                density_scope=density_scope, runtime_mechanism_subset=runtime,
                input_sha256={name: sha256(arm / name) for name in ('observations.mat', 'configuration.mat',
                    'inventory_metadata.json', 'tl_connectivity.json', 'thermal_connectivity.json',
                    'public_inventory_targets.json')}, production_recovery_allowed=False)


def audit(root):
    manifest = read(root / 'storage_closure_execution.json')
    if (manifest['status'] != 'collected_requires_formulation_specific_physical_comparison' or
            manifest['source_state_loaded'] or manifest['existing_OP_imported']):
        raise ValueError('Incomplete or incorrectly initialized storage-law experiment')
    folders = [Path(manifest[key]).resolve() for key in ('baseline_root', 'candidate_root')]
    configs = [Path(manifest['baseline_config_path']), root / 'candidate_config.json']
    for folder, path, prefix in zip(folders, configs, ('baseline', 'candidate')):
        execution = read(folder / 'cold_chamber_execution.json')
        if (sha256(path) != manifest[prefix + '_config_sha256'] or
                sha256(folder / 'cold_chamber_execution.json') != manifest[prefix + '_execution_sha256'] or
                not execution['requested_arm_collection_pass'] or execution['error_message'] or
                execution['checkpoint_saved'] or execution['c200_state_imported'] or
                execution['production_recovery_allowed'] or execution['stop_time_s'] != 10 or
                sha256(folder / 'native/observations.mat') != execution['cases'][0]['observation_sha256']):
            raise ValueError('Changed or incomplete C1 case')
    compare_configs(*(read(path) for path in configs))
    declarations = compare_metadata(*(read(folder / 'native/inventory_metadata.json') for folder in folders))
    for name in ('tl_connectivity.json', 'thermal_connectivity.json'):
        if edges(read(folders[0] / 'native' / name)) != edges(read(folders[1] / 'native' / name)):
            raise ValueError('Physical wiring changed')
    with h5py.File(folders[0] / 'native/configuration.mat') as a, \
            h5py.File(folders[1] / 'native/configuration.mat') as b:
        compare_commands(a['commands'], b['commands'])
    candidate = read(folders[1] / 'cold_chamber_execution.json')
    component = folders[1] / 'component_build/+ecc_inventory_pressure_only/conservative_chamber.ssc'
    repo = Path(__file__).resolve().parents[1]
    if (sha256(component) != candidate['endpoint_chamber_source_sha256'] or
            sha256(component) != sha256(repo / 'verification/simscape_inventory_pressure_only/'
                                      '+ecc_inventory_pressure_only/conservative_chamber.ssc')):
        raise ValueError('Actual compiled candidate source changed')
    cases = [analyze_case(folder, index == 1) for index, folder in enumerate(folders)]
    comparison = []
    for name in BUFFER_NAMES:
        values = [next(row['full_cycle_mass_change_kg'] for row in case['mass_budget']['buffers']
                       if row['buffer'] == name) for case in cases]
        comparison.append(dict(buffer=name, baseline_mass_change_kg=values[0],
                               pressure_only_mass_change_kg=values[1],
                               absolute_migration_reduction_fraction=1-abs(values[1]/values[0]) if values[0] else None))
    return dict(schema='heatdrive_ecc_manifold_storage_closure_comparison_v1', source_root=str(root),
                manifest_sha256=sha256(root / 'storage_closure_execution.json'),
                geometry_property_tables_commands_and_wiring_identical=True,
                storage_reference_temperatures_K=declarations,
                initial_coordinates=initial_coordinates(*folders, candidate_volume_factor=1),
                cases=cases, buffer_transfer_comparison=comparison,
                candidate_component_sha256=sha256(component),
                real_fluid_EOS_claim=False, paper_exact_accessory_model_claim=False,
                periodic_steady_state=False, all_mechanism_gates_evaluated=False,
                production_recovery_allowed=False, outer_solve_eligible=False,
                diagnostic_warmup_continuation_allowed=False, table4_reproduction_claim=False,
                interpretation='This isolates thermal expansion of manifold stored mass. All mass and '
                'energy fluxes remain conserved, but the density closure is an explicitly different '
                'approximation; a passing diagnostic is not a physical-device repair or steady result.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--experiment-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Never overwrite storage-law evidence')
    result = audit(args.experiment_root.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    print(json.dumps({'comparison': result['buffer_transfer_comparison'],
                      'energy_closure': [case['model_energy_balance']['model_equation_energy_closure_pass']
                                         for case in result['cases']],
                      'initial_match_count': result['initial_coordinates']['strict_coordinate_match_count'],
                      'real_fluid_EOS_claim': False, 'outer_solve_eligible': False}))
