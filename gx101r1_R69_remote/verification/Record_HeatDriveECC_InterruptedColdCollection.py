"""Retain terminal interruption evidence without classifying a physics failure."""
import argparse
import hashlib
import json
from pathlib import Path


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest().upper()


def record(root, output, exit_code):
    assert exit_code != 0 and not output.exists()
    assert not (root / 'cold_chamber_execution.json').exists()
    arm = root / 'native'
    mechanism = json.loads((arm / 'cold_mechanism_audit.json').read_text(encoding='utf-8'))
    assert mechanism['mechanism_pass'] and all(mechanism['checks'].values())
    assert not mechanism['full_native_inventory_ledger_evaluated']
    observation = arm / 'cold_mechanism_observation.mat'
    assert digest(observation) == mechanism['observation_sha256']
    files = ['cold_mechanism_observation.mat', 'cold_mechanism_audit.json',
             'diagnostic_complete_operating_point.mat', 'diagnostic_state_observation.mat',
             'diagnostic_state_capture.json', 'public_observations.mat', 'configuration.mat',
             'postprocessing_progress.json']
    evidence = {name: {'sha256': digest(arm / name), 'bytes': (arm / name).stat().st_size}
                for name in files}
    result = {'schema': 'heatdrive_ecc_interrupted_cold_collection_v1',
              'root': str(root), 'observed_terminal_exit_code': exit_code,
              'observed_terminal_exit_hex': hex(exit_code & 0xffffffff),
              'exit_cause_proven': False, 'execution_commit': mechanism['execution_commit'],
              'mechanism_pass': True, 'mechanism_count': len(mechanism['checks']),
              'directional_pressure_pass': mechanism['directional_pressure_observation']['pass'],
              'full_collection_pass': False, 'full_native_ledger_pass': False,
              'complete_state_restore_qualified': False,
              'scientific_failure_inferred_from_exit': False, 'evidence': evidence,
              'production_recovery_allowed': False, 'diagnostic_continuation_allowed': False}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2, ensure_ascii=True) + '\n', encoding='utf-8')
    marker = root / 'INCOMPLETE_DO_NOT_RESUME.json'
    assert not marker.exists()
    marker.write_text(json.dumps(result, indent=2, ensure_ascii=True) + '\n', encoding='utf-8')
    print(json.dumps({'mechanism_pass': True, 'collection_pass': False,
                      'exit_cause_proven': False, 'receipt': str(output)}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--exit-code', type=int, required=True)
    args = parser.parse_args()
    record(args.root.resolve(), args.output.resolve(), args.exit_code)
