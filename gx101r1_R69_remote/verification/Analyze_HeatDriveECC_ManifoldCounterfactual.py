"""Compare declared cold chamber-volume interventions, not steady performance points."""
import argparse
import copy
import json
import subprocess
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_ColdChamberCycle import (
    checked_rows, edges, read,
)
from Audit_HeatDriveECC_ColdBufferCoupled import cycle_arm, port_contract
from Audit_HeatDriveECC_DistributedPressureRuntime import audit_arm as runtime_audit
from Audit_HeatDriveECC_ColdCoordinateSmoke import compare_initial, scalar_series
from Audit_HeatDriveECC_CoupledEnergyInventory import (
    BUFFER_NAMES, CHAMBER_NAMES, ROOT, MASS_TOL_KG, latent_decomposition, system_balance,
)
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_TLDomainInventory import density_table, resolve_domains


def compare_configs(a, b):
    a, b = copy.deepcopy(a), copy.deepcopy(b)
    for config, factor in ((a, 1), (b, .1)):
        if config.pop('diagnostic_inventory_options') != {'volume_factor': factor}:
            raise ValueError('Wrong inventory intervention')
        config.pop('output_root')
        if (config['diagnostic_state_options'] != {'mode': 'off', 'command_horizon_cycles': 1}
                or config['cycle_count'] != 1 or config['duration_s'] != 10
                or config['diagnostic_arm'] != 'native' or not config['endpoint_all_arms']):
            raise ValueError('Not a state-free matched cold experiment')
    if a != b:
        raise ValueError('An undeclared configuration field changed')


def compare_metadata(a, b):
    a, b = copy.deepcopy(a), copy.deepcopy(b)
    if a['settings_tables'] != b['settings_tables']:
        raise ValueError('Fluid properties changed')
    volumes = []
    for data, factor in ((a, 1), (b, .1)):
        found = {}
        for row in data['storage_blocks']:
            if row['block_path'] in {ROOT + name for name in CHAMBER_NAMES}:
                volume = row['mask_parameters']['volume']
                if volume['unit'] != 'm^3' or volume['value'] <= 0:
                    raise ValueError('Invalid actual chamber volume')
                found[row['block_path']] = volume['value']
                volume['value'] /= factor
                # Nominals and cold extensive targets scale with the declared volume.
                # Unit, priority, pressure and temperature settings must not change.
                for key in ('stored_mass', 'stored_energy', 'stored_mass_nominal_value', 'stored_energy_nominal_value'):
                    if key in row.get('initialization_parameters', {}):
                        value = float(row['initialization_parameters'][key])/factor
                        row['initialization_parameters'][key] = value
        if len(found) != 2:
            raise ValueError('Incomplete chamber intervention')
        volumes.append(found)
    a_rows = {row['block_path']: row for row in a['storage_blocks']}
    for row in b['storage_blocks']:
        if row['block_path'] in volumes[0]:
            expected_volume=a_rows[row['block_path']]['mask_parameters']['volume']['value']
            if not np.isclose(row['mask_parameters']['volume']['value'],expected_volume,rtol=5e-14,atol=0):
                raise ValueError('Actual chamber volume differs from its declared factor')
            row['mask_parameters']['volume']['value']=expected_volume
            for key in ('stored_mass', 'stored_energy', 'stored_mass_nominal_value', 'stored_energy_nominal_value'):
                if key in row.get('initialization_parameters', {}):
                    expected = a_rows[row['block_path']]['initialization_parameters'][key]
                    if not np.isclose(row['initialization_parameters'][key], expected, rtol=5e-14, atol=0):
                        raise ValueError('Chamber cold target or numerical nominal does not scale with actual volume')
                    row['initialization_parameters'][key] = expected
    if a != b:
        raise ValueError('Storage metadata changed beyond the two declared volumes')
    return volumes


