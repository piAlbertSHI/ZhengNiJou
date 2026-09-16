"""Classify a cold one-cycle audit as a diagnostic seed without granting recovery."""
import argparse
import json
from pathlib import Path

from Audit_HeatDriveECC_SegmentedEvidence import sha256


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def classify(audit, execution):
    if audit['schema'] != 'heatdrive_ecc_cold_buffer_coupled_audit_v2':
        raise ValueError('Unknown cold audit schema')
    if (execution['production_recovery_allowed'] or execution['checkpoint_saved']
            or execution['c200_state_imported'] or len(execution['cases']) != 2):
        raise ValueError('Execution crossed the independent diagnostic boundary')
    if audit['execution_commit'] != execution['execution_commit'] or audit['cycle_count'] != 1:
        raise ValueError('Audit and one-cycle execution do not match')

    failed_flows = []
    phase_rows = []
    for arm in audit['arms']:
        failed_flows.extend(dict(arm=arm['arm'], component=row['component'], stage=row['stage'],
                                 max_abs_relative_error=row['max_abs_relative_error'],
                                 rms_relative_error=row.get('rms_relative_error'))
                            for row in arm['selected_flow_gates'] if not row['selected_flow_gate'])
        for material, row in arm['selected_solid_balances'].items():
            bounds_pass = (0 <= row['all_node_phase_min'] <= 1
                           and 0 <= row['all_node_phase_max'] <= 1
                           and row['selected_solid_energy_gate'])
            phase_rows.append(dict(arm=arm['arm'], material=material,
                                   all_node_phase_min=row['all_node_phase_min'],
                                   all_node_phase_max=row['all_node_phase_max'],
                                   solid_energy_gate=row['selected_solid_energy_gate'],
                                   phase_bounds_and_solid_gate_pass=bounds_pass))

    pressure_gate_evaluated = False
    flow_gate_pass = not failed_flows
    phase_gate_pass = all(row['phase_bounds_and_solid_gate_pass'] for row in phase_rows)
    strict_seed_gate = bool(audit['evidence_audit_pass']
                            and audit['declared_window_numerical_gates_pass']
                            and audit['trajectory_compiled_inventory_gate']
                            and audit['local_inventory_conservation_pass']
                            and audit['strict_initial_coordinate_match']
                            and flow_gate_pass and phase_gate_pass
                            and pressure_gate_evaluated
                            and audit['all_mechanism_gates_evaluated'])
    reasons = []
    if failed_flows:
        reasons.append('SE stage-2/stage-4 selected flow gates failed in both arms')
    if not pressure_gate_evaluated:
        reasons.append('independent pressure gate was not evaluated by this audit')
    if not audit['all_mechanism_gates_evaluated']:
        reasons.append('complete mechanism gate set was not evaluated')
    if audit['full_device_first_law_verified']:
        raise ValueError('Cold audit unexpectedly claims full-device first-law closure')
    return dict(
        schema='heatdrive_ecc_cold_seed_decision_v1',
        evidence_audit_pass=audit['evidence_audit_pass'],
        declared_window_numerical_gates_pass=audit['declared_window_numerical_gates_pass'],
        local_inventory_conservation_pass=audit['local_inventory_conservation_pass'],
        strict_initial_coordinate_match=audit['strict_initial_coordinate_match'],
        trajectory_compiled_inventory_gate=audit['trajectory_compiled_inventory_gate'],
        selected_flow_gates_pass=flow_gate_pass,
        failed_selected_flow_gates=failed_flows,
        phase_bounds_and_solid_energy_gates_pass=phase_gate_pass,
        phase_rows=phase_rows,
        independent_pressure_gate_evaluated=pressure_gate_evaluated,
        all_mechanism_gates_evaluated=audit['all_mechanism_gates_evaluated'],
        diagnostic_20cycle_seed_eligible=strict_seed_gate,
        rejection_reasons=reasons,
        periodic_steady_state=False,
        full_device_first_law_verified=False,
        production_recovery_allowed=False,
        outer_solve_eligible=False,
        paired_table4_eligible=False,
        raw_retention='keep_as_latest_control_volume_failure_evidence')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--audit', type=Path, required=True)
    parser.add_argument('--execution', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--marker', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists() or args.marker.exists():
        raise FileExistsError('Never overwrite a seed decision or rejection marker')
    audit, execution = read(args.audit), read(args.execution)
    result = classify(audit, execution)
    result['input_sha256'] = {
        'audit': sha256(args.audit),
        'execution': sha256(args.execution),
        **{f"{case['arm']}_observations": case['observation_sha256'] for case in execution['cases']},
    }
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    args.marker.write_text('\n'.join((
        'status=rejected_as_20cycle_seed',
        'diagnostic_20cycle_seed_eligible=false',
        'production_recovery_allowed=false',
        'outer_solve_eligible=false',
        'paired_table4_eligible=false',
        f'decision_sha256={sha256(args.output)}',
        f'decision={args.output.resolve()}',
        'raw_retention=keep_as_latest_control_volume_failure_evidence',
        'reason=SE stage-2/stage-4 flow gates failed; pressure and complete mechanism gates were not evaluated',
        '')), encoding='utf-8')
    print(json.dumps(result, indent=2, allow_nan=False))
    return 0 if result['diagnostic_20cycle_seed_eligible'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
