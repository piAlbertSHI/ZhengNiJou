"""Check preserved-lag initialization without promoting a failed trajectory."""
import argparse
import csv
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_AdvancedSeedControl import public_rows
from Audit_HeatDriveECC_C200RestoredSignals import compare
from Audit_HeatDriveECC_OPAPIIsolation import require
from Audit_HeatDriveECC_OneSecondTransfer import compare_trace, compute as previous_compute, seal_and_verify
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field
from Audit_HeatDriveECC_TargetInitialization import rows


def identical_traces(left, right):
    require(set(left) == set(right), 'Incomplete variant coverage')
    return all(left[k][0] == right[k][0] and np.array_equal(left[k][1], right[k][1])
               and np.array_equal(left[k][2], right[k][2]) for k in left)


def compute(repo):
    base = repo / 'outputs_storage_audit'; root = base / 'native_lag_one_second_transfer_20260908'
    previous_root = base / 'one_second_public_transfer_20260908'
    previous_path = previous_root / 'independent_one_second_audit.json'
    previous = previous_compute(repo)
    require(json.loads(previous_path.read_text(encoding='utf-8')) == previous, 'Prior rejection evidence changed')
    path = root / 'public_snapshot_control.json'; meta = json.loads(path.read_text(encoding='utf-8-sig'))
    require(meta['execution_commit'] == '07a0c7ad2f7b0d265323ccdedb910d665376da75'
            and meta['computation_complete'] is True and meta['error_message'] == ''
            and meta['seed_source'] == 'advanced_native_lag_bootstrap'
            and meta['window_mode'] == 'one_second_complete_only'
            and meta['start_time_s'] == 2000.001 and meta['stop_time_s'] == 2001.001, 'Wrong producer or window')
    require(all(meta[k] is False for k in ('production_recovery_allowed','source_physical_model_changed',
                'controller_representation_changed','source_op_edited','final_checkpoint_saved','anonymous_indices_edited',
                'command_horizon_extended')) and meta['boundary_sample_hold_diagnostic'] is True
            and meta['bootstrap_operating_point_not_recovery'] is True and meta['bootstrap_public_lag_groups'] == 2,
            'Model or bootstrap scope changed')
    require(len(meta['controller_initial_conditions']) == 12 and all(r['canonical_replacement'] is False
            for r in meta['controller_initial_conditions']), 'Controller blocks replaced')
    require(meta['seed_target_pass'] is True and len(meta['seed_matches']) == 196
            and len({r['path'] for r in meta['seed_matches']}) == 196
            and meta['seed_target_comparison'] == 'initial_sample_before_advance'
            and meta['seed_initial_time_s'] == 2000 and meta['seed_snapshot_time_s'] == 2000.001,
            'Incomplete final seed qualification')
    native = {}
    with h5py.File(root / 'seed_native.mat') as handle:
        for ref in handle['seed_native'][:].flat:
            row = handle[ref]; key = text_field(row['block_path']) + '/' + text_field(row['state_name'])
            require(key not in native, 'Duplicate native seed row')
            native[key] = (text_field(row['unit']), row['time_s'][:].reshape(-1), row['values'][:])
    require(len(native) == 1240, 'Incomplete physical inventory')
    strict_path = base / 'c200_two_step_snapshot_20260908/restored_step_signals.mat'; strict = rows(strict_path)
    for target in meta['seed_matches']:
        key = 'heatdrive_ecc_coupled_se21/' + target['path']; unit, time, value = native[key]
        expected = strict['native/' + key]
        require(unit == target['unit'] == expected[0] and np.array_equal(time,[2000,2000.001])
                and float(value[...,0].item()) == target['actual'] and float(expected[2][...,1].item()) == target['expected']
                and target['pass'] is True and compare([target['actual']],[target['expected']])['pass_endpoint_match'],
                'Seed target or provenance changed')
    donor_path = previous_root / 'reference/untouched_input_public_states.mat'; donor = public_rows(donor_path,'observation')
    before_path = root / 'bootstrap_before_public_states.mat'; after_path = root / 'bootstrap_after_public_states.mat'
    before = public_rows(before_path,'observation'); after = public_rows(after_path,'observation')
    require(len(before) == 73 and set(before) == set(after) == set(donor), 'Incomplete bootstrap groups')
    changed = []
    for key in before:
        require(before[key][0] == after[key][0] and np.array_equal(before[key][1],[2000])
                and np.array_equal(before[key][1],after[key][1]), 'Bootstrap timestamps or units changed')
        is_lag = '/PressurePI_ErrorLag/' in key or '/SMAPressurePI_ErrorLag/' in key
        if is_lag:
            require(after[key][2].size == 1 and np.array_equal(after[key][2],donor[key][2]), 'Wrong scalar lag import')
            changed.append(key)
        else:
            require(np.array_equal(before[key][2],after[key][2]), 'Unrelated bootstrap state edited')
    require(len(changed) == 2, 'Wrong bootstrap edit coverage')
    input_path = root / 'whole_snapshot_input_public_states.mat'
    require(identical_traces(donor,public_rows(input_path,'input_snapshot')), 'Complete donor import changed')
    raw = root / 'whole_snapshot_observations.mat'
    require(len(meta['cases']) == 1 and meta['cases'][0]['arm'] == 'whole_snapshot'
            and meta['cases'][0]['copied_public_groups'] == 73 and meta['cases'][0]['whole_solver_groups'] == 1
            and sha256(raw) == meta['cases'][0]['observation_sha256'], 'Observation provenance changed')
    actual = rows(raw); reference_path = previous_root / 'reference/untouched_observations.mat'
    alternative_path = previous_root / 'candidate/whole_snapshot_observations.mat'
    reference = rows(reference_path); alternative = rows(alternative_path)
    same = identical_traces(actual,alternative)
    require(len(actual) == 1474 and all(v[1].size == 1001 for v in actual.values()), 'Wrong observation coverage')
    comparisons = [dict(key=k, **compare_trace(reference[k],actual[k])) for k in reference]
    lag_root = base / 'lag_accelerator_equivalence_20260908'; lag_path = lag_root / 'lag_equivalence.json'
    lag = json.loads(lag_path.read_text(encoding='utf-8-sig'))
    require(lag['execution_commit'] == 'a4040bc3eec700ef988bdcfb7c899bd0daac3816'
            and lag['simulation_mode'] == 'accelerator' and lag['samples'] == 101
            and lag['state_max_difference'] == lag['output_max_difference'] == 0
            and lag['production_recovery_allowed'] is False, 'Wrong accelerator control')
    with h5py.File(lag_root / 'equivalence_traces.mat') as handle:
        require(handle['time_s'].size == 101 and np.array_equal(handle['transfer'][:],handle['state_space'][:]),
                'Accelerator output equivalence changed')
    diary = root / 'matlab_diary.log'
    warning_seen = 'First solve for initial conditions failed to converge' in diary.read_text(encoding='utf-8-sig',errors='replace')
    require(warning_seen, 'Bootstrap warning evidence changed')
    paths = [path,raw,input_path,before_path,after_path,root/'seed_native.mat',root/'seed_public_states.mat',
             root/'control_inputs.mat',diary,previous_path,donor_path,reference_path,alternative_path,strict_path,
             lag_path,lag_root/'equivalence_traces.mat']
    return dict(schema='heatdrive_ecc_native_lag_transfer_v1',execution_commit=meta['execution_commit'],
                accelerator_isolated_output_bitwise_equal=True,bootstrap_only_two_named_lag_states_edited=True,
                bootstrap_automatic_priority_fallback_warning=True,seed_initial_targets_verified=196,
                copied_public_groups_exact=73,observation_group_count=1474,samples_per_group=1001,
                native_lag_and_replaced_lag_trajectories_bitwise_equal=same,
                time_grid_failed_groups=sum(not r['exact_grid_pass'] for r in comparisons),
                common_timestamp_value_failed_groups=sum(not r['common_timestamp_values_pass'] for r in comparisons),
                whole_window_transfer_pass=all(r['full_transfer_pass'] for r in comparisons),
                production_recovery_allowed=False,full_device_first_law_verified=False,
                comparisons=comparisons,input_sha256={str(p.relative_to(repo)):sha256(p) for p in paths})