def source_equivalence(repo, baseline, candidate):
    if baseline == candidate:
        return dict(identical_producer=True, guard_only_source_changes_verified=True)
    changed=subprocess.check_output(['git','-C',str(repo),'diff','--name-only',baseline,candidate,'--','gx101r1_R69_remote']).decode().splitlines()
    changed=[path for path in changed if path.endswith(('.m','.ssc'))]
    prefix='gx101r1_R69_remote/'
    expected={prefix+path for path in (
        'Integrate_HeatDriveECC_Constitutive21_Interface.m',
        'Check_HeatDriveECC_DiagnosticManifoldGeometry.m',
        'verification/Run_HeatDriveECC_ColdChamberDiagnostic.m',
        'verification/Run_HeatDriveECC_ManifoldInventoryCounterfactual.m',
        'verification/Verify_HeatDriveECC_ManifoldInventoryDiagnostic.m')}
    if set(changed)!=expected:
        raise ValueError('Unexpected physics/assembly source changes between reused baseline and candidate')
    old_guard="""        assert(abs(options.branch.sma_pump_manifold_volume_m3 - ...
            options.branch.connecting_pipe_flow_area_m2*options.branch.connecting_pipe_length_m)<1e-15, ...
            'Diagnostic chamber geometry must remain unchanged.');"""
    new_guard="""        assert(Check_HeatDriveECC_DiagnosticManifoldGeometry(options), ...
            'Diagnostic chamber geometry must be nominal or an explicit cold-only volume intervention.');"""
    contracts=(('Integrate_HeatDriveECC_Constitutive21_Interface.m',new_guard,old_guard),
        ('verification/Run_HeatDriveECC_ColdChamberDiagnostic.m',
         '            overrides.branch.cold_manifold_inventory_volume_factor=inventory_options.volume_factor;\n',''))
    for path,new,old in contracts:
        values=[subprocess.check_output(['git','-C',str(repo),'show',commit+':'+prefix+path]).decode().replace('\r\n','\n')
                for commit in (baseline,candidate)]
        if values[1].count(new)!=1 or values[1].replace(new,old)!=values[0]:
            raise ValueError('Assembly source changed beyond the explicit geometry guard and marker')
    return dict(identical_producer=False, guard_only_source_changes_verified=True,
        baseline_producer=baseline,candidate_producer=candidate,changed_MATLAB_sources=changed,
        dynamics_and_Simscape_equations_unchanged=True,
        interpretation='The completed baseline is reused across a proven geometry-eligibility-only repair, not across arbitrary physical source changes.')


def initial_coordinates(a_folder, b_folder):
    targets = [read(folder/'native/public_inventory_targets.json') for folder in (a_folder, b_folder)]
    for target in targets:
        if target['has_private_data'] or target['source_time_s'] != 0 or len(target['targets']) != 204:
            raise ValueError('Incomplete public cold initialization contract')
    if targets[0]['source_sha256'] != targets[1]['source_sha256']:
        raise ValueError('Different cold initialization observations')
    expected_rows = [{(row['block_path'], row['state_name']): row for row in target['targets']} for target in targets]
    if len(expected_rows[0]) != 204 or set(expected_rows[0]) != set(expected_rows[1]):
        raise ValueError('Cold target coordinates changed')
    comparisons = []
    with h5py.File(a_folder/'native/observations.mat') as a, h5py.File(b_folder/'native/observations.mat') as b:
        aa, bb = checked_rows(a, 'native', 1262), checked_rows(b, 'native', 1262)
        for key, reference in expected_rows[0].items():
            candidate = expected_rows[1][key]
            factor = .1 if key[0] in {ROOT+name for name in CHAMBER_NAMES} and key[1] in ('stored_mass', 'stored_energy') else 1
            if (candidate['unit'] != reference['unit'] or candidate['priority'] != reference['priority']
                    or not compare_initial(candidate['value']/factor, reference['value'])['within_strict_comparison']):
                raise ValueError('An undeclared public cold target changed')
            current_a = scalar_series(aa[key], reference['unit'])[0]
            current_b = scalar_series(bb[key], reference['unit'])[0]
            comparisons.append(dict(path=reference['path'], unit=reference['unit'], intentional_factor=factor,
                actual_baseline_vs_target=compare_initial(current_a, reference['value']),
                actual_candidate_vs_target=compare_initial(current_b, candidate['value']),
                volume_normalized_actual_match=compare_initial(current_b/factor, current_a)))
    return dict(coordinates=comparisons,
        declared_targets_match_except_volume=True,
        actual_initial_coordinates_match=all(row['volume_normalized_actual_match']['within_strict_comparison'] for row in comparisons),
        own_actual_coordinates_match_targets=all(row[key]['within_strict_comparison']
            for row in comparisons for key in ('actual_baseline_vs_target', 'actual_candidate_vs_target')))


