"""Test disjoint same-Tc metric repeatability, not exact/asymptotic state equality."""
import argparse
import json
import math
from pathlib import Path

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Close_HeatDriveECC_SplitObservation import read


def compare_metrics(reference, candidate, lift_limit, scp_limit):
    fields = ('temperature_lift_eq9_K', 'SCP_W_per_g')
    values = [r[key] for r in (reference, candidate) for key in fields]
    if (not all(type(v) in (int, float) and math.isfinite(v) for v in values) or
            lift_limit != .1 or scp_limit != .01):
        raise ValueError('Finite metrics and unchanged declared outer precision required')
    differences = {key: candidate[key]-reference[key] for key in fields}
    return dict(differences=differences, lift_limit_K=lift_limit, SCP_limit_W_per_g=scp_limit,
        disjoint_metric_repeatability_pass=bool(abs(differences[fields[0]]) <= lift_limit and
                                               abs(differences[fields[1]]) <= scp_limit),
        asymptotic_error_bound_claim=False, exact_internal_periodicity_claim=False,
        new_physical_threshold_imposed=False)


def window_lineage(reference, candidate):
    a, b = reference['current_window_s'], candidate['current_window_s']
    if (a[1]-a[0] != 100 or b[1]-b[0] != 100 or b[0] < a[1] or
            reference['temperature_K'] != candidate['temperature_K'] or
            not candidate['same_Tc_continuation'] or
            any(r['source_state_edited'] or not r['all_four_memories_bitwise_preserved'] or
                not r['all_original_packet_mechanism_flow_phase_energy_gates_pass'] or
                not r['original_public_thermal_periodic_pass'] or
                not r['current_target_window_stability']['precision_pass']
                for r in (reference, candidate))):
        raise ValueError('Require disjoint, physically qualified, unchanged-Tc periodic windows')
    return a, b


def analyze(reference, candidate, output):
    if output.exists():
        raise FileExistsError('Never overwrite a repeatability decision')
    a, b = read(reference), read(candidate)
    windows = window_lineage(a, b)
    for path, q in ((reference, a), (candidate, b)):
        if (q['schema'] != 'heatdrive_ecc_runtime_Tc_candidate_endpoint_v1' or
                q['production_recovery_allowed'] or q['old_model_OP_imported'] or
                sha256(Path(q['operating_point_path'])) != q['operating_point_sha256']):
            raise ValueError('Wrong family or changed full-state diagnostic')
        for row in q['files']:
            if sha256(Path(row['path'])) != row['sha256']:
                raise ValueError('Changed qualification dependency')
    refhash = sha256(reference)
    if not any(Path(r['path']).resolve() == reference.resolve() and r['sha256'] == refhash for r in b['files']):
        raise ValueError('Candidate did not inherit the exact reference qualification')
    records = [Path(r['path']) for r in b['files'] if Path(r['path']).name == 'collection_result.json']
    if len(records) != 1:
        raise ValueError('Ambiguous continuation collection')
    result = read(records[0]); c = result['continuation']
    if (result['candidate_Tc_K'] != a['temperature_K'] or c['source_snapshot_s'] != a['snapshot_time_s'] or
            c['source_qualification_sha256'] != refhash or c['source_OP_sha256'] != a['operating_point_sha256'] or
            not c['temperature_unchanged'] or not result['pass'] or result['source_state_edited']):
        raise ValueError('Changed source state or continuation boundary')
    limits = [q['current_target_window_stability'] for q in (a, b)]
    if any(r['lift_limit_K'] != .1 or r['SCP_limit_W_per_g'] != .01 for r in limits):
        raise ValueError('Numerical precision changed')
    record = dict(schema='heatdrive_ecc_disjoint_same_Tc_repeatability_v1',
        temperature_K=a['temperature_K'], reference_window_s=windows[0], candidate_window_s=windows[1],
        reference_qualification_sha256=refhash, candidate_qualification_sha256=sha256(candidate),
        source_complete_OP_sha256=a['operating_point_sha256'],
        candidate_complete_OP_sha256=b['operating_point_sha256'],
        reference_performance=a['performance'], candidate_performance=b['performance'],
        **compare_metrics(a['performance'], b['performance'], .1, .01),
        interpretation='Finite-precision repeatability on two actual disjoint windows, not an asymptotic bias bound or a substitute for inventory/PI assessment.',
        root_bracket_established=False, full_goal_outer_root_admission_established=False,
        production_recovery_allowed=False, table4_reproduction_claim=False,
        simulation_executed=False, source_state_edited=False,
        producer_source_sha256=sha256(Path(__file__)))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(record, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    return record


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('reference', 'candidate', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    print(json.dumps(analyze(**vars(parser.parse_args())), indent=2))
