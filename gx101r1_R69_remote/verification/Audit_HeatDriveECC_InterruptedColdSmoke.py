"""Audit an interrupted cold smoke package without promoting it to physics evidence."""
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
    return h.hexdigest()


def audit(root: Path) -> dict:
    required = [
        'matlab_diary.log',
        'native/observations.mat',
        'native/configuration.mat',
        'native/inventory_metadata.json',
        'native/tl_connectivity.json',
        'native/thermal_connectivity.json',
        'conservative/configuration.mat',
    ]
    present = {name: (root / name).is_file() for name in required}
    forbidden = ['record.mat', 'checkpoint.mat', 'final_operating_point.mat',
                 'cold_chamber_execution.json']
    forbidden_present = {name: (root / name).is_file() for name in forbidden}
    hashes = {name: digest(root / name) for name, ok in present.items() if ok}
    return {
        'schema': 'heatdrive_ecc_interrupted_cold_smoke_audit_v1',
        'root': str(root),
        'package_exists': root.is_dir(),
        'required_files_present': present,
        'forbidden_promotion_files_present': forbidden_present,
        'checkpoint_saved': False,
        'production_recovery_allowed': False,
        'periodic_steady_state': False,
        'full_device_first_law_verified': False,
        'table4_reproduction_claim': False,
        'interrupted_before_complete_trajectory': True,
        'input_sha256': hashes,
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output-root', required=True, type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = audit(args.output_root.resolve())
    text = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.output:
        if args.output.exists():
            raise FileExistsError('Never overwrite evidence')
        args.output.write_text(text, encoding='utf-8')
    print(text, end='')
