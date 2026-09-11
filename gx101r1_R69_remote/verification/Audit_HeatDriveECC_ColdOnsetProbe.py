"""Audit the independent cold onset probe without promoting it to recovery evidence."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest().upper()


def audit(root: Path) -> dict:
    execution_path = root / 'cold_chamber_execution.json'
    if not execution_path.is_file():
        raise FileNotFoundError(execution_path)
    execution = json.loads(execution_path.read_text(encoding='utf-8'))
    required = [
        'cold_chamber_execution.json',
        'native/observations.mat',
        'native/configuration.mat',
        'native/inventory_metadata.json',
        'native/tl_connectivity.json',
        'native/thermal_connectivity.json',
        'conservative/observations.mat',
        'conservative/configuration.mat',
        'conservative/compiled_inventory_tags.json',
    ]
    present = {name: (root / name).is_file() for name in required}
    forbidden = ['record.mat', 'checkpoint.mat', 'final_operating_point.mat']
    forbidden_present = {name: (root / name).is_file() for name in forbidden}
    cases = execution.get('cases', [])
    case_hashes = {
        case['arm']: case['observation_sha256'].upper()
        for case in cases
        if 'arm' in case and 'observation_sha256' in case
    }
    observed_hashes = {
        arm: digest(root / arm / 'observations.mat')
        for arm in ('native', 'conservative')
        if (root / arm / 'observations.mat').is_file()
    }
    hashes_match = case_hashes == observed_hashes and len(observed_hashes) == 2
    collection_pass = bool(
        execution.get('collection_pass') is True
        and execution.get('stop_time_s') == 0.2
        and execution.get('diagnostic_simulation_mode') == 'normal'
        and execution.get('c200_state_imported') is False
        and execution.get('production_recovery_allowed') is False
        and execution.get('periodic_steady_state') is False
        and execution.get('checkpoint_saved') is False
        and execution.get('full_device_first_law_verified') is False
        and execution.get('table4_reproduction_claim') is False
        and all(present.values())
        and not any(forbidden_present.values())
        and hashes_match
    )
    return {
        'schema': 'heatdrive_ecc_cold_onset_probe_audit_v1',
        'root': str(root),
        'package_exists': root.is_dir(),
        'required_files_present': present,
        'forbidden_promotion_files_present': forbidden_present,
        'execution_collection_pass': execution.get('collection_pass') is True,
        'case_count': len(cases),
        'case_hashes': case_hashes,
        'observed_hashes': observed_hashes,
        'observation_hashes_match': hashes_match,
        'diagnostic_network_absolute_pressure_MPa': execution.get(
            'diagnostic_network_absolute_pressure_MPa'),
        'cold_onset_probe_pass': collection_pass,
        'periodic_steady_state': False,
        'full_device_first_law_verified': False,
        'table4_reproduction_claim': False,
        'production_recovery_allowed': False,
        'promotion_blocked_by_design': True,
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output-root', required=True, type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = audit(args.output_root.resolve())
    if args.output:
        if args.output.exists():
            raise FileExistsError('Never overwrite evidence')
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False, indent=2))
