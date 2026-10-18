"""Seal bounded cold implementation comparisons, not new sensitivity or recovery seeds."""
import argparse
from pathlib import Path
import shutil

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Close_HeatDriveECC_SensitivityColdCase import write
from Close_HeatDriveECC_SplitObservation import read, validate_gate, validate_comparison, compact_evidence
from Verify_HeatDriveECC_ObservationPacket import validate_manifest


def close(experiments, offline, preflight, launcher_prefix, output):
    repo = Path(__file__).resolve().parents[1]
    output = output.resolve()
    if output.exists() or output.parent != repo / 'outputs_storage_audit':
        raise ValueError('Require a fresh archive in the calling repository')
    tested = read(offline)
    if (tested['schema'] != 'heatdrive_ecc_stable_kernel_candidate_comparison_v1'
            or not tested['all_captured_samples_bitwise_equal']
            or not tested['all_original_L8_option_cases_bitwise_equal']
            or tested['error_message'] or tested['coupled_acceleration_qualified']
            or sha256(repo / 'verification/HeatDriveECC_StableKernelCandidate.m') != tested['candidate_source_sha256']):
        raise ValueError('Changed or failed offline implementation evidence')
    tests = read(preflight / 'preflight_tests.json')
    if tests['positive_requests'] != 2 or tests['negative_requests_rejected'] != 9 or tests['operating_point_loaded']:
        raise ValueError('Missing bounded request tests')
    if len(experiments) != 2:
        raise ValueError('Require original nominal and row one cold comparisons')
    records = []
    protected = {}
    for root in experiments:
        root = root.resolve()
        result_path = root / 'native/kernel_cold_comparison/kernel_cold_comparison.json'
        r = read(result_path)
        if (r['schema'] != 'heatdrive_ecc_kernel_cold_comparison_v1' or not r['pass']
                or not r['all_trajectory_arrays_bitwise_equal'] or not r['all_original_packet_gates_pass']
                or r['error_message'] or r['source_OP_imported'] or r['twenty_cycle_seed_qualified']
                or r['complete_state_restore_equivalence_evaluated']
                or r['kernel_qualification_sha256'] != sha256(offline)):
            raise ValueError('Incomplete cold comparison')
        packet = Path(r['comparison_packet'])
        if not (packet / 'COMPARISON_ONLY_DO_NOT_RESUME.json').is_file():
            raise ValueError('Comparison state has no non-propagation marker')
        comparison_path = result_path.parent / 'trajectory_comparison.json'
        comparison = read(comparison_path)
        validate_comparison(comparison)
        for group in ('states', 'native', 'sources', 'public'):
            if any(row['start_s'] != 0 or row['end_s'] != 20 or row['sample_count'] != 20001
                   for row in comparison[group]['traces']):
                raise ValueError('Incomplete actual coupled clock')
        for p in (packet, Path(r['reference_packet'])):
            manifest = read(p / 'packet_manifest.json')
            gate = read(p / 'packet_gate.json')
            validate_manifest(manifest)
            validate_gate(gate)
            if manifest['window_s'] != [0, 20] or gate['input_sha256']['manifest'] != sha256(p / 'packet_manifest.json'):
                raise ValueError('Changed physical window or gate')
            for item in manifest['input_files']:
                path = (p / item['path']).resolve()
                if not path.is_relative_to(p.resolve()) or sha256(path) != item['sha256']:
                    raise ValueError('Changed comparison input')
                protected[str(path)] = item['sha256']
        records.append(dict(case_index=r['case_index'],producer=r['producer'],result_path=str(result_path),
            result_sha256=sha256(result_path),trajectory_comparison_sha256=sha256(comparison_path),
            pass_all_original_gates=True,all_actual_arrays_bitwise_equal=True,window_s=[0,20],
            candidate_timing=r['candidate_simulation_timing'],historical_reference_timing=r['historical_reference_simulation_timing']))
    if sorted(r['case_index'] for r in records) != [0, 1]:
        raise ValueError('Missing original control or first factor case')
    output.mkdir()
    copies = []
    inventory = []
    for label, root in [(f'case_{k}', p) for k,p in enumerate(experiments)] + [('preflight', preflight)]:
        for path in sorted(root.rglob('*')):
            if not path.is_file():
                continue
            rel = path.relative_to(root)
            size = path.stat().st_size
            row = dict(path=str(path),bytes=size,sha256=sha256(path))
            cache = bool({'cache','codegen','component_build','buffer_component_build'}.intersection(rel.parts))
            if not cache and compact_evidence(path,size):
                target = output / label / rel
                target.parent.mkdir(parents=True,exist_ok=True)
                shutil.copyfile(path,target)
                if sha256(target) != row['sha256']:
                    raise ValueError('Compact copy changed')
                copies.append(dict(**row,archive_relative=str(target.relative_to(output))))
            else:
                inventory.append(dict(**row,classification='regenerable_cache' if cache else 'bounded_comparison_raw_or_constructor_dependency',
                                      action='retain_single_execution_copy'))
    prefixes = [launcher_prefix] + experiments
    for prefix in prefixes:
        for suffix in ('.preflight_config.json','.stdout.log','.stderr.log','.matlab.log'):
            path = Path(str(prefix)+suffix)
            if path.exists():
                target = output / path.name
                shutil.copyfile(path,target)
                copies.append(dict(path=str(path),bytes=path.stat().st_size,sha256=sha256(path),archive_relative=path.name))
    summary = dict(schema='heatdrive_ecc_kernel_cold_comparison_closeout_v1',offline_sha256=sha256(offline),
        sampled_kernel_speedup=tested['sampled_kernel_speedup'],records=records,
        coupled_cold_trajectory_equivalence_verified=True,replay_physical_cycles=4,
        new_completed_sensitivity_cases=0,strict_candidate_state_restore_equivalence_verified=False,
        long_chain_candidate_backend_admitted=False,whole_pipeline_speedup_established=False,
        timing_is_contemporaneous_paired_benchmark=False,production_recovery_allowed=False,table4_reproduction_claim=False)
    write(output/'kernel_cold_closeout.json',summary)
    write(output/'storage_receipt.json',dict(compact_copies=copies,retained_single_execution_files=inventory,
        protected_comparison_inputs=protected,compact_copied_bytes=sum(r['bytes'] for r in copies),
        retained_single_execution_bytes=sum(r['bytes'] for r in inventory),raw_deleted_bytes=0))
    return dict(summary_sha256=sha256(output/'kernel_cold_closeout.json'),cases=2,replay_cycles=4,
        compact_copied_bytes=sum(r['bytes'] for r in copies),retained_single_execution_bytes=sum(r['bytes'] for r in inventory))


if __name__ == '__main__':
    import json
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--experiments',type=Path,nargs=2,required=True)
    for key in ('offline','preflight','launcher-prefix','output'):
        p.add_argument('--'+key,type=Path,required=True)
    print(json.dumps(close(**vars(p.parse_args())),indent=2))