def mass_budget(time, buffers, chambers):
    if time.size != 10001 or set(buffers) != set(BUFFER_NAMES) or set(chambers) != set(CHAMBER_NAMES):
        raise ValueError('Incomplete cold mass coverage')
    rows = []
    for name, data in buffers.items():
        mass, flow = data['mass'], data['mass_flow']
        if (mass.shape != time.shape or flow.shape != time.shape or np.any(mass <= 0)
                or not np.isfinite(mass).all() or not np.isfinite(flow).all()):
            raise ValueError('Invalid actual buffer mass')
        transport = float(np.sum(flow[1:] * np.diff(time)))
        delta = float(mass[-1] - mass[0])
        rows.append(dict(buffer=name, mass_start_kg=float(mass[0]), mass_end_kg=float(mass[-1]),
                         full_cycle_mass_change_kg=delta, transport_BE_kg=transport,
                         mass_residual_kg=transport-delta,
                         local_mass_pass=abs(transport-delta) <= MASS_TOL_KG))
    chamber_rows = []
    for name, data in chambers.items():
        volume, mass = data['volume'], data['mass']
        if (np.max(abs(mass-volume*data['density'])) > MASS_TOL_KG
                or not np.isfinite(mass).all() or np.any(mass <= 0)):
            raise ValueError('Actual chamber mass/volume/density identity failed')
        t0, th = data['temperature'][[0, 5000]]
        p0, ph = data['pressure'][[0, 5000]]
        rho = data['density_table']([[t0, p0], [th, p0], [th, ph]])
        dm_t, dm_p = (float(volume * difference) for difference in np.diff(rho))
        dm = float(mass[5000]-mass[0])
        if abs(dm-dm_t-dm_p) > MASS_TOL_KG:
            raise ValueError('Actual density decomposition does not close')
        chamber_rows.append(dict(chamber=name, volume_m3=volume,
            phase_times_s=[0, 5, 10], temperature_K=data['temperature'][[0, 5000, -1]].tolist(),
            pressure_Pa=data['pressure'][[0, 5000, -1]].tolist(),
            mass_kg=mass[[0, 5000, -1]].tolist(), hot_half_mass_change_kg=dm,
            hot_half_T_contribution_kg=dm_t, hot_half_P_contribution_kg=dm_p,
            full_cycle_mass_change_kg=float(mass[-1]-mass[0])))
    stages = []
    for stage, (begin, end) in enumerate(zip((0, 3500, 5000, 8500), (3500, 5000, 8500, 10000)), 1):
        dm_buffer = sum(float(data['mass'][end]-data['mass'][begin]) for data in buffers.values())
        dm_chamber = sum(float(data['mass'][end]-data['mass'][begin]) for data in chambers.values())
        stages.append(dict(stage=stage, buffers_mass_change_kg=dm_buffer,
            chambers_mass_change_kg=dm_chamber, residual_kg=dm_buffer+dm_chamber,
            numerical_mass_closure_pass=abs(dm_buffer+dm_chamber) <= MASS_TOL_KG))
    return dict(buffers=rows, chambers=chamber_rows, stage_mass_exchange=stages,
        buffer_mass_equations_pass=all(row['local_mass_pass'] for row in rows),
        buffer_plus_chamber_stage_closure_pass=all(row['numerical_mass_closure_pass'] for row in stages))


