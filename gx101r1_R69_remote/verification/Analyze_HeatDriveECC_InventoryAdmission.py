"""Attribute native inventory migration without inventing a periodicity tolerance."""
import argparse
import json
import math
from pathlib import Path
import shutil

import h5py
import numpy as np

from Analyze_HeatDriveECC_CoolingBoundaryReconciliation import aligned_window_indices
from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdBufferCoupled import cycle_arm, port_contract
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_CoupledEnergyInventory import (
    BUFFER_NAMES, ROOT, buffer_cycle_rows, latent_decomposition, system_balance)
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field
from Audit_HeatDriveECC_TLDomainInventory import resolve_domains
from Close_HeatDriveECC_SplitObservation import read, validate_gate
from HeatDriveECC_ObservationWindow import window_indices
from Verify_HeatDriveECC_ObservationPacket import validate_manifest


def signed_trend(values):
    values = np.asarray(values, dtype=float)
    if values.shape != (10,) or not np.isfinite(values).all():
        raise ValueError('Require ten actual consecutive cycle increments')
    magnitude = np.abs(values)
    return dict(first=float(values[0]), last=float(values[-1]),
        same_nonzero_sign=bool(np.all(values > 0) or np.all(values < 0)),
        magnitude_monotonically_decreasing=bool(np.all(np.diff(magnitude) <= 0)),
        magnitude_monotonically_increasing=bool(np.all(np.diff(magnitude) >= 0)),
        last_to_first_magnitude_ratio=float(magnitude[-1]/magnitude[0]) if magnitude[0] else None,
        asymptotic_limit_or_error_bound_claim=False)


def storage_scales(components, latent_J, duration_s, mass_kg, scp_tolerance):
    if (not components or duration_s not in (10, 20) or not all(math.isfinite(v) for v in
            (latent_J, mass_kg, scp_tolerance)) or mass_kg <= 0 or scp_tolerance <= 0):
        raise ValueError('Require a measured 10/20 s window and positive active mass/metric precision')
    names = [r['block_path'] for r in components]
    if len(names) != len(set(names)):
        raise ValueError('Duplicate inventory component')
    increments = np.asarray([r['energy_endpoint_change_J']+r.get('pressure_volume_work_J', 0)
                             for r in components], dtype=float)
    if not np.isfinite(increments).all():
        raise ValueError('Nonfinite measured inventory change')
    tolerance_W = 1000*mass_kg*scp_tolerance
    total = float(increments.sum()+latent_J)
    absolute = float(np.abs(increments).sum()+abs(latent_J))
    return dict(native_storage_plus_pdv_J=float(increments.sum()), latent_storage_J=latent_J,
        modeled_storage_including_latent_plus_pdv_J=total,
        modeled_storage_mean_rate_W=total/duration_s,
        sum_absolute_component_storage_rate_W=absolute/duration_s,
        declared_SCP_tolerance_W_per_g=scp_tolerance, active_SE_mass_kg=mass_kg,
        equivalent_existing_metric_tolerance_W=tolerance_W,
        net_storage_scale_over_metric_tolerance=abs(total/duration_s)/tolerance_W,
        absolute_storage_scale_over_metric_tolerance=absolute/duration_s/tolerance_W,
        rates_are_diagnostics_not_Eq10_corrections=True,
        global_inventory_change_is_not_an_Eq10_error_bound=True,
        new_inventory_threshold_imposed=False)


def grouped_components(components):
    result = {}
    for row in components:
        group = result.setdefault(row['mask_type'], dict(count=0, energy_change_J=0., pdv_J=0.))
        group['count'] += 1
        group['energy_change_J'] += row['energy_endpoint_change_J']
        group['pdv_J'] += row.get('pressure_volume_work_J', 0.)
    return result


def return_drift(time, values):
    time, values = np.asarray(time).ravel(), np.asarray(values)
    if values.shape != (1, 20001) or time.size != 20001 or not np.isfinite(values).all():
        raise ValueError('Require one scalar memory on two actual complete cycles')
    window_indices(time, float(time[0]), float(time[-1]))
    difference = values[0, 10000:]-values[0, :10001]
    endpoints = values[0, ::10000]
    return dict(cycle_endpoints=endpoints.tolist(), cycle_increments=np.diff(endpoints).tolist(),
        same_phase_maximum=float(np.abs(difference).max()),
        same_phase_rms=float(np.sqrt(np.mean(difference**2))), tolerance_imposed=False)


