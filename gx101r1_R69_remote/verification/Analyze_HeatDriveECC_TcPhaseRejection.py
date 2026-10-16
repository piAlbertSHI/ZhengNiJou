"""Read-only attribution of a rejected temperature trial; never authorize its OP."""
import argparse
import csv
import json
import math
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Close_HeatDriveECC_RuntimeWarmup import packet_cycles
from HeatDriveECC_ObservationWindow import window_indices


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def phase_cycles(time, nodes):
    time, nodes = np.asarray(time).ravel(), np.asarray(nodes)
    begin, end = float(time[0]), float(time[-1])
    window_indices(time, begin, end)
    if end-begin != 20 or nodes.shape != (21, 20001) or not np.isfinite(nodes).all():
        raise ValueError('Require the original intact two-cycle SE phase trace')
    local = time-begin
    cycle = np.minimum(np.floor(local/10).astype(int), 1)
    elapsed = local-10*cycle
    mean = nodes.mean(axis=0)
    rows = []
    for c in range(2):
        selected = cycle == c
        cold = selected & (elapsed >= 5)
        cold_indices = np.flatnonzero(cold)
        minimum_index = int(cold_indices[np.argmin(mean[cold])])
        completion = cold_indices[mean[cold] <= .01]
        rows.append(dict(cycle=int(begin/10)+c+1,
            mean_phase_min=float(mean[selected].min()), mean_phase_max=float(mean[selected].max()),
            phase_swing=float(np.ptp(mean[selected])),
            cold_half_min_mean_phase=float(mean[minimum_index]),
            cold_half_min_time_s=float(time[minimum_index]),
            cold_half_completion_s=float(elapsed[completion[0]]-5) if completion.size else None,
            cold_min_node_phase=nodes[:, minimum_index].tolist(),
            original_99_percent_swing_pass=bool(np.ptp(mean[selected]) >= .99),
            original_cold_half_1_percent_completion_pass=bool(completion.size)))
    return rows