def analyze_case(folder, execution):
    arm = folder/'native'
    metadata = read(arm/'inventory_metadata.json')
    assignment, count = resolve_domains(read(arm/'tl_connectivity.json'))
    if count != 2:
        raise ValueError('Changed hydraulic domains')
    contracts={row['block_path']:row for row in read(arm/'buffer_replacement_contract.json')['buffers']}
    if set(contracts)!={ROOT+name for name in BUFFER_NAMES}:
        raise ValueError('Incomplete four-buffer contract')
    for contract in contracts.values():
        port_contract(contract)
    ledger = cycle_arm(arm, assignment, contracts, mass_formulation='zero_based_offset', start=0, stop=10)
    runtime = runtime_audit(arm,0,10)
    densities = {row['block_path']: density_table(row['parameters']) for row in metadata['settings_tables']}
    blocks = {row['block_path']: row for row in metadata['storage_blocks']}
    time = np.arange(10001)*.001
    with h5py.File(arm/'observations.mat') as f, h5py.File(arm/'configuration.mat') as config:
        native = checked_rows(f, 'native', 1262)
        buffers = {name: {field: scalar_series(native[ROOT+name, state], unit)
            for field, state, unit in (('mass', 'stored_mass', 'kg'), ('mass_flow', 'mdot_A', 'kg/s'))}
            for name in BUFFER_NAMES}
        chambers = {name: {field: scalar_series(native[ROOT+name, state], unit)
            for field, state, unit in (('mass', 'stored_mass', 'kg'), ('temperature', 'T_I', 'K'),
                ('pressure', 'p_I', 'Pa'), ('density', 'rho_I', 'kg/m^3'))}
            for name in CHAMBER_NAMES}
        for name, data in chambers.items():
            data.update(volume=blocks[ROOT+name]['mask_parameters']['volume']['value'],
                        density_table=densities[assignment[ROOT+name]])
        signal = f['signals/ECC_constitutive21_output/values'][:]
        phase = np.vstack([signal[a:b].mean(axis=0) for a, b in ((42, 63), (63, 84))])
        command = sum(f['signals/'+name+'/values'][:].sum(axis=0)
                      for name in ('ECC_Q_SMA_constitutive_W', 'ECC_Q_SE_constitutive_W'))
        coefficients = np.array([float(config['options/equilibrium/'+mass][0, 0])*
            float(config['options/material/'+material+'/Delta_h_J_per_kg'][0, 0])
            for mass, material in (('m_a_kg', 'SMA'), ('m_r_kg', 'SE'))])
        latent = latent_decomposition(time, command, phase, coefficients)
    budget = mass_budget(time, buffers, chambers)
    source = {name: row['BE_energy_J'] for name, row in ledger['source_ledger'].items()}
    energy = system_balance(source, ledger['actual_endpoint_storage_plus_pdv_J'], latent)
    return dict(input_sha256={name: sha256(arm/name) for name in (
        'observations.mat', 'configuration.mat', 'inventory_metadata.json',
        'tl_connectivity.json', 'thermal_connectivity.json', 'public_inventory_targets.json')},
        execution_sha256=sha256(folder/'cold_chamber_execution.json'),
        volume_factor=execution['inventory_intervention']['volume_factor'],
        mass_budget=budget, model_energy_balance=energy, latent_decomposition=latent,
        cold_cycle_ledger=ledger, mechanism_subset_runtime=runtime, periodic_steady_state=False,
        all_mechanism_gates_evaluated=False, production_recovery_allowed=False, outer_solve_eligible=False)


