"""Read a bounded tail from frozen v7.3 physical data for offline gate tests."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np
from scipy.io import savemat

from Audit_HeatDriveECC_NativeWindowLedger import validate_grid
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field


def read_field(file, item, total_samples, selection):
    kind = item.attrs.get("MATLAB_class")
    if isinstance(item, h5py.Group) and kind == b"struct":
        return {name: read_field(file, child, total_samples, selection) for name, child in item.items()}
    if kind == b"char":
        return text_field(item)
    if kind == b"cell":
        values = np.empty(item.shape[::-1], dtype=object)
        for index, ref in enumerate(item[:].T.reshape(-1)):
            values.flat[index] = text_field(file[ref])
        return values
    if kind not in (b"double", b"logical") or item.ndim != 2:
        raise ValueError("Unsupported physical field representation")
    if item.shape[1] == total_samples:
        return item[:, selection].T
    if item.shape == (1, 1):
        return item[:].T.astype(bool) if kind == b"logical" else item[:].T
    raise ValueError("Unknown physical array layout")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cycles", type=int, default=1)
    args = parser.parse_args()
    if args.output.exists() or args.cycles not in (1, 2):
        raise ValueError("Use a new file and one/two complete tail cycles")
    contract = json.loads(args.contract.read_text(encoding="utf-8-sig"))
    path = args.contract.parent.parent / contract["result_relative_path"]
    digest = sha256(path)
    if digest != contract["result_sha256"]:
        raise ValueError("Frozen result hash changed")
    with h5py.File(path, "r") as file:
        tau = float(file["options/schedule/tau_cycle_s"][0, 0])
        dt = float(file["options/simulation/fixed_step_s"][0, 0])
        group = file["physical"]
        total = group["time_s"].shape[1]
        count = round(args.cycles * tau / dt) + 1
        if count > total:
            raise ValueError("Incomplete source history")
        selection = slice(total - count, total)
        physical = {name: read_field(file, item, total, selection) for name, item in group.items()
                    if not ((name.startswith("U_") or name.startswith("M_")) and "inventory" in name)}
    time = physical["time_s"].reshape(-1)
    validate_grid(time, time[-1] - args.cycles * tau, time[-1], dt)
    metadata = dict(source_result_sha256=digest, source_result_path=str(path.resolve()),
                    start_s=float(time[0]), stop_s=float(time[-1]), sample_count=count,
                    simulation_executed=False, production_recovery_allowed=False,
                    legacy_inventory_fields_excluded=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    savemat(args.output, dict(physical=physical, slice_metadata=metadata), long_field_names=True, do_compression=True)
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    main()
