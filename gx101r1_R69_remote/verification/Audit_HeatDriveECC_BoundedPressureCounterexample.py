"""Read-only source-oriented diagnosis of the failed bounded C3 experiment."""
import argparse
import hashlib
import json
from pathlib import Path

import h5py
import numpy as np


def sha256(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest().upper()


def pressure_interval(datum, minimum, maximum, margin, requested, reference_port):
    """Ideal reference-port interval, NOT a whole-network safety certificate."""
    if (not np.isfinite([datum,minimum,maximum,margin,*requested]).all() or
            len(requested) != 2 or reference_port not in ('A', 'B') or
            not minimum + margin < datum < maximum - margin):
        raise ValueError('Require a named ideal reference port inside the property domain')
    if margin <= 0 or requested[0] >= requested[1]:
        raise ValueError('Invalid headroom or command interval')
    # Native source equation: B.p - A.p == P.
    if reference_port == 'A':
        legal = (minimum + margin - datum, maximum - margin - datum)
    else:
        legal = (datum - maximum + margin, datum - minimum - margin)
    result = [max(requested[0], legal[0]), min(requested[1], legal[1])]
    if result[0] >= result[1]:
        raise ValueError('Empty oriented command interval')
    return result


def flow_metrics(flow, command, raw_sum, target, lower, upper, rms_limit):
    error = np.abs(flow) / target - 1
    saturation = np.isclose(command, lower, rtol=0, atol=1e-12)
    return dict(samples=int(flow.size), rms_relative=float(np.sqrt(np.mean(error**2))),
                rms_limit=float(rms_limit), rms_pass=bool(np.sqrt(np.mean(error**2)) <= rms_limit),
                mean_relative_error=float(np.mean(error)),
                maximum_absolute_relative_error=float(np.max(np.abs(error))),
                lower_saturation_fraction=float(np.mean(saturation)),
                clipped_sum_command_max_error_MPa=float(np.max(np.abs(
                    command - np.clip(raw_sum, lower, upper)))))


def audit(root, source_file):
    native = root / 'native'
    proof = json.loads((native / 'rebuilt_cycle_restore.json').read_text(encoding='utf-8'))
    capture_root = Path(proof['source_root'])
    cold = json.loads((capture_root / 'native/cold_mechanism_audit.json').read_text(encoding='utf-8'))
    if not (proof['rebuilt_complete_cycle_pass'] and proof['strict_restore_completed']
            and proof['continuous_reference_pass'] and not proof['source_state_edited']
            and not proof['partial_state_restore_used'] and proof['checksum_policy'] == 'error/error'
            and len(proof['state_comparisons']) == 74 and len(proof['signal_comparisons']) == 201
            and all(r['values_exact'] and r['clock_pass'] and r['samples'] == 10001
                    for r in proof['state_comparisons'] + proof['signal_comparisons'])
            and cold['mechanism_pass']):
        raise ValueError('Require passed C2 mechanism and actual exact full-cycle state proof')
    equation = 'B.p - A.p == p_diff;'
    source = source_file.read_text(encoding='utf-8')
    if equation not in source or 'p_diff = P;' not in source:
        raise ValueError('The installed native pressure-source sign was not verified')
    file = native / 'restored_physical_observation.mat'
    with h5py.File(file) as handle:
        p = handle['physical']; s = handle['signals']; o = handle['configured']
        get = lambda group, key: np.asarray(group[key][:], dtype=float).reshape(-1)
        scalar = lambda group, key: float(get(group, key)[0])
        t = get(p, 'time_s')
        if t.size != 10001 or not np.allclose(t, 20 + np.arange(10001)*.001, rtol=0, atol=1e-9):
            raise ValueError('Missing exact C3 samples')
        stage = get(p, 'stage_id'); elapsed = get(p, 'stage_elapsed_s')
        branch = o['branch']; validation = o['validation']
        domain = validation['pressure_command_domain_contract']
        minimum = scalar(domain, 'minimum_absolute_MPa'); maximum = scalar(domain, 'maximum_absolute_MPa')
        datum = scalar(branch, 'network_absolute_pressure_MPa'); margin = scalar(domain, 'declared_margin_MPa')
        durations = get(o['schedule'], 'stage_durations_s')
        ramp = scalar(branch, 'stage_command_ramp_s')
        settled = scalar(validation, 'se_settled_guard_s') + scalar(o['simulation'], 'fixed_step_s')
        target = np.mean([scalar(branch, 'm_dot_se_the_kg_per_s'),
                          scalar(branch, 'm_dot_se_chex_kg_per_s')])
        lower = scalar(branch, 'se_pressure_pi_min_MPa'); upper = scalar(branch, 'pressure_pi_max_MPa')
        rms_limit = scalar(validation, 'max_se_settled_flow_rms_relative_error')
        command = get(p, 'pressure_command_SE_MPa')
        pressure_rows = []
        for name in s:
            if name.startswith('pump_pressure_'):
                values = get(s[name], 'values')
                pressure_rows.append(dict(name=name, minimum_MPa=float(values.min()),
                                          maximum_MPa=float(values.max()),
                                          current_domain_pass=bool(values.min() >= minimum and values.max() <= maximum)))
        if len(pressure_rows) != 6:
            raise ValueError('Incomplete actual named A/B pressures')
        rows = []
        for selected_stage in (2, 4):
            mask = ((stage == selected_stage) & (elapsed >= max(ramp, settled)) &
                    (elapsed <= durations[selected_stage-1]-ramp))
            flow = get(p, f'mdot_SE_stage{selected_stage}_in_kgps')[mask]
            a = get(s[f'pump_pressure_se_stage{selected_stage}_port_a_MPa'], 'values')[mask]
            b = get(s[f'pump_pressure_se_stage{selected_stage}_port_b_MPa'], 'values')[mask]
            cmd = command[mask]
            residual = float(np.max(np.abs(b - a - cmd)))
            if residual > 1e-10:
                raise ValueError('Actual source sign/units/clock does not match native equation')
            raw = get(s['stage4_bias_sum'], 'values')[mask] if selected_stage == 4 else cmd
            metrics = flow_metrics(flow, cmd, raw, target, lower, upper, rms_limit)
            if selected_stage != 4:
                metrics.pop('clipped_sum_command_max_error_MPa')
            rows.append(dict(stage=selected_stage, source_equation_max_residual_MPa=residual,
                             observed_minimum_port_pressure_MPa=float(min(a.min(), b.min())),
                             port_B_range_MPa=[float(b.min()), float(b.max())],
                             naive_datum_plus_command_min_MPa=float(datum + cmd.min()),
                             prelimit_sum_evaluated=selected_stage==4, **metrics))
    failed = [key for key, value in proof['bounded_restored_cycle_mechanism_checks'].items() if not value]
    return dict(schema='heatdrive_ecc_bounded_pressure_counterexample_v1', source_root=str(root),
                installed_native_equation=equation, source_sign_verified_on_actual_samples=True,
                source_equation_file=str(source_file), actual_pressure_rows=pressure_rows, stage_records=rows,
                actual_all_six_pump_ports_domain_pass=all(r['current_domain_pass'] for r in pressure_rows),
                naive_uniform_lower_absolute_pressure_inference_is_not_qualified=True,
                ideal_A_reference_interval_MPa=pressure_interval(datum,minimum,maximum,margin,[-.5,.02],'A'),
                ideal_B_reference_interval_MPa=pressure_interval(datum,minimum,maximum,margin,[-.5,.02],'B'),
                reference_port_topology_and_head_loss_bounds_still_required=True,
                bounded_cold_C2_mechanism_pass=True, bounded_C3_mechanism_pass=False,
                bounded_C3_failed_checks=failed, full_cycle_state_restore_pass=True,
                native_snapshot_failure=proof['error_message'], simulation_executed=False,
                thresholds_changed=False, state_edited=False, production_recovery_allowed=False,
                twenty_cycle_continuation_allowed=False, strict_table4_reproduction_pass=False,
                input_sha256={str(path): sha256(path) for path in
                              (file,native/'rebuilt_cycle_restore.json',native/'rebuilt_cycle_comparison.mat',
                               capture_root/'native/cold_mechanism_audit.json',source_file)})


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--native-source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Never overwrite scientific evidence')
    result = audit(args.root.resolve(), args.native_source.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps(dict(state_restore_pass=True, original_C3_failed_checks=result['bounded_C3_failed_checks'],
                         stages=result['stage_records'], twenty_cycle_continuation_allowed=False),indent=2))