def audit(study_root):
    manifest = read(study_root/'counterfactual_execution.json')
    if (manifest['status'] != 'collected_requires_physical_comparison' or manifest['state_imported']
            or manifest['production_recovery_allowed'] or len(manifest['cases']) != 2):
        raise ValueError('Incomplete or wrongly authorized study')
    names = ('baseline', 'volume_0p1')
    if [case['name'] for case in manifest['cases']] != list(names):
        raise ValueError('Changed counterfactual case order')
    configs = [read(study_root/(name+'_config.json')) for name in names]
    compare_configs(*configs)
    executions = [];folders=[]
    for name, case in zip(names, manifest['cases']):
        folder = Path(case.get('case_root',str(study_root/name))).resolve()
        if folder!=Path(configs[len(folders)]['output_root']).resolve():
            raise ValueError('Config and manifest case roots disagree')
        folders.append(folder)
        execution = read(folder/'cold_chamber_execution.json')
        if (sha256(folder/'cold_chamber_execution.json') != case['execution_sha256']
                or sha256(study_root/(name+'_config.json')) != case['config_sha256']
                or not execution['requested_arm_collection_pass'] or execution['error_message']
                or execution['start_time_s'] != 0 or execution['stop_time_s'] != 10
                or execution['c200_state_imported'] or execution['production_recovery_allowed']
                or execution['checkpoint_saved'] or len(execution['cases']) != 1
                or execution['cases'][0]['observation_sha256'] != sha256(folder/'native/observations.mat')):
            raise ValueError('Changed or incomplete independently collected case')
        executions.append(execution)
    sources=source_equivalence(Path(__file__).resolve().parents[2],*(execution['execution_commit'] for execution in executions))
    volumes = compare_metadata(*(read(folder/'native/inventory_metadata.json') for folder in folders))
    for topology in ('tl_connectivity.json', 'thermal_connectivity.json'):
        if edges(read(folders[0]/'native'/topology)) != edges(read(folders[1]/'native'/topology)):
            raise ValueError('Case physical wiring differs')
    with h5py.File(folders[0]/'native/configuration.mat') as a, h5py.File(folders[1]/'native/configuration.mat') as b:
        if set(a['commands']) != set(b['commands']) or len(a['commands']) != 5:
            raise ValueError('Changed command coverage')
        for name in a['commands']:
            for field in ('time_s', 'values'):
                if not np.array_equal(a['commands'][name][field][:], b['commands'][name][field][:]):
                    raise ValueError('Commands changed between cold cases')
    cases = [analyze_case(folder, execution) for folder, execution in zip(folders, executions)]
    initialization = initial_coordinates(*folders)
    baseline = {row['buffer']: row for row in cases[0]['mass_budget']['buffers']}
    comparisons = []
    for row in cases[1]['mass_budget']['buffers']:
        old = baseline[row['buffer']]['full_cycle_mass_change_kg']
        new = row['full_cycle_mass_change_kg']
        comparisons.append(dict(buffer=row['buffer'], baseline_delta_mass_kg=old,
            tenth_volume_delta_mass_kg=new, observed_delta_mass_ratio=new/old if abs(old)>MASS_TOL_KG else None))
    return dict(schema='heatdrive_ecc_cold_manifold_counterfactual_comparison_v1',
        analysis_source_sha256=sha256(Path(__file__)),
        analysis_commit=subprocess.check_output(['git','-C',str(Path(__file__).resolve().parents[2]),'rev-parse','HEAD']).decode().strip(),
        source_root=str(study_root), execution_producer=[execution['execution_commit'] for execution in executions],
        source_equivalence=sources,
        manifest_sha256=sha256(study_root/'counterfactual_execution.json'),
        single_declared_configuration_change=True, property_tables_identical=True,
        physical_edges_identical=True, commands_identical=True, actual_volumes_m3=volumes,
        cold_initialization_comparison=initialization,
        cases=cases, buffer_transfer_comparison=comparisons,
        simulation_executed_by_analysis=False, periodic_steady_state=False,
        all_mechanism_gates_evaluated=False, production_recovery_allowed=False,
        outer_solve_eligible=False, table4_reproduction_claim=False,
        interpretation='Cold structural intervention only. Ratios are observations, not a steady-state gate '
        'or permission to replace the reported geometry. Different chamber mass is intentional; '
        'buffer inventories and all commanded schedules must otherwise retain the common cold contract.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--study-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Never overwrite counterfactual evidence')
    result = audit(args.study_root.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    print(json.dumps({'producer': result['execution_producer'],
        'buffer_transfer_comparison': result['buffer_transfer_comparison'],
        'model_energy_pass': [case['model_energy_balance']['model_equation_energy_closure_pass'] for case in result['cases']],
        'outer_solve_eligible': False}))
