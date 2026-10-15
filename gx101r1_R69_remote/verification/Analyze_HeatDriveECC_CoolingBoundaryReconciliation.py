"""Reconcile Eq.10 and CHEX heat on measured windows, without granting steady authority."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from HeatDriveECC_ObservationWindow import window_indices


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def integrals(time, values):
    time, values = np.asarray(time), np.asarray(values)
    if (time.ndim != 1 or time.size < 2 or values.shape != time.shape or
            not np.isfinite([time, values]).all() or np.any(np.diff(time) <= 0)):
        raise ValueError('Require finite shared measured samples')
    return dict(BE_J=float(np.sum(values[1:]*np.diff(time))),
                trapz_J=float(np.trapezoid(values, time)))


def stage_ids(time, horizon_cycles, starts, ends):
    time = np.asarray(time)
    starts, ends = np.asarray(starts), np.asarray(ends)
    if (time.ndim != 1 or not np.isfinite(time).all() or starts.shape != (4,) or ends.shape != (4,) or
            not np.array_equal(starts, [0, 3.5, 5, 8.5]) or not np.array_equal(ends, [3.5, 5, 8.5, 10]) or
            horizon_cycles < 1 or horizon_cycles != int(horizon_cycles)):
        raise ValueError('Require the declared unchanged four-stage schedule')
    cycle = np.clip(np.floor(time/10)+1, 1, horizon_cycles)
    local = time-(cycle-1)*10
    local[time >= horizon_cycles*10-10*np.spacing(max(horizon_cycles*10, 1))] = 10
    stage = np.full(time.shape, 4)
    for index in range(4):
        mask = (local >= starts[index]) & (local < ends[index] if index < 3 else local <= ends[index]+np.spacing(10.))
        stage[mask] = index+1
    return stage


def aligned_window_indices(clock, time):
    clock, time = np.asarray(clock).ravel(), np.asarray(time).ravel()
    indices = window_indices(clock, float(time[0]), float(time[-1]))
    allowance = 16*np.spacing(max(abs(time[0]), abs(time[-1]), 1.))
    if indices.size != time.size or np.any(abs(clock[indices]-time) > allowance):
        raise ValueError('Samples do not share the same absolute millisecond grid')
    return indices


def summed_channels(values, clock_size):
    values = np.asarray(values)
    if values.ndim != 2 or values.shape[1] != clock_size or not np.isfinite(values).all():
        raise ValueError('Require channel-by-time measurements, not a flattened or transposed signal')
    return values.sum(axis=0)


def reconciliation(time, active, eq10, port_net_in, heat_into_pipe, sensor, delta_storage):
    active = np.asarray(active)
    arrays = [np.asarray(v) for v in (eq10, port_net_in, heat_into_pipe, sensor)]
    if active.dtype != bool or any(v.shape != active.shape for v in arrays) or not np.isfinite(delta_storage):
        raise ValueError('Require a shared Boolean activity mask and finite measured storage')
    eq10, port_net_in, heat_into_pipe, sensor = arrays
    energies = {name: integrals(time, value) for name, value in dict(
        eq10=eq10, native_export_stage4=-port_net_in*active,
        native_export_inactive=-port_net_in*~active, native_export_all=-port_net_in,
        heat_into_pipe=heat_into_pipe, sensor=sensor).items()}
    duration = float(time[-1]-time[0])
    result = {}
    for quadrature in ('BE_J', 'trapz_J'):
        e = {name: row[quadrature] for name, row in energies.items()}
        residual = -e['native_export_all']+e['heat_into_pipe']-delta_storage
        terms = dict(stage4_metric_minus_native_port_export_J=e['eq10']-e['native_export_stage4'],
                     omitted_inactive_native_export_J=-e['native_export_inactive'],
                     negative_pipe_storage_change_J=-float(delta_storage),
                     pipe_heat_minus_sensor_J=e['heat_into_pipe']-e['sensor'])
        difference = e['eq10']-e['sensor']
        # The independently evaluated residual remains visible, not fitted as a heat correction.
        result[quadrature] = dict(energies_J=e, difference_J=difference, difference_mean_W=difference/duration,
            resolved_terms_J=terms, independently_measured_pipe_residual_J=residual,
            unexplained_after_physical_terms_J=difference-sum(terms.values()),
            bookkeeping_identity_error_J=difference-sum(terms.values())+residual)
    return dict(window_s=[float(time[0]), float(time[-1])], pipe_storage_change_J=float(delta_storage),
        quadratures=result, solver_equation_quadrature='BE_J', performance_quadrature='trapz_J',
        residual_is_not_a_fitted_heat_correction=True, inactive_transport_is_retained=True)


def flow_metric_split(time, active, public_flow, native_flow, cp_delta_temperature, native_port_net_in):
    active = np.asarray(active)
    values = [np.asarray(v) for v in (public_flow, native_flow, cp_delta_temperature, native_port_net_in)]
    if active.dtype != bool or not active.any() or any(v.shape != active.shape for v in values):
        raise ValueError('Metric and native flow must share the measured grid')
    public_flow, native_flow, cp_delta_temperature, native_port_net_in = values
    public_metric = abs(public_flow)*cp_delta_temperature*active
    native_metric = abs(native_flow)*cp_delta_temperature*active
    return dict(
        upstream_flow_location_difference=integrals(time, public_metric-native_metric),
        remaining_same_native_flow_metric_minus_port_export=integrals(time, native_metric+native_port_net_in*active),
        stage4_public_flow_mean_kg_s=float(np.mean(abs(public_flow[active]))),
        stage4_native_flow_mean_kg_s=float(np.mean(abs(native_flow[active]))),
        remaining_term_is_not_assigned_to_cp_or_conduction_without_further_evidence=True)


def analyze(contract_path, physics_path, science_path, saved_performance_path):
    contract, physics, science = map(read, (contract_path, physics_path, science_path))
    root = (Path(contract['execution_repo'])/contract['source_root_relative']).resolve()
    raw = root/'native/observations.mat'
    cfg = root/'native/configuration.mat'
    saved_performance = read(saved_performance_path)
    execution = read(root/'cold_chamber_execution.json')
    if (science['input_sha256']['physics_audit'] != sha256(physics_path) or
            not science['modeled_energy_balance']['model_equation_energy_closure_pass'] or
            physics['producer'] != execution['execution_commit'] or not physics['mechanism_subset_pass'] or
            not execution['requested_arm_collection_pass'] or execution['error_message']):
        raise ValueError('Require the current complete mechanism/energy-qualified diagnostic')
    for relative, expected in physics['input_sha256'].items():
        path = (root/relative.replace('\\', '/')).resolve()
        if not path.is_relative_to(root) or sha256(path) != expected:
            raise ValueError('Changed or escaped current evidence: '+relative)
    for kind in ('operating_point', 'history'):
        if sha256(root/contract[kind+'_relative']) != contract[kind+'_sha256']:
            raise ValueError('Current complete state changed: '+kind)
    if (Path(saved_performance['source_root']).resolve() != root or saved_performance['simulation_executed'] or
            saved_performance['window_cycles'] != 10 or
            saved_performance['input_sha256']['observation'] != sha256(raw) or
            saved_performance['input_sha256']['configuration'] != sha256(cfg)):
        raise ValueError('Original MATLAB statistics do not bind the same measured source')
    ledger = physics['arms'][0]['inventory_ledger']
    pipe_rows = [row for row in ledger['components'] if row['block_path'].endswith('/ColdSinkPipe')]
    if ledger['storage_count'] != 119 or ledger['source_count'] != 49 or len(pipe_rows) != 1:
        raise ValueError('Incomplete or ambiguous actual control-volume inventory')
    pipe = pipe_rows[0]
    stop = execution['stop_time_s']
    start = stop-20
    if physics['logged_window_s'] != [start, stop]:
        raise ValueError('Native ledger window changed')
    clock_difference_max_s = 0.
    with h5py.File(raw) as f, h5py.File(cfg) as config:
        options = config['options']
        scalar = lambda key: float(options[key][0, 0])
        horizon = scalar('cycle_count')
        cp = scalar('system/cp_fluid_J_per_kgK')
        mass = scalar('equilibrium/m_r_kg')
        if cp <= 0 or mass <= 0:
            raise ValueError('Invalid declared fluid cp or active SE mass')
        starts = options['schedule/stage_start_s'][:].ravel()
        ends = options['schedule/stage_end_s'][:].ravel()

        def sampled(row, time, unit=None):
            nonlocal clock_difference_max_s
            clock = row['time_s'][:].ravel()
            indices = aligned_window_indices(clock, time)
            clock_difference_max_s = max(clock_difference_max_s, float(abs(clock[indices]-time).max()))
            if unit:
                values = scalar_series(row, unit)[indices]
            else:
                # Select the supported window before summing: unrelated history may contain NaNs.
                values = summed_channels(row['values'][:, indices], len(indices))
            if not np.isfinite(values).all():
                raise ValueError('Missing measured support in requested window')
            return values

        def public_metrics(begin, end):
            clock = f['signals/SMA_Tx21_internal/time_s'][:].ravel()
            time = clock[window_indices(clock, begin, end)]
            signal = lambda name: sampled(f['signals/'+name], time)
            stage = stage_ids(time, horizon, starts, ends)
            eq10 = abs(signal('mass_flow_v4_hot_inlet_kgps'))*(stage == 4)*cp*(
                signal('cold_hx_inlet_fluid_temp_out')-signal('cold_hx_outlet_fluid_temp_out'))
            sensor = signal('Qdot_cold_sink_mass_to_hx_pipe_W')
            mean = lambda value: integrals(time, value)['trapz_J']/(end-begin)
            source = mean(np.maximum(signal('shex_source_heat_flow_W'), 0))
            performance = dict(window_s=[begin, end], samples=int(time.size), window_cycles=(end-begin)/10,
                quadrature='trapz_both_endpoints', temperature_lift_eq9_K=mean(
                    signal('hot_hx_inlet_fluid_temp_out')-signal('cold_hx_inlet_fluid_temp_out')),
                cooling_power_eq10_W=mean(eq10), SCP_W_per_g=mean(eq10)/(1000*mass),
                CHEX_sensor_mean_W=mean(sensor), positive_SHEX_source_mean_W=source,
                heat_driven_COP=mean(eq10)/source if source > 0 else None,
                active_SE_mass_kg=mass, declared_fluid_cp_J_kgK=cp)
            return time, stage, eq10, sensor, performance

        time, stage, eq10, sensor, two = public_metrics(start, stop)
        _, _, _, _, ten = public_metrics(stop-100, stop)
        native = named_rows(f, f['native'])
        get = lambda variable, unit='W': sampled(native[pipe['block_path'], variable], time, unit)
        port_net = get('Phi_A')+get('Phi_B')
        decomposition = reconciliation(time, stage == 4, eq10, port_net, get('Q_H'), sensor,
                                       pipe['energy_endpoint_change_J'])
        signal = lambda name: sampled(f['signals/'+name], time)
        flow_split = flow_metric_split(time, stage == 4, signal('mass_flow_v4_hot_inlet_kgps'),
            get('mdot_A', 'kg/s'), cp*(signal('cold_hx_inlet_fluid_temp_out')-
                signal('cold_hx_outlet_fluid_temp_out')), port_net)
        terminal_metric_power = float(abs(signal('mass_flow_v4_hot_inlet_kgps')[-1])*cp*(
            signal('cold_hx_inlet_fluid_temp_out')[-1]-signal('cold_hx_outlet_fluid_temp_out')[-1]))
        terminal_endpoint_increment_W = terminal_metric_power*.001/2/100
        original = saved_performance['performance']
        if (abs(original['temperature_lift_eq9_K']-ten['temperature_lift_eq9_K']) > 1e-10 or
                abs(original['cooling_power_eq10_W']-ten['cooling_power_eq10_W']-terminal_endpoint_increment_W) > 1e-10):
            raise ValueError('Independent performance does not reproduce the original analysis endpoint convention')
        boundary = f['thermal_boundary_signals/fields']
        native_heat_means = {name: integrals(time, sampled(row, time))['trapz_J']/20
                            for name, row in boundary.items() if 'heat_flow' in name}
        pump_proxy_means = {name: integrals(time, sampled(boundary[name], time))['trapz_J']/20
                            for name in ('pump_power_sma_W', 'pump_power_se_W')}
    budget = science['modeled_energy_balance']
    return dict(schema='heatdrive_ecc_current_cooling_boundary_reconciliation_v1', source_root=str(root),
        producer=execution['execution_commit'], total_cycles=execution['cycle_count'],
        current_public_ten_cycle_performance=original,
        original_performance_window_s=[stop-100, stop],
        independent_absolute_schedule_ten_cycle_performance=ten,
        endpoint_convention=dict(original_analysis_view_terminal_sample_is_stage4=True,
            uninterrupted_absolute_horizon_terminal_sample_is_stage1=True,
            original_view_minus_absolute_schedule_cooling_W=terminal_endpoint_increment_W,
            interpretation='Half of one 1-ms terminal sample; no missing cycle or changed physical trajectory'),
        matched_native_two_cycle_performance=two,
        chex_pipe_path=pipe['block_path'], cooling_boundary_reconciliation=decomposition,
        stage4_metric_vs_native_port_split=flow_split,
        thermal_boundary_channel_sums_mean_over_two_cycles_W=native_heat_means,
        thermal_boundary_field_provenance='Exchanger heat fields are native; constitutive node arrays are public channel sums',
        modeled_full_inventory_energy_balance_over_two_cycles=budget,
        pumps_over_the_same_two_cycles=ledger['pumps'],
        engineering_pump_proxy_means_over_two_cycles_W=pump_proxy_means,
        pump_scope='Measured signed P*mdot/mean(rho_A,rho_B) is hydraulic estimate; native power_spec.none heat is zero, not electric power',
        control_volumes=[dict(block_path=r['block_path'], mask_type=r['mask_type'],
            storage_change_J=r['energy_endpoint_change_J'], pressure_volume_work_J=r.get('pressure_volume_work_J', 0))
            for r in ledger['components']],
        performance_and_conservation_windows_are_distinct_and_explicit=True,
        largest_aligned_sample_clock_difference_s=clock_difference_max_s,
        alignment_rule='same integer-millisecond indices; at most sixteen floating-point ULPs; no value interpolation',
        ten_cycle_native_coverage_required_for_this_two_cycle_balance=False,
        matched_twenty_second_balance_does_not_prove_ten_cycle_inventory_periodicity=True,
        simulation_executed=False, operating_point_loaded=False, source_state_edited=False,
        real_fluid_EOS_claim=False, production_recovery_allowed=False, outer_solve_eligible=False,
        zero_load_endpoint_accepted=False, zero_lift_endpoint_accepted=False, table4_reproduction_claim=False,
        input_sha256=dict(contract=sha256(contract_path), physics=sha256(physics_path), science=sha256(science_path),
                          original_MATLAB_performance=sha256(saved_performance_path),
                          observations=sha256(raw), configuration=sha256(cfg)))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--contract', type=Path, required=True)
    parser.add_argument('--physics', type=Path, required=True)
    parser.add_argument('--science', type=Path, required=True)
    parser.add_argument('--saved-performance', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Never overwrite boundary reconciliation')
    result = analyze(args.contract, args.physics, args.science, args.saved_performance)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    print(json.dumps({k: result[k] for k in ('matched_native_two_cycle_performance',
        'cooling_boundary_reconciliation', 'stage4_metric_vs_native_port_split', 'endpoint_convention')}, indent=2))
