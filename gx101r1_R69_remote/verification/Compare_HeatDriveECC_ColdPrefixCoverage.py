"""Verify saved short selected observations are covered exactly by saved C1.

Numeric prefix equality is NOT byte duplication of JSON and MAT files, not
equality of unobserved state, and not permission to delete any other data.
This program only writes a coverage/retirement-candidate receipt.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from scipy.io import loadmat

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Run_HeatDriveECC_ConservativeTransport import write_json


def equal_prefix(a, b):
    a, b = np.asarray(a), np.asarray(b)
    return a.ndim == b.ndim and a.shape[1:] == b.shape[1:] and b.shape[0] >= a.shape[0] and np.array_equal(a, b[:len(a)])


def compare_raw(prefix, full):
    keys = lambda r: {(s["block_path"],s["state_name"]):s for s in r["series"]}
    a, b = keys(prefix), keys(full)
    if set(a) != set(b) or len(a) != len(prefix["series"]) or len(b) != len(full["series"]):
        raise ValueError("Selected physical coordinates differ")
    for key, row in a.items():
        target = b[key]
        if row["unit"] != target["unit"] or not equal_prefix(row["time_s"],target["time_s"]) or not equal_prefix(row["values"],target["values"]):
            raise ValueError("Short physical observation is not an exact saved prefix")
    if not equal_prefix(prefix["tout_s"],full["tout_s"]):
        raise ValueError("Actual simulation clock differs")
    for name, trace in {"constitutive":prefix["constitutive_output"],**prefix.get("gate_commands",{})}.items():
        target = full["constitutive_output"] if name == "constitutive" else full["gate_commands"][name]
        if not equal_prefix(trace["time"],target["time"]) or not equal_prefix(trace["signals"]["values"],target["signals"]["values"]):
            raise ValueError("Constitutive or actual control samples differ")
    return len(a)


def compare(prefix_root, full_root):
    a, b = (json.loads((p/"cold_initial_execution.json").read_text(encoding="utf-8")) for p in (prefix_root,full_root))
    if not (a["collection_complete"] and b["collection_complete"] and a["stop_time_s"]==.2 and b["stop_time_s"]==10):
        raise ValueError("Require a completed 0.2 s probe and complete cold C1")
    if a["input_dependencies"]["configuration_sha256"] != b["input_dependencies"]["configuration_sha256"] or a["hydraulic_storage_variant"] != b["hydraulic_storage_variant"]:
        raise ValueError("Constructor parameter variant differs")
    rows=[]
    for arm in ("dual","shared"):
        short = prefix_root/arm/"selected_observations.json"
        long = full_root/arm/"selected_observations.mat"
        ca, cb = (next(r for r in ex["completed_arms"] if r["arm"]==arm) for ex in (a,b))
        if sha256(short)!=ca["raw_sha256"] or sha256(long)!=cb["raw_sha256"]:
            raise ValueError("Saved observations do not match their producer markers")
        count=compare_raw(json.loads(short.read_text(encoding="utf-8")),loadmat(long,simplify_cells=True)["traces"])
        rows.append({"arm":arm,"candidate_path":str(short),"candidate_sha256":sha256(short),"candidate_bytes":short.stat().st_size,
                     "retained_full_raw":str(long),"retained_full_raw_sha256":sha256(long),
                     "exact_physical_prefix_series":count,"actual_clock_constitutive_and_recorded_gate_prefix_equal":True})
    return {"schema":"heatdrive_ecc_exact_selected_prefix_coverage_v1","reader_sha256":sha256(Path(__file__)),
            "candidates":rows,"byte_duplicate_files":False,"data_prefix_covered_exactly":True,
            "unobserved_state_equality_claimed":False,"latest_full_cycle_raw_must_be_kept":True,
            "earlier_summary_markers_preflight_and_logs_must_be_kept":True,"automatic_deletion_performed":False}


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--prefix",type=Path,required=True);p.add_argument("--full",type=Path,required=True)
    p.add_argument("--receipt",type=Path,required=True)
    args=p.parse_args();result=compare(args.prefix.resolve(),args.full.resolve())
    write_json(args.receipt.resolve(),result)
    print(json.dumps({"exact_prefix_coverage":True,"candidate_bytes":sum(r["candidate_bytes"] for r in result["candidates"]),"deletion_performed":False}))