def analyze(collection, output):
    if output.exists():
        raise FileExistsError('Preserve original rejection evidence')
    collection = collection.resolve()
    result = read(collection/'collection_result.json')
    if result['pass'] or not result['error_message'] or not result['completed_packets']:
        raise ValueError('Require a stopped failed collection with verified predecessor packets')
    rejected = Path(result['current_attempt_root'])
    if not (rejected/'REJECTED_DO_NOT_RESUME.json').exists():
        raise ValueError('Rejected OP must remain explicitly excluded')
    origin = read(collection/'initial_recording_contract.json')
    parent = origin['operating_point_sha256']
    packets = [Path(r['packet_root']) for r in result['completed_packets']]+[rejected]
    cycles, details = [], []
    for i, packet in enumerate(packets):
        manifest = read(packet/'packet_manifest.json')
        mechanism = read(packet/'mechanism.json')
        checks = mechanism['checks']
        if len(checks) != 73 or manifest['parent_complete_OP_sha256'] != parent:
            raise ValueError('Broken original mechanism or complete-state lineage')
        for entry in manifest['input_files']:
            file = (packet/entry['path']).resolve()
            if not file.is_relative_to(packet.resolve()) or sha256(file) != entry['sha256']:
                raise ValueError('Changed or escaped original packet array')
        parent = sha256(packet/'comparison_only_complete_op.mat')
        if parent != manifest['complete_OP_sha256']:
            raise ValueError('Changed complete OP')
        failed = [key for key, value in checks.items() if not value]
        if i < len(packets)-1:
            gate, boundary = read(packet/'packet_gate.json'), read(packet/'boundary_comparison.json')
            if failed or not gate['gate_pass'] or not boundary['pass']:
                raise ValueError('Unverified predecessor packet')
        elif set(failed) != {'SE_phase_swing', 'qian_table4_half_cycle_phase_completion'}:
            raise ValueError('This attribution must not hide another scientific failure')
        metrics = packet_cycles(packet)
        with h5py.File(packet/'native/observations.mat') as f:
            signal = f['signals/ECC_constitutive21_output']
            begin, end = manifest['window_s']
            indices = window_indices(signal['time_s'][:], begin, end)
            time = signal['time_s'][:].ravel()[indices]
            phase = phase_cycles(time, signal['values'][63:84, indices])
            temperature = f['signals/SE_Tx21_internal']
            if not np.array_equal(temperature['time_s'][:].ravel(), signal['time_s'][:].ravel()):
                raise ValueError('Node temperatures must use the same measured clock')
            for row in phase:
                sample = int(indices[np.flatnonzero(time == row['cold_half_min_time_s'])[0]])
                row['cold_min_node_temperature_K'] = temperature['values'][:, sample].tolist()
                for key, start, scale in (('cold_min_node_SE_stress_MPa', 105, 1e6),
                                         ('cold_min_logged_reverse_drive_MPa', 189, 1e6),
                                         ('cold_min_logged_phase_rate_per_s', 231, 1)):
                    row[key] = (signal['values'][start:start+21, sample]/scale).tolist()
        with (packet/'cycle_physical_summary.csv').open(encoding='utf-8-sig', newline='') as stream:
            original = list(csv.DictReader(stream))
        if len(original) != 2:
            raise ValueError('Incomplete original cycle summaries')
        for row, metric, csv_row in zip(phase, metrics, original):
            for key, field in (('mean_phase_min', 'xM_SE_min'), ('mean_phase_max', 'xM_SE_max'),
                               ('phase_swing', 'xM_SE_swing')):
                if not math.isclose(row[key], float(csv_row[field]), abs_tol=1e-12, rel_tol=1e-12):
                    raise ValueError('Raw phase and original production summary disagree')
            completion = float(csv_row['stage3_SE_unloading_completion_s'])
            if (row['cold_half_completion_s'] is None) != math.isnan(completion):
                raise ValueError('Cold-half completion classification disagrees')
            row.update(metric, original_packet_mechanism_pass=mechanism['passed'],
                       transient_diagnostic_only=True, outer_interpolation_allowed=False)
            cycles.append(row)
        details.append(dict(packet_root=str(packet), window_s=manifest['window_s'], failed_checks=failed,
            manifest_sha256=sha256(packet/'packet_manifest.json'),
            mechanism_sha256=sha256(packet/'mechanism.json'),
            original_summary_sha256=sha256(packet/'cycle_physical_summary.csv'),
            complete_OP_sha256=parent, complete_OP_may_propagate=False))
    files = [dict(path=str(f), bytes=f.stat().st_size, sha256=sha256(f))
             for f in sorted(collection.rglob('*')) if f.is_file()]
    record = dict(schema='heatdrive_ecc_rejected_Tc_phase_attribution_v1', terminal_exit_code=1,
        producer_source_sha256=sha256(Path(__file__)),
        collection_root=str(collection), source_Tc_K=origin['temperature_K'], candidate_Tc_K=result['candidate_Tc_K'],
        source_snapshot_s=origin['snapshot_time_s'], verified_stop_s=result['last_verified_snapshot_time_s'],
        attempted_stop_s=result['current_attempt_window_s'][1],
        original_collection_window_field_s=result['collection_window_s'],
        original_collection_window_field_stale_on_failure=True,
        verified_additional_cycles=2*len(result['completed_packets']), attempted_additional_cycles=2*len(packets),
        packets=details, cycles=cycles,
        disposition='original full-transformation benchmark condition rejected; no solver failure established',
        failed_packet_native_inventory_gate_evaluated=False,
        failed_packet_native_gate_note='Original verifier stops before native ledgers when mechanism fails. Solid-energy checks passed; do not claim the full failed-packet native energy audit passed.',
        original_thresholds_changed=False, rejected_packet_may_propagate=False,
        last_verified_packet_is_qualified_steady_response=False,
        steady_feasibility_boundary_established=False, causal_Tc_derivative_claim=False,
        root_interpolation_allowed=False, production_recovery_allowed=False,
        storage_classification='retain_latest_rejected_phase_boundary_evidence_and_verified_prefix_single_raw_copy',
        collection_bytes=sum(r['bytes'] for r in files), raw_copied_bytes=0, files=files)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(record, indent=2, allow_nan=False)+'\n', encoding='utf-8', newline='\n')
    return dict(verified_cycles=record['verified_additional_cycles'], attempted_cycles=record['attempted_additional_cycles'],
        final_cycle=cycles[-1], collection_bytes=record['collection_bytes'], output_sha256=sha256(output),
        rejected_packet_may_propagate=False)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--collection', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    print(json.dumps(analyze(**vars(parser.parse_args())), indent=2))