def main():
    parser=argparse.ArgumentParser(description=__doc__); mode=parser.add_mutually_exclusive_group()
    mode.add_argument('--create',action='store_true'); mode.add_argument('--seal',action='store_true'); args=parser.parse_args()
    repo=Path(__file__).resolve().parents[1]; root=repo/'outputs_storage_audit/native_lag_one_second_transfer_20260908'
    result=compute(repo); path=root/'independent_one_second_audit.json'; table=root/'comparison_by_group.csv'
    if args.create:
        require(not path.exists() and not table.exists(),'Do not overwrite evidence')
        path.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
        with table.open('w',encoding='utf-8',newline='') as stream:
            writer=csv.DictWriter(stream,fieldnames=list(result['comparisons'][0]));writer.writeheader();writer.writerows(result['comparisons'])
    require(json.loads(path.read_text(encoding='utf-8'))==result,'Independent evidence changed')
    with table.open(encoding='utf-8',newline='') as stream: actual=list(csv.DictReader(stream))
    require(actual==[{k:'' if v is None else str(v) for k,v in r.items()} for r in result['comparisons']],'CSV changed')
    seal_and_verify(repo,root,result,args.seal,
        note_relative='项目文档/研究笔记/2026-09-08_原滤波器保留对照与初始化警告.md',extra_paths=[])
    print(json.dumps({k:v for k,v in result.items() if k not in ('comparisons','input_sha256')},indent=2))
    if not result['whole_window_transfer_pass']:raise SystemExit(1)


if __name__=='__main__':main()
