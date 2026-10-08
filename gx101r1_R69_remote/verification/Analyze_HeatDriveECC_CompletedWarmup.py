"""Evaluate completed warmup physics and all logged storage drift, not recovery."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Analyze_HeatDriveECC_WarmupOutcome import analyze, paired_drift
from Audit_HeatDriveECC_ColdBufferCoupled import cycle_arm, BUFFERS, CHAMBERS, port_contract
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_CompletedColdArms import INITIAL_SHA
from Audit_HeatDriveECC_ColdPumpPressureProbes import normalized_rows
from Audit_HeatDriveECC_DistributedPressureRuntime import audit_arm, read_json
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_TLDomainInventory import resolve_domains
from HeatDriveECC_DiagnosticAnalysisScope import diagnostic_arms
from HeatDriveECC_ObservationWindow import window_indices


def storage_drifts(handle, start, stop):
    rows = normalized_rows(handle, 'native', start, stop, True)
    if len(rows) != 1262:
        raise ValueError('Require all 1262 original inventory observations')
    records = []
    units = {'T_I': 'K', 'T': 'K', 'p_I': 'Pa', 'stored_mass': 'kg',
             'mass_offset': 'kg', 'stored_energy': 'J'}
    for (block, state), row in rows.items():
        if state in units:
            unit = units[state]
            values = scalar_series(row, unit).reshape(1, -1)
            records.append(dict(block_path=block, state=state, unit=unit,
                                **paired_drift(values)))
    temperatures = [r for r in records if r['unit'] == 'K']
    if len(temperatures) != 119 or len({r['block_path'] for r in temperatures}) != 119:
        raise ValueError('Incomplete 119-storage temperature coverage')
    return dict(storage_temperature_count=119, records=records,
                worst_temperature_endpoint_K=max(r['endpoint_max'] for r in temperatures),
                worst_temperature_same_phase_K=max(r['same_phase_max'] for r in temperatures),
                complete_differential_state_coverage_verified=False)


def analyze_completed(root):
    execution = read_json(root/'cold_chamber_execution.json')
    stop = float(execution['stop_time_s'])
    start = stop-20
    arms_requested=diagnostic_arms(root,execution)
    if ((not execution['collection_pass'] and len(arms_requested)!=1) or execution['cycle_count'] < 2
            or execution['c200_state_imported']):
        raise ValueError('Require completed independent non-recovery warmup')
    summary = analyze(root)
    initialization = {}
    for result in summary['arms']:
        name = result['arm']
        folder = root/name
        completion = read_json(folder/'arm_completion.json')
        if completion['execution_commit'] != execution['execution_commit']:
            raise ValueError('Arm producer differs from completed package')
        targets = read_json(folder/'public_inventory_targets.json')
        allowed_sources = {INITIAL_SHA} if name == 'native' else {
            INITIAL_SHA, sha256(root/'native/observations.mat')}
        if (targets['source_sha256'] not in allowed_sources or targets['source_time_s'] != 0
                or len(targets['targets']) != 204):
            raise ValueError('Warmup has an unauthorized or incomplete initialization source')
        initialization[name] = dict(source_sha256=targets['source_sha256'], source_time_s=0)
        assignment, domains = resolve_domains(read_json(folder/'tl_connectivity.json'))
        if domains != 2:
            raise ValueError('Require original two liquid domains')
        contracts = {r['block_path']: r for r in
                     read_json(folder/'buffer_replacement_contract.json')['buffers']}
        if set(contracts) != BUFFERS:
            raise ValueError('Incomplete buffer contracts')
        for contract in contracts.values():
            port_contract(contract)
        runtime = audit_arm(folder, start, stop)
        ledger = cycle_arm(folder, assignment, contracts,
                           mass_formulation='zero_based_offset', start=start, stop=stop)
        local = []
        for row in ledger['components']:
            if row['mask_type'] == 'Conservative Buffer (TL)':
                local.append(row['component_detail']['candidate_component_pass'])
            elif row['block_path'] in CHAMBERS:
                gate = row['local_chamber_gate']
                local.append(gate['mass_closure_pass'] and gate['energy_closure_pass'])
        local_pass = len(local) == 6 and all(local)
        with h5py.File(folder/'observations.mat') as handle:
            drift = storage_drifts(handle, start, stop)
            memory = {}
            for key in ('stage4_integrator_state', 'stage4_integrator_input'):
                row = handle['signals/'+key]
                selected=window_indices(row['time_s'][:].reshape(-1),start,stop)
                values = row['values'][:, selected]
                memory[key] = paired_drift(values)
        boundary = runtime['pressure_boundary']
        gates = dict(distributed_equations=runtime['distributed_controller_runtime_pass'],
                     selected_flows=runtime['selected_flow_gates_pass'],
                     production_flow_windows=all(r['tracking_pass'] for r in result['production_window_flows']),
                     pressure_range=boundary['pressure_range_gate'],
                     ideal_source_ports=boundary['hydraulic_diagnostic_gate'],
                     local_inventory=local_pass, phase_bounds=runtime['phase_bounds_pass'],
                     selected_solid_energy=runtime['solid_energy_pass'])
        result.update(mechanism_subset_gates=gates, mechanism_subset_pass=all(gates.values()),
                      runtime=runtime, inventory_ledger=ledger,
                      storage_drift=drift, observed_controller_memory_drift=memory,
                      physical_simulation_completed=True,
                      full_state_periodicity_evaluated=False)
        summary['input_sha256'].update({str((folder/file).relative_to(root)): sha256(folder/file)
            for file in ('arm_completion.json', 'inventory_metadata.json', 'tl_connectivity.json',
                         'thermal_connectivity.json', 'buffer_replacement_contract.json',
                         'distributed_pressure_ff_contract.json', 'public_inventory_targets.json')})
    summary.update(schema='heatdrive_ecc_completed_warmup_physics_v1',
                   analysis_scope='state_qualified_diagnostic_segment' if len(arms_requested)==1 else 'independent_cold_warmup',
                   actual_segment_start_s=execution['start_time_s'],
                   producer=execution['execution_commit'], logged_window_s=[start, stop],
                   mechanism_subset_pass=all(r['mechanism_subset_pass'] for r in summary['arms']),
                   no_failed_trajectory_propagated=True,
                   initialization_source_chains=initialization,
                   full_device_first_law_verified=False,
                   incomplete_state_coverage_is_not_a_mechanism_failure=True,
                   next_action='Establish diagnostic full-state capture, then cold periodic convergence; no parameter repair solely for unsteady drift',
                   checkpoint_available=bool(execution['checkpoint_saved']),
                   checkpoint_is_diagnostic_candidate_only=bool(execution['checkpoint_saved']))
    summary['input_sha256']['cold_chamber_execution.json'] = sha256(root/'cold_chamber_execution.json')
    return summary


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--experiment-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Never overwrite an audit')
    result = analyze_completed(args.experiment_root.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    print(json.dumps(dict(mechanism_subset_pass=result['mechanism_subset_pass'], arms=[
        dict(arm=r['arm'], gates=r['mechanism_subset_gates'],
             storage_endpoint_K=r['storage_drift']['worst_temperature_endpoint_K'],
             storage_same_phase_K=r['storage_drift']['worst_temperature_same_phase_K'])
        for r in result['arms']]), indent=2))
