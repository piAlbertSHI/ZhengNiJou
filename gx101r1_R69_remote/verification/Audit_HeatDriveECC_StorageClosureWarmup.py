"""Audit an unchanged-model warmup; numerical closure is not real-EOS or steady validation."""
import argparse
import copy
import json
from pathlib import Path

import h5py
import numpy as np

from Analyze_HeatDriveECC_SECommutationInventory import partition
from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_CompiledInventoryStates import decode_tags, component_inventory_preserved
from Audit_HeatDriveECC_CoupledEnergyInventory import ROOT, latent_decomposition, system_balance
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from HeatDriveECC_ObservationWindow import window_indices


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def validate_resume_config(original, resumed):
    old, new = copy.deepcopy(original), copy.deepcopy(resumed)
    if (old.pop('duration_s') != 20 or old.pop('cycle_count') != 2 or
            old.pop('diagnostic_state_options') != {'mode': 'restore_preflight', 'command_horizon_cycles': 200} or
            new.pop('duration_s') != 200 or new.pop('cycle_count') != 20):
        raise ValueError('Not the qualified C2-to-C22 fixed-horizon continuation')
    state = new.pop('diagnostic_state_options')
    if (set(state) != {'mode', 'command_horizon_cycles', 'restore_source_root', 'restore_verification_root',
                      'storage_state_audit_path', 'storage_complete_cycle_audit_path'} or
            state['mode'] != 'diagnostic_resume' or state['command_horizon_cycles'] != 200):
        raise ValueError('Incomplete typed storage recovery recipe')
    source = old.pop('output_root')
    new.pop('output_root')
    if state['restore_source_root'] != source:
        raise ValueError('Resume changed its qualified source')
    for key in ('diagnostic_inventory_options', 'diagnostic_se_reference_options'):
        options = new[key]
        if (options.pop('rebuilt_state_audit_path') != state['storage_state_audit_path'] or
                options.pop('warmup_restore_audit_path') != state['storage_complete_cycle_audit_path']):
            raise ValueError('Physical interventions consume different state authorities')
    if old != new:
        raise ValueError('A model, control, property, geometry or initialization setting changed')
    return state


