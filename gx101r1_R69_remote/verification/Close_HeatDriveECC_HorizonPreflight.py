"""Seal completed command compatibility evidence, without granting recovery authority."""
import argparse
import json
from pathlib import Path

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from HeatDriveECC_CommandHorizon import audit_prefix


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def comparison_summary(value):
    counts = dict(states=74, native=1262, sources=162, public=201)
    if not value['pass']:
        raise ValueError('Comparison failed')
    rows = {}
    for name, count in counts.items():
        row = value[name]
        if row['trace_count'] != count or not row['pass']:
            raise ValueError('Incomplete comparison')
        rows[name] = {key: row[key] for key in (
            'trace_count', 'channel_count', 'pass', 'bitwise_values_equal', 'max_tolerance_ratio')}
    return rows


def close(prepared, qualification, output, exit_code):
    prepared = prepared.resolve()
    native = prepared/'native'
    root = native/'horizon_preflight'
    result = read(native/'command_horizon_preflight.json')
    q = read(qualification)
    if (exit_code != 0 or output.exists() or result['stage'] != 'completed' or not result['pass'] or
            not result['short_step_comparison_pass'] or not result['complete_two_cycle_comparison_pass'] or
            result['comparison_states_may_propagate'] or result['source_state_edited'] or
            result['physical_parameters_changed'] or result['production_recovery_allowed'] or
            result['checksum_policy'] != 'error/error' or
            result['source_qualification_sha256'] != sha256(qualification) or
            result['source_OP_sha256'] != sha256(Path(q['operating_point_path']))):
        raise ValueError('Uncompleted or changed preflight/source')
    prefix = None
    gates = {}
    for case in ('reference', 'extended'):
        packet = root/case
        manifest = read(packet/'packet_manifest.json')
        prefix = audit_prefix(packet, manifest['horizon_comparison'])
        gate = read(packet/'packet_gate.json')
        if (manifest['packet_role'] != 'runtime_horizon_comparison' or
                manifest['parent_complete_OP_sha256'] != result['source_OP_sha256'] or
                not gate['gate_pass'] or not gate['original_mechanism_pass'] or
                gate['original_mechanism_count'] != 73 or not all(gate['six_local_inventory_gates']) or
                len(gate['flow_gates']) != 6 or not all(r['selected_flow_gate'] for r in gate['flow_gates']) or
                not gate['modeled_energy_balance']['model_equation_energy_closure_pass'] or
                gate['storage_count'] != 119 or gate['source_count'] != 49 or
                not read(packet/'boundary_comparison.json')['pass'] or
                not read(packet/'resolved_commands.json')['all_actual_bindings_exact']):
            raise ValueError('Changed or incomplete original gate evidence')
        gates[case] = dict(original_mechanisms=73, flow_gates=6, local_inventory_gates=6,
                           storage_count=119, source_count=49, all_pass=True)
    comparisons = {case: comparison_summary(read(root/(case+'_comparison.json')))
                   for case in ('short', 'full')}
    files = []
    for file in sorted(prepared.rglob('*')):
        if file.is_symlink():
            raise ValueError('Unexpected linked evidence')
        if file.is_file():
            files.append(dict(path=str(file), bytes=file.stat().st_size, sha256=sha256(file)))
    record = dict(schema='heatdrive_ecc_command_horizon_closeout_v1', producer=result['producer'],
        terminal_exit_code=exit_code, source_snapshot_s=result['source_snapshot_s'],
        source_qualification_path=str(qualification.resolve()),
        source_qualification_sha256=sha256(qualification), source_OP_sha256=result['source_OP_sha256'],
        compared_window_s=result['full_window_s'], comparisons=comparisons, original_gates=gates,
        independent_prefix_reverification=prefix, future_coverage_compatibility_preflight_pass=True,
        extended_continuation_contract_implemented=False, actual_200_cycle_crossing_verified=False,
        comparison_states_may_propagate=False, production_recovery_allowed=False,
        current_diagnostic_restore_cycles=108, C200_mainline_authority_unchanged=True,
        storage_classification='retain_latest_successful_compatibility_evidence_single_raw_copy',
        prepared_bytes=sum(r['bytes'] for r in files), files=files)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(record, indent=2)+'\n', encoding='utf-8')
    return dict(pass_=True, files=len(files), prepared_bytes=record['prepared_bytes'],
                comparison_bitwise_all=all(r['bitwise_values_equal'] for rows in comparisons.values() for r in rows.values()),
                closeout_sha256=sha256(output), comparison_states_may_propagate=False)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('prepared', 'qualification', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--exit-code', type=int, required=True)
    print(json.dumps(close(**vars(parser.parse_args())), indent=2))
