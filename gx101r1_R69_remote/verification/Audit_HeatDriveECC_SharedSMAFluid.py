"""Independent exact wire-partition review of the shared native SMA constructor.

This cannot prove compilation, cold initialization, switch continuity or physics.
Only three explicit liquid-net joins and declared cooling block removals are
allowed. All other surviving liquid/thermal wire partitions must be identical.
"""
import argparse
import json
from pathlib import Path
import re

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_SMAFlowCoordinates import liquid_wire_labels
from Run_HeatDriveECC_ConservativeTransport import write_json


def partition(topology, surviving=None, extra_edges=()):
    keys = [v["key"] for v in topology["vertices"]]
    if len(keys) != len(set(keys)):
        raise ValueError("Duplicate typed physical coordinate")
    keep = set(keys) if surviving is None else set(surviving)
    if not keep <= set(keys):
        raise ValueError("Missing retained typed physical coordinate")
    parent = {k: k for k in keep}

    def find(k):
        while k != parent[k]:
            parent[k] = parent[parent[k]]
            k = parent[k]
        return k

    def join(a, b):
        parent[find(a)] = find(b)

    for e in topology["edges"]:
        if e["kind"] not in {"physical_wire_net", "hierarchy_connector"}:
            raise ValueError("Unexpected inferred primitive-internal edge")
        a, b = keys[e["a"]-1], keys[e["b"]-1]
        if a in keep and b in keep:
            join(a, b)
    for a, b in extra_edges:
        if a not in keep or b not in keep:
            raise ValueError("Declared intervention references missing coordinate")
        join(a, b)
    groups = {}
    for k in keep:
        groups.setdefault(find(k), set()).add(k)
    return {frozenset(g) for g in groups.values()}


def require_partition(before, after, removed_pattern, joins=()):
    old = {v["key"] for v in before["vertices"]}
    removed = {k for k in old if re.search(removed_pattern, k.split(":")[0])}
    keep = old-removed
    if {v["key"] for v in after["vertices"]} != keep:
        raise ValueError("Unexpected physical vertex removal/addition")
    if partition(before, keep, joins) != partition(after):
        raise ValueError("Undeclared surviving physical-wire partition change")
    return len(removed)


def review(folder):
    names = ("construction_execution.json", "before_tl.json", "before_thermal.json", "after_tl.json", "after_thermal.json")
    data = {n: json.loads((folder/n).read_text(encoding="utf-8")) for n in names}
    execution = data[names[0]]
    if not execution["construction_complete"] or execution["simulated"] or execution["compiled"] or execution["checkpoint_loaded"]:
        raise ValueError("Not the scoped cold constructor-only diagnostic")
    before, after = data["before_tl.json"], data["after_tl.json"]
    liquid_wire_labels(before)
    liquid_wire_labels(after)  # Also validate actual typed PortConnectivity and two fluid-property domains.
    roots = {v["key"].split("/")[0] for v in before["vertices"]}
    if len(roots) != 1:
        raise ValueError("Ambiguous model root")
    model = next(iter(roots))
    sma = model+"/SMA/"
    joins = ((sma+"HoldPipe_001:A", sma+"Conn3:port"),
             (sma+"HoldPipe_021:B", sma+"Conn4:port"),
             (sma+"HoldPipe_011:B", sma+"SMACooldownPipeNode11FluidTempSensor:A"))
    liquid_removed = require_partition(before, after, r"/SMA/CooldownPipe_\d{3}$", joins)
    thermal_removed = require_partition(data["before_thermal.json"], data["after_thermal.json"],
        r"/SMA/(?:CooldownPipe_\d{3}|CooldownThermalGate_\d{3}|SMACooldownNode\d{2}HeatFlowSensor)$")
    if (liquid_removed, thermal_removed) != (42, 105):
        raise ValueError("Wrong cooling representation removal count")
    change = execution["intervention"]
    pipes = change["retained_pipe_parameters"]
    if len(pipes) != 21 or any(p["block"] != sma+"HoldPipe_%03d" % i for i, p in enumerate(pipes, 1)):
        raise ValueError("Missing retained physical SMA pipe coordinate")
    blocks = set(execution["retained_SMA_blocks"])
    if any(re.search(r"/(?:CooldownPipe_\d{3}|CooldownThermalGate_\d{3}|ToWorkspace_sma_cooldown_node\d{2}_heatflow_W)$", b) for b in blocks):
        raise ValueError("Duplicate cooling storage or fabricated retired heat-flow output")
    sources = [sma+n for n in ("HoldThermalGateCommandFromWorkspace", "CooldownThermalGateCommandFromWorkspace", "SharedSMAActiveThermalGate")]
    if execution["actual_gate_input_sources"] != sources or execution["actual_gate_function"] != "max":
        raise ValueError("Shared gate is not driven by both original route commands")
    if execution["gate_command_variables"] != ["SMA_hold_pipe_to_sma_G_command", "SMA_cooldown_pipe_to_sma_G_command"]:
        raise ValueError("Original thermal command contract was replaced")
    return {"schema": "heatdrive_ecc_shared_SMA_wire_review_v1", "execution_commit": execution["execution_commit"],
            "input_dependencies": [{"path": str(folder/n), "sha256": sha256(folder/n)} for n in names],
            "reader_sha256": sha256(Path(__file__)),
            "exact_liquid_partition_intervention_pass": True, "all_surviving_thermal_wire_partitions_unchanged": True,
            "retired_liquid_typed_vertices": liquid_removed, "retired_thermal_typed_vertices": thermal_removed,
            "retained_SMA_fluid_pipe_count": 21, "single_bed_volume_m3": change["single_bed_volume_m3"],
            "actual_both_route_gate_inputs_verified": True, "geometry_and_initial_expressions_held_by_applicator": True,
            "compiled_inventory_state_count_verified": False, "switch_continuity_or_energy_balance_proven": False,
            "cold_initialization_or_mechanism_qualified": False, "C200_inventory_or_causal_attribution": False,
            "production_recovery_or_twenty_cycle_seed_allowed": False,
            "next_action": "New native cold initialization and small observable switch test; never load old OP"}


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--root", required=True, type=Path)
    p.add_argument("--output", required=True, type=Path)
    a = p.parse_args()
    result = review(a.root.resolve())
    a.output.mkdir(parents=True, exist_ok=False)
    write_json(a.output/"shared_SMA_wire_review.json", result)
    print(json.dumps(result, allow_nan=False))