def audit(root, physics_path):
    root = root.resolve()
    physics = read(physics_path)
    execution = read(root / 'cold_chamber_execution.json')
    config = read(Path(str(root) + '.resumed_config.json'))
    source = Path(execution['diagnostic_resume_contract']['source_root']).resolve()
    original = read(source.parent / 'candidate_config.json')
    state = validate_resume_config(original, config)
    c2 = read(state['storage_state_audit_path'])
    c3 = read(state['storage_complete_cycle_audit_path'])
    if (not physics['pressure_only_density_storage_declared'] or not physics['mechanism_subset_pass'] or
            physics['producer'] != execution['execution_commit'] or physics['cycles_run'] != 22 or
            physics['logged_window_s'] != [200, 220] or execution['start_time_s'] != 20 or
            execution['stop_time_s'] != 220 or not execution['checkpoint_saved'] or execution['error_message'] or
            c2['source_root'] != str(source) or not c2['full_mechanism_pass'] or
            sha256(source.parent / 'candidate_config.json') != c2['candidate_config_sha256'] or
            c3['C2_audit_sha256'] != sha256(Path(state['storage_state_audit_path'])) or
            not c3['complete_cycle_restore_verified'] or not c3['diagnostic_warmup_continuation_allowed'] or
            c3['source_root'] != str(source) or c3['restored_root'] != state['restore_verification_root']):
        raise ValueError('Wrong, incomplete or changed warmup ancestry')
    for relative, expected in c2['input_sha256'].items():
        if sha256(source / 'native' / relative) != expected:
            raise ValueError('C2 input changed: ' + relative)
    for relative, expected in c3['input_sha256'].items():
        if sha256(Path(c3['restored_root']) / relative) != expected:
            raise ValueError('C3 proof changed: ' + relative)
    for relative, expected in physics['input_sha256'].items():
        path = (root / relative).resolve()
        if not path.is_relative_to(root) or sha256(path) != expected:
            raise ValueError('Changed or escaped current physical evidence')
    tags = read(root / 'native/compiled_inventory_tags.json')
    names = {'SMA_PumpInletConnectingPipeVolume', 'SMA_PumpOutletConnectingPipeVolume'}
    tagged = [dict(block_name=row['block_name'], variable_name=row['variable_name'], **decode_tags(row))
              for row in tags['node_metadata'] if row['block_name'] in names]
    if not component_inventory_preserved(tagged, names):
        raise ValueError('Retained differential M/E states lost')
    time = 200 + np.arange(20001) * .001
    with h5py.File(root / 'native/observations.mat') as f, h5py.File(root / 'native/configuration.mat') as cfg:
        public = f['signals/ECC_constitutive21_output']
        selected = window_indices(public['time_s'][:], 200, 220)
        values = public['values'][:, selected]
        phase = np.vstack([values[a:b].mean(axis=0) for a, b in ((42, 63), (63, 84))])
        command = sum(f['signals/' + name + '/values'][:, selected].sum(axis=0)
                      for name in ('ECC_Q_SMA_constitutive_W', 'ECC_Q_SE_constitutive_W'))
        coefficients = np.array([float(cfg['options/equilibrium/' + mass][0, 0]) *
            float(cfg['options/material/' + material + '/Delta_h_J_per_kg'][0, 0])
            for mass, material in (('m_a_kg', 'SMA'), ('m_r_kg', 'SE'))])
        latent = latent_decomposition(time, command, phase, coefficients)
        rows = named_rows(f, f['native'])
        ramp = float(cfg['options/branch/stage_command_ramp_s'][0, 0])
        budgets = {}
        for name in ('SHEXFluidBuffer', 'SMAHotFluidBuffer', 'ColdFluidBuffer', 'HotFluidBuffer'):
            row = rows[ROOT + name, 'stored_mass']
            indices = window_indices(row['time_s'][:], 200, 220)
            budgets[name] = partition(time, scalar_series(row, 'kg')[indices],
                scalar_series(rows[ROOT + name, 'mdot_A'], 'kg/s')[indices], ramp)
    ledger = physics['arms'][0]['inventory_ledger']
    balance = system_balance({name: data['BE_energy_J'] for name, data in ledger['source_ledger'].items()},
                             ledger['actual_endpoint_storage_plus_pdv_J'], latent)
    if not balance['model_equation_energy_closure_pass']:
        raise ValueError('Modeled heat plus latent inventory closure failed')
    summaries = [dict(buffer=name, global_cycle=cycle, net_mass_change_kg=sum(
        row['endpoint_mass_change_kg'] for row in stages if row['global_cycle'] == cycle))
        for name, stages in budgets.items() for cycle in (21, 22)]
    capture = read(root / 'native/diagnostic_state_capture.json')
    return dict(schema='heatdrive_ecc_storage_closure_warmup_science_v1', source_root=str(root), total_cycles=22,
        producer=execution['execution_commit'], actual_simulation_window_s=[20, 220], native_ledger_window_s=[200, 220],
        all_input_hashes_verified=True, original_model_and_control_config_unchanged=True,
        differential_inventory_states_preserved=True, modeled_energy_balance=balance,
        mass_summaries=summaries, stage_mass_partitions=budgets,
        source_operating_point_sha256=capture['operating_point_sha256'], source_history_sha256=capture['history_sha256'],
        source_configuration_sha256=sha256(Path(str(root) + '.resumed_config.json')),
        source_state_edited=False, failed_state_propagated=False, ten_cycle_native_inventory_steady_verified=False,
        physical_density_approximation='M=V*rho(T_initial,p), U=M*u(T,p); transport density unchanged',
        real_fluid_EOS_claim=False, production_recovery_allowed=False, outer_solve_eligible=False,
        table4_reproduction_claim=False, input_sha256={'physics_audit': sha256(physics_path),
            'C2_audit': sha256(Path(state['storage_state_audit_path'])),
            'C3_audit': sha256(Path(state['storage_complete_cycle_audit_path']))})


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--experiment-root', type=Path, required=True)
    parser.add_argument('--physics-audit', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Never overwrite warmup scientific evidence')
    result = audit(args.experiment_root, args.physics_audit)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    print(json.dumps({key: result[key] for key in ('total_cycles', 'modeled_energy_balance', 'mass_summaries',
        'source_operating_point_sha256', 'source_history_sha256')}, indent=2))
