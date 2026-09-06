"""Compute an equation-matched diagnostic ledger from one complete native cycle."""
import argparse
import json
from pathlib import Path

from Audit_HeatDriveECC_NativeWindowLedger import NativeWindowLedger
from Audit_HeatDriveECC_NativeWindowPackets import load_packet
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("packet", "topology", "probe", "metadata", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Do not overwrite a native cycle ledger")
    inputs = {n: getattr(args, n) for n in ("topology", "probe", "metadata")}
    ledger = NativeWindowLedger(*(json.loads(p.read_text(encoding="utf-8-sig")) for p in inputs.values()))
    header, streams = load_packet(args.packet)
    if any(header[key] != value for key, value in ledger.source.items()):
        raise ValueError("Packet and model metadata source mismatch")
    duration = header["stop_s"] - header["start_s"]
    if abs(duration - header["cycle_period_s"]) > 1e-10:
        raise ValueError("Require exactly one complete native cycle")
    result = ledger.evaluate(streams["native"], header["start_s"], header["stop_s"], header["fixed_step_s"])
    result["input_sha256"] = {name: sha256(path) for name, path in inputs.items()}
    result["packet_sha256"] = sha256(args.packet)
    result["one_cycle_native_coverage_verified"] = True
    result["mechanism_verified_by_ledger"] = False
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k != "components"}, indent=2))


if __name__ == "__main__":
    main()
