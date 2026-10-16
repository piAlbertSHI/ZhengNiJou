"""Matched transient contrast and frozen-coordinate phase-drive attribution; no OP propagation."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess

import h5py
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def reverse_coordinate(phase, drive_MPa, stress_MPa, rate, material, kinetics):
    x, drive, sigma, observed = [np.asarray(v, dtype=float) for v in (phase, drive_MPa, stress_MPa, rate)]
    As, Ms, C = (material[k] for k in ('T_As_K', 'T_Ms_K', 'C_A_Pa_per_K'))
    k, width = kinetics['rate_r_stage3_unload_1_per_s'], kinetics['drive_width_r_Pa']
    if (any(v.shape != (21,) for v in (x, drive, sigma, observed)) or
            not np.isfinite([x, drive, sigma, observed]).all() or not np.all((0 <= x) & (x <= 1)) or
            not np.isfinite([As, Ms, C, k, width]).all() or As <= Ms or min(C, k, width) <= 0 or
            kinetics['phase_front_smoothing_1_per_s'] != 0):
        raise ValueError('Require the actual 21-node unsmoothed reverse phase law')
    drive_Pa, stress_Pa = drive*1e6, sigma*1e6
    gate = -np.expm1(-np.maximum(drive_Pa, 0)/max(width, 1))
    predicted_rate = -k*gate*x
    if not np.allclose(predicted_rate, observed, rtol=1e-11, atol=1e-12):
        raise ValueError('Logged rate is not the declared original reverse law')
    # Use recorded constitutive drive, not a potentially one-step-shifted public temperature.
    zero_unclipped = x-drive_Pa/(C*(As-Ms))
    zero = np.clip(zero_unclipped, 0, 1)
    inferred_T = (drive_Pa+stress_Pa)/C+As-(As-Ms)*x
    margin = drive_Pa/C-(As-Ms)*x
    return dict(actual_mean_phase=float(x.mean()), mean_frozen_zero_drive_coordinate=float(zero.mean()),
        mean_phase_minus_frozen_coordinate=float((x-zero).mean()),
        frozen_coordinate_is_causal_contribution_or_asymptotic_bound=False,
        rate_identity_max_abs_error_per_s=float(np.max(np.abs(predicted_rate-observed))),
        nodes=[dict(node=i+1, phase=float(x[i]), reverse_gate=float(gate[i]),
                    inferred_constitutive_input_temperature_K=float(inferred_T[i]),
                    full_reverse_zero_drive_temperature_margin_K=float(margin[i]),
                    frozen_zero_drive_phase_coordinate=float(zero[i]),
                    logged_phase_rate_per_s=float(observed[i])) for i in range(21)])


def normalized_recipe(value):
    value = copy.deepcopy(value)
    value.pop('output_root')
    for key in ('collection_root', 'candidate_Tc_K'):
        value['diagnostic_observation_options'].pop(key)
    return value


def compare(first, second, output):
    if output.exists():
        raise FileExistsError('Do not overwrite mechanism attribution')
    cases = [read(first), read(second)]
    roots = [Path(c['collection_root']) for c in cases]
    source = [read(r/'initial_recording_contract.json') for r in roots]
    recipes = [read(r/'initial_prepared_recipe.json') for r in roots]
    results = [read(r/'collection_result.json') for r in roots]
    if (source[0] != source[1] or sha256(roots[0]/'initial_recording_contract.json') != sha256(roots[1]/'initial_recording_contract.json') or
            normalized_recipe(recipes[0]) != normalized_recipe(recipes[1]) or
            any(c['rejected_packet_may_propagate'] or c['root_interpolation_allowed'] for c in cases)):
        raise ValueError('The two trajectories must have a common complete source and unchanged recipe')
    repo = Path(__file__).resolve().parents[1]
    changed = subprocess.check_output(['git', 'diff', '--name-only', results[0]['producer'], results[1]['producer']],
                                      cwd=repo.parent).decode('utf-8').splitlines()
    if any(Path(p).suffix.lower() in ('.m', '.ssc', '.slx', '.p') for p in changed):
        raise ValueError('MATLAB/Simscape implementation changed between physical executions')
    validator_paths = ['Verify_HeatDriveECC_ObservationPacket.py', 'Audit_HeatDriveECC_ColdBufferCoupled.py',
                       'Audit_HeatDriveECC_CoupledEnergyInventory.py']
    common_validator_sha = {}
    for name in validator_paths:
        path = 'gx101r1_R69_remote/verification/'+name
        blobs = [subprocess.check_output(['git', 'show', r['producer']+':'+path], cwd=repo.parent) for r in results]
        if blobs[0] != blobs[1]:
            raise ValueError('Scientific verifier changed between executions')
        common_validator_sha[name] = hashlib.sha256(blobs[0]).hexdigest().upper()
    dependencies = {p.resolve() for p in (first, second)}
    for r in roots:
        dependencies.update((r/n).resolve() for n in ('initial_recording_contract.json', 'initial_prepared_recipe.json', 'collection_result.json'))
    trajectories = []
    for c in cases:
        last = c['cycles'][-1]
        cfg = Path(c['packets'][-1]['packet_root'])/'native/configuration.mat'
        dependencies.add(cfg.resolve())
        with h5py.File(cfg) as f:
            scalar = lambda group, name: float(f['options/'+group+'/'+name][0, 0])
            material = {n: scalar('material/SE', n) for n in ('T_As_K', 'T_Ms_K', 'C_A_Pa_per_K')}
            kinetics = {n: scalar('constitutive', n) for n in (
                'rate_r_stage3_unload_1_per_s', 'drive_width_r_Pa', 'phase_front_smoothing_1_per_s')}
        budget = reverse_coordinate(last['cold_min_node_phase'], last['cold_min_logged_reverse_drive_MPa'],
            last['cold_min_node_SE_stress_MPa'], last['cold_min_logged_phase_rate_per_s'], material, kinetics)
        trajectories.append(dict(Tc_K=c['candidate_Tc_K'], cycle=last['cycle'], time_s=last['cold_half_min_time_s'],
            material=material, kinetics=kinetics, budget=budget,
            public_temperature_is_not_silently_used_as_constitutive_input=True))
    if trajectories[0]['material'] != trajectories[1]['material'] or trajectories[0]['kinetics'] != trajectories[1]['kinetics']:
        raise ValueError('Phase material or kinetic parameters changed')
    rows = [{r['cycle']: r for r in c['cycles'] if r['original_packet_mechanism_pass']} for c in cases]
    common = sorted(set(rows[0]) & set(rows[1]))
    if len(common) < 4 or any(b != a+1 for a, b in zip(common, common[1:])):
        raise ValueError('Require an intact common gate-passing transient interval')
    # Retain original arrays for the first and last shared two-cycle packets.
    selected = common[:2]+common[-2:]
    contrasts = []
    for cycle in selected:
        a, b = rows[0][cycle], rows[1][cycle]
        if a['window_s'] != b['window_s'] or a['cold_half_completion_s'] is None or b['cold_half_completion_s'] is None:
            raise ValueError('A matched transient contrast must not borrow a failed/missing event')
        contrasts.append(dict(cycle=cycle, window_s=a['window_s'], first_Tc_K=cases[0]['candidate_Tc_K'],
            second_Tc_K=cases[1]['candidate_Tc_K'],
            second_minus_first={k: b[k]-a[k] for k in ('cooling_power_eq10_W', 'temperature_lift_eq9_K',
                'cold_half_min_mean_phase', 'cold_half_completion_s')},
            finite_time_contrast_only=True, steady_derivative_or_root_point=False))
        for c in cases:
            packet = next(p for p in c['packets'] if p['window_s'][0] <= a['window_s'][0] and p['window_s'][1] >= a['window_s'][1])
            root = Path(packet['packet_root'])
            m = read(root/'packet_manifest.json')
            dependencies.update((root/n).resolve() for n in ('packet_manifest.json', 'packet_gate.json', 'boundary_comparison.json'))
            for entry in m['input_files']:
                file = (root/entry['path']).resolve()
                if not file.is_relative_to(root.resolve()) or sha256(file) != entry['sha256']:
                    raise ValueError('Changed retained matched-time raw evidence')
                dependencies.add(file)
    output.parent.mkdir(parents=True, exist_ok=True)
    record = dict(schema='heatdrive_ecc_phase_drive_budget_v1', producer_source_sha256=sha256(Path(__file__)),
        common_source_complete_OP_sha256=source[0]['operating_point_sha256'],
        normalized_recipes_equal=True, MATLAB_and_Simscape_implementations_unchanged=True,
        common_scientific_validator_sha256=common_validator_sha,
        matched_retained_cycles=selected, matched_transient_contrasts=contrasts,
        respective_failed_endpoint_drive_coordinates=trajectories,
        frozen_coordinate_note='Zero of the actual reduced reverse-drive law at frozen current constitutive temperature and compatible stress. Not a coupled equilibrium, causal factor attribution or globally valid phase floor.',
        failed_endpoints_are_not_matched_absolute_times=True,
        root_interpolation_allowed=False, failed_OP_propagation_allowed=False, production_recovery_allowed=False,
        six_factor_coupled_sensitivity_completed=False,
        files=[dict(path=str(p), sha256=sha256(p)) for p in sorted(dependencies)])
    output.write_text(json.dumps(record, indent=2, allow_nan=False)+'\n', encoding='utf-8', newline='\n')
    return dict(output_sha256=sha256(output), matched_cycles=selected,
        endpoint_diagnostics=[dict(Tc_K=t['Tc_K'], cycle=t['cycle'], mean_phase=t['budget']['actual_mean_phase'],
            frozen_zero_drive_coordinate=t['budget']['mean_frozen_zero_drive_coordinate'],
            node21=t['budget']['nodes'][-1]) for t in trajectories],
        root_interpolation_allowed=False)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('first', 'second', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    print(json.dumps(compare(**vars(parser.parse_args())), indent=2))