def analyze(qualification, measured, output):
    snapshot = output.with_suffix('.producer.py')
    if output.exists() or snapshot.exists():
        raise FileExistsError('Never overwrite admission evidence')
    q, d = read(qualification), read(measured)
    if (q['schema'] != 'heatdrive_ecc_runtime_Tc_candidate_endpoint_v1' or
            not q['all_original_packet_mechanism_flow_phase_energy_gates_pass'] or
            not q['all_four_memories_bitwise_preserved'] or q['source_state_edited'] or
            q['production_recovery_allowed'] or q['current_window_s'] != d['window_s'] or
            d['sample_count'] != 100001 or not d['fixed_Tc_candidate'] or
            q['temperature_K'] != d['candidate_Tc_K']):
        raise ValueError('Changed or incompatible complete diagnostic endpoint')
    for row in q['files']:
        if sha256(Path(row['path'])) != row['sha256']:
            raise ValueError('Changed qualification dependency: '+row['path'])
    if not any(Path(r['path']).resolve() == measured.resolve() and r['sha256'] == sha256(measured)
               for r in q['files']):
        raise ValueError('Measured window is not the sealed current window')
    if sha256(Path(q['operating_point_path'])) != q['operating_point_sha256']:
        raise ValueError('Changed complete Operating Point')
    start, stop = d['window_s']
    if stop-start != 100 or len(d['packets']) != 5:
        raise ValueError('Require ten complete native cycles')
    target = q['current_target_window_stability']
    tolerance = target['SCP_limit_W_per_g']
    packets, buffer_rows, packet_inputs, memories = [], [], [], []
    for k, p in enumerate(d['packets']):
        packet = Path(p['packet_root']); arm = packet/'native'
        m, gate = read(packet/'packet_manifest.json'), read(packet/'packet_gate.json')
        begin, end = validate_manifest(m); validate_gate(gate)
        if ([begin, end] != [start+20*k, start+20*(k+1)] or m['prescribed_Tc_K'] != q['temperature_K'] or
                gate['input_sha256']['manifest'] != sha256(packet/'packet_manifest.json')):
            raise ValueError('Incomplete or changed current packet')
        domains, count = resolve_domains(read(arm/'tl_connectivity.json'))
        if count != 2:
            raise ValueError('Fluid domain count changed')
        contracts = {r['block_path']: r for r in read(arm/'buffer_replacement_contract.json')['buffers']}
        for c in contracts.values():
            port_contract(c)
        with h5py.File(arm/'observations.mat') as f, h5py.File(arm/'configuration.mat') as cfg:
            state = f['signals/ECC_constitutive21_output']
            indices = window_indices(state['time_s'][:], begin, end)
            time = state['time_s'][:].ravel()[indices]
            native = named_rows(f, f['native']); arrays = {}
            for name in BUFFER_NAMES:
                def get(variable, unit):
                    r = native[ROOT+name, variable]
                    selected = aligned_window_indices(r['time_s'][:], time)
                    return scalar_series(r, unit)[selected]
                arrays[name] = dict(mass=get('stored_mass', 'kg'), energy=get('stored_energy', 'J'),
                    temperature=get('T_I', 'K'), mass_flow=get('mdot_A', 'kg/s'))
            buffer_rows.extend(buffer_cycle_rows(time, arrays))
            values = state['values'][:, indices]
            phase = np.vstack([values[a:b].mean(axis=0) for a, b in ((42, 63), (63, 84))])
            commands = np.zeros(time.size)
            for name in ('ECC_Q_SMA_constitutive_W', 'ECC_Q_SE_constitutive_W'):
                r = f['signals/'+name]
                selected = aligned_window_indices(r['time_s'][:], time)
                commands += r['values'][:, selected].sum(axis=0)
            coefficients = np.array([float(cfg['options/equilibrium/'+mass][0, 0])*
                float(cfg['options/material/'+material+'/Delta_h_J_per_kg'][0, 0])
                for mass, material in (('m_a_kg', 'SMA'), ('m_r_kg', 'SE'))])
        with h5py.File(packet/'observed_states.mat') as states:
            rows = named_rows(states, states['observation/states'])
            selected_memories = {k: r for k, r in rows.items() if k[0].endswith((
                '/SMAPressurePI_Integrator', '/SEStage2PressurePI_Integrator', '/SEStage4PressurePI_Integrator'))}
            if len(selected_memories) != 3:
                raise ValueError('Missing independent-route PI memories')
            for key, row in selected_memories.items():
                selected = aligned_window_indices(row['time_s'][:], time)
                memories.append(dict(block_path=key[0], state_name=key[1], window_s=[begin, end],
                    unit=text_field(row['unit']) if 'unit' in row else 'not_exported',
                    **return_drift(time, row['values'][:, selected])))
        # The established ledger requires the intact two-cycle native packet.
        # Per-cycle mass attribution uses its separate exact endpoint/flux partition.
        ledger = cycle_arm(arm, domains, contracts, start=begin, stop=end,
            mass_formulation='zero_based_offset', pressure_only_density=True)
        latent = latent_decomposition(time, commands, phase, coefficients)
        balance = system_balance({key: value['BE_energy_J'] for key, value in ledger['source_ledger'].items()},
            ledger['actual_endpoint_storage_plus_pdv_J'], latent)
        if (ledger['storage_count'] != 119 or ledger['source_count'] != 49 or
                not balance['model_equation_energy_closure_pass']):
            raise ValueError('Original two-cycle modeled inventory equation did not close')
        scales = storage_scales(ledger['components'], latent['latent_storage_change_J'], end-begin,
            d['active_SE_mass_kg'], tolerance)
        packets.append(dict(stop_cycle=int(end/10), window_s=[begin, end], energy_balance=balance,
            storage_scales=scales, groups=grouped_components(ledger['components']),
            source_ledger=ledger['source_ledger'], components=[dict(block_path=r['block_path'],
                mask_type=r['mask_type'], energy_endpoint_change_J=r['energy_endpoint_change_J'],
                pressure_volume_work_J=r.get('pressure_volume_work_J', 0.)) for r in ledger['components']]))
        packet_inputs.append(dict(path=str(packet/'packet_manifest.json'), sha256=sha256(packet/'packet_manifest.json')))
    trends = {}
    for name in BUFFER_NAMES:
        rows = [r for r in buffer_rows if r['buffer'] == name]
        if [r['global_cycle'] for r in rows] != list(range(int(start/10)+1, int(stop/10)+1)):
            raise ValueError('Buffer cycles are not the current consecutive window')
        trends[name] = dict(mass=signed_trend([r['mass_change_kg'] for r in rows]),
            energy=signed_trend([r['energy_change_J'] for r in rows]),
            largest_mass_equation_residual_kg=max(abs(r['mass_equation_residual_kg']) for r in rows),
            mean_stage_transport_kg={str(stage): float(np.mean([r['stages'][stage-1]['transported_mass_BE_kg'] for r in rows]))
                for stage in (1, 2, 3, 4)})
    record = dict(schema='heatdrive_ecc_native_inventory_admission_review_v1', window_s=d['window_s'],
        temperature_K=q['temperature_K'], qualification_sha256=sha256(qualification),
        measured_window_sha256=sha256(measured), complete_OP_sha256=q['operating_point_sha256'],
        original_public_thermal_periodic_pass=q['original_public_thermal_periodic_pass'],
        existing_target_precision_pass=target['precision_pass'], all_five_native_packet_energy_equations_pass=True,
        buffer_trends=trends, buffer_cycles=buffer_rows, packet_ledgers=packets,
        PI_memory_return_drift=memories,
        native_temperature_summary=dict(count=len(d['native_temperatures']),
            combined_same_phase_RMS_K=math.sqrt(sum(r['same_phase_rms']**2 for r in d['native_temperatures'])/
                                               len(d['native_temperatures'])),
            all_119_thermal_return_tolerances_newly_imposed=False),
        cooling_boundary_reconciliation=d['cooling_boundary_reconciliation'],
        complete_internal_state_periodicity_verified=False, asymptotic_error_bound_established=False,
        full_goal_outer_root_admission_established=False, production_recovery_allowed=False,
        physical_tolerances_changed=False, scientific_gate_failure=False,
        decision='Keep the intact diagnostic. Mass increments do not contract in this observed window; neither local conservation nor thermal convergence proves full-state periodicity.',
        recommended_next_action='Measure a disjoint same-Tc ten-cycle window against the existing metric precision, while recording native/PI return drift. Do not equate global storage rate to Eq10 error, fit a heat correction, demand bitwise cross-cycle equality, or assume a permanent controller defect from this finite record.',
        simulation_executed=False, operating_point_loaded=False, source_state_edited=False,
        packet_inputs=packet_inputs, producer_source_sha256=sha256(Path(__file__)), producer_snapshot=str(snapshot))
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(__file__, snapshot)
    if sha256(snapshot) != record['producer_source_sha256']:
        raise ValueError('Producer snapshot changed')
    output.write_text(json.dumps(record, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    return dict(output=str(output), window_s=d['window_s'], buffer_trends=trends,
        maximum_absolute_BE_residual_J=max(abs(r['energy_balance']['external_heat_minus_total_storage_J']) for r in packets),
        final_two_cycle_storage_scales=packets[-1]['storage_scales'], full_goal_outer_root_admission_established=False)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('qualification', 'measured', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    print(json.dumps(analyze(**vars(parser.parse_args())), indent=2))
