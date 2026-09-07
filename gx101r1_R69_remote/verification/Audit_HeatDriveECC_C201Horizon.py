"""Independently audit C201 command extension and inherited C200 states."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C200RestoredSignals import compare
from Audit_HeatDriveECC_C200StateCapture import archived_source
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field


def named_rows(f, refs):
    rows = {}
    for ref in refs[:].flat:
        row = f[ref]
        key = (text_field(row['block_path']), text_field(row['state_name']))
        if key in rows:
            raise ValueError('Duplicate observed identity')
        rows[key] = row
    return rows


def check_period(t, y):
    t, y = np.asarray(t).reshape(-1), np.asarray(y)
    if t[-1] != 2010 or np.any(np.diff(t) <= 0) or not np.isfinite(y).all():
        raise ValueError('Invalid extended command grid')
    left, right = (t >= 1990) & (t <= 2000), (t >= 2000) & (t <= 2010)
    # Compare every actual command knot, not a sparse representative grid.
    if (left.sum() < 5 or left.sum() != right.sum()
            or not np.allclose(t[right]-t[left], 10, rtol=0, atol=1e-10)):
        raise ValueError('C201 command knots are not a full repeated cycle')
    result = compare(y[:, left], y[:, right])
    if not result['pass_endpoint_match']:
        raise ValueError('C201 command values differ from the preceding cycle')
    result['knot_count'] = int(left.sum())
    return result


def audit(repo):
    archive = repo/'outputs_storage_audit/c200_source_compatibility_20260907'
    probe = repo/'outputs_storage_audit/c200_horizon_20260907/probe201'
    source = archived_source(archive)
    meta_path = probe/'source_restore_audit.json'
    meta = json.loads(meta_path.read_text(encoding='utf-8-sig'))
    authority = json.loads((repo/'verification/c200_mainline_freeze_contract.json').read_text(encoding='utf-8-sig'))
    if (not meta['strict_restore_pass'] or not meta['observation_complete'] or meta['error_message']
            or not all(meta['physical_options_unchanged'].values()) or meta['target_cycle_count'] != 201
            or meta['original_cycle_count'] != 200 or meta['schedule_total_time_s'] != 2010
            or not meta['command_horizon_extended'] or meta['full_cycle_verified']
            or meta['source_operating_point_edited'] or meta['partial_restore_executed'] or meta['cold_start_executed']
            or meta['production_recovery_allowed']):
        raise ValueError('Horizon restore contract failed')
    for key, field in [('result_relative_path','result_sha256'), ('checkpoint_relative_path','checkpoint_sha256')]:
        if sha256(repo/authority[key]) != authority[field] or meta[field] != authority[field]:
            raise ValueError('Frozen authority hash changed')
    parameters = {r['Name']: r['Value'] for r in meta['input_parameters']}
    for name in ('OperatingPointContentsChecksumMismatchMsg','OperatingPointInterfaceChecksumMismatchMsg'):
        if parameters[name] != 'error':
            raise ValueError('Strict checksum checks were relaxed')
    comparisons = []
    def initial(left, right, key):
        for row in (left, right):
            if not np.array_equal(row['time_s'][:].reshape(-1), [2000,2000.001]):
                raise ValueError('Unexpected probe window')
            if row['values'].shape[-1] != 2 or not np.isfinite(row['values'][:]).all():
                raise ValueError('Invalid probe values')
        result = compare(left['values'][:,0],right['values'][:,0])
        comparisons.append(dict(identity=key, **result))
    raw = probe/'restored_step_signals.mat'
    registered = probe/'registered_states.mat'
    baseline = archive/'archived_source_probe_v4'
    with h5py.File(baseline/'restored_step_signals.mat') as a, h5py.File(raw) as b:
        if set(a['signals']) != set(b['signals']) or len(b['signals']) != 161:
            raise ValueError('Physical signal coverage changed')
        for name in a['signals']:
            initial(a['signals'][name], b['signals'][name], name)
        x, y = named_rows(a,a['native']), named_rows(b,b['native'])
        if set(x) != set(y) or len(y) != 1240:
            raise ValueError('Native inventory coverage changed')
        for key in x:
            if text_field(x[key]['unit']) != text_field(y[key]['unit']):
                raise ValueError('Native unit changed')
            initial(x[key], y[key], key)
    with h5py.File(baseline/'registered_states.mat') as a, h5py.File(registered) as b:
        x, y = named_rows(a,a['observation']['states']), named_rows(b,b['observation']['states'])
        if set(x) != set(y) or len(y) != 73:
            raise ValueError('Registered state coverage changed')
        for key in x:
            initial(x[key], y[key], key)
    command_file = probe/'command_profiles.mat'
    with h5py.File(command_file) as f:
        commands = {name: check_period(row['time_s'][:], row['values'][:]) for name,row in f['commands'].items()}
    passed = all(r['pass_endpoint_match'] for r in comparisons)
    return dict(schema='heatdrive_ecc_c201_horizon_v1', audit_pass=passed, source=source,
                strict_horizon_restore_pass=True, inherited_initial_comparison_groups=len(comparisons),
                failed_initial_comparison_groups=sum(not r['pass_endpoint_match'] for r in comparisons),
                maximum_initial_difference=max(r['max_abs_error'] for r in comparisons),
                comparisons=comparisons, command_periods=commands, full_cycle_verified=False,
                whole_model_first_law_verified=False, new_model_recovery_allowed=False, table4_reproduction_claim=False,
                input_sha256={p.name:sha256(p) for p in (raw,registered,command_file,meta_path)})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite evidence')
    result = audit(args.repo)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('comparisons','input_sha256')},indent=2))
    if not result['audit_pass']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
