"""Read saved typed ports, solid attachments and signed SMA route measurements.

No active model inspection/rebuild or hydraulic qualification. Snapshot/flow
association is the retained arm contract, not a claim about current dirty SLX.
"""
import json
from pathlib import Path

import h5py
import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_ThermalConnectivity import wire_nets
from Audit_HeatDriveECC_TLDomainInventory import resolve_domains, as_list


def liquid_wire_labels(topology):
    resolve_domains(topology)  # Registered primitives, ownership, two property networks.
    vertices = topology["vertices"]
    pairs = [(e["a"]-1, e["b"]-1) for e in topology["edges"]]
    matrix = coo_matrix((np.ones(len(pairs)), np.asarray(pairs).T), shape=(len(vertices), len(vertices)))
    _, labels = connected_components(matrix, directed=False)
    expected = {tuple(sorted((e["a"], e["b"]))) for e in topology["edges"] if e["kind"] == "physical_wire_net"}
    actual = set()
    seen = set()
    for row in topology["port_connectivity"]:
        a = row["vertex_index"]
        if a in seen or not 1 <= a <= len(vertices):
            raise ValueError("Invalid or duplicated typed port row")
        seen.add(a)
        destinations, handles = as_list(row["destination_indices"]), as_list(row["destination_handles"])
        if len(destinations) != len(handles):
            raise ValueError("Missing port handle witness")
        for b, handle in zip(destinations, handles):
            if not 1 <= b <= len(vertices) or vertices[b-1]["handle"] != handle:
                raise ValueError("Wrong physical destination identity")
            actual.add(tuple(sorted((a, b))))
    if seen != set(range(1, len(vertices)+1)) or actual != expected:
        raise ValueError("Liquid wires disagree with recorded PortConnectivity")
    return {v["key"]: int(labels[i]) for i, v in enumerate(vertices)}


def measured_sign(values):
    v = np.asarray(values)
    if v.size == 0 or not np.isfinite(v).all():
        raise ValueError("No finite route-flow observations")
    return 1 if v.min() > 0 else -1 if v.max() < 0 else 0


def infer_sequence(pump_terminal_node, return_terminal_node, sensor_sign, count=21):
    if {pump_terminal_node, return_terminal_node} != {1, count} or sensor_sign not in (-1, 1):
        raise ValueError("No unique full-chain direction from the selected flow window")
    start = pump_terminal_node if sensor_sign > 0 else return_terminal_node
    return list(range(1, count+1)) if start == 1 else list(range(count, 0, -1))


def audit(root):
    completion = root/"arm_completion.json"
    arm = json.loads(completion.read_text(encoding="utf-8"))
    observations = root/"observations.mat"
    if arm.get("cycle_count") != 20 or arm.get("do_not_use_as_seed") is not True or sha256(observations) != arm["observation_sha256"]:
        raise ValueError("Not the completed retained native cold diagnostic")
    tl_path, th_path = root/"tl_connectivity.json", root/"thermal_connectivity.json"
    tl = json.loads(tl_path.read_text(encoding="utf-8"))
    thermal = json.loads(th_path.read_text(encoding="utf-8"))
    nets = liquid_wire_labels(tl)
    tgroups = wire_nets(thermal)
    tnets = {key: i for i, group in enumerate(tgroups) for key in group}
    blocks = {b["block_path"]: b for b in thermal["blocks"]}
    prefix = "heatdrive_ecc_coupled_se21/SMA/"
    rows = []
    for group, pipe_in, pipe_out, route_valve, return_valve in (
            ("Hold", "B", "A", "SMA_V3_pump_to_heat_path", "SMA_V5_SMA_to_SHEX"),
            ("Cooldown", "B", "A", "SMA_V4_pump_to_cool_path", "SMA_V6_SMA_to_HHEX")):
        mapped = []
        for i in range(1, 22):
            pipe = prefix+group+"Pipe_%03d" % i
            gate = prefix+group+"ThermalGate_%03d" % i
            sensor = prefix+"SMA"+group+"Node%02dHeatFlowSensor" % i
            mass = prefix+"Subsystem2/NodeMass_%02d:M" % i
            if (tnets[pipe+":H"] != tnets[gate+":A"] or tnets[gate+":B"] != tnets[sensor+":A"]
                    or tnets[sensor+":B"] != tnets[mass]
                    or blocks[sensor]["source_file"] != "foundation.thermal.sensors.heat_flow"):
                raise ValueError("Pipe/finite gate/ideal sensor/solid coordinate mapping changed")
            mapped.append({"pipe_index": i, "solid_node_index": i, "solid_mass_port": mass})
        for i in range(1, 21):
            end1, end2 = (("B", "A") if group == "Hold" else ("A", "B"))
            if nets[prefix+group+"Pipe_%03d:" % i+end1] != nets[prefix+group+"Pipe_%03d:" % (i+1)+end2]:
                raise ValueError("Non-sequential native pipe chain")
        pump_index = 21 if group == "Hold" else 1
        return_index = 22-pump_index
        if (nets["heatdrive_ecc_coupled_se21/"+route_valve+":B"] != nets[prefix+group+"Pipe_%03d:B" % pump_index]
                or nets["heatdrive_ecc_coupled_se21/"+return_valve+":A"] != nets[prefix+group+"Pipe_%03d:A" % return_index]):
            raise ValueError("Native valve/chain terminals changed")
        route_sensor = "heatdrive_ecc_coupled_se21/FlowSensor_SMA_stage%d_route" % (1 if group == "Hold" else 3)
        if nets[route_sensor+":B"] != nets["heatdrive_ecc_coupled_se21/"+route_valve+":A"]:
            raise ValueError("Recorded route sensor does not feed the selected valve")
        rows.append({"route": group, "pump_side_pipe_index": pump_index, "return_side_pipe_index": return_index,
                     "pipe_to_solid_mapping": mapped, "flow_sensor_positive_convention": "sensor A to B, per direct PS converter/builder",
                     "windows": []})
    with h5py.File(observations, "r") as f:
        same_run = bool(np.asarray(f["boundary_metadata/same_run_topology_reused"]).item())
        for row in rows:
            heat = row["route"] == "Hold"
            name = "mass_flow_sma_stage%d_route_kgps" % (1 if heat else 3)
            t = np.asarray(f["signals/"+name+"/time_s"]).ravel()
            v = np.asarray(f["signals/"+name+"/values"]).ravel()
            if len(t) != len(v) or not np.isfinite(t).all() or np.any(np.diff(t) <= 0):
                raise ValueError("Invalid native flow-signal clock")
            for cycle in (1, 20):
                start = (cycle-1)*10+(0 if heat else 5)+.2
                end = start+4.6
                a = v[(t >= start) & (t <= end)]
                sign = measured_sign(a)
                row["windows"].append({"cycle": cycle, "time_s": [start, end], "samples": len(a),
                    "flow_min_median_max_kg_s": [float(a.min()), float(np.median(a)), float(a.max())],
                    "signed_sensor_direction": sign,
                    "solid_node_visit_order": infer_sequence(row["pump_side_pipe_index"], row["return_side_pipe_index"], sign)})
    if not same_run:
        raise ValueError("No retained same-run topology/observation witness")
    reference = {"heating": list(range(1, 22)), "cooling": list(range(21, 0, -1))}
    opposite = all(rows[0]["windows"][j]["solid_node_visit_order"] == rows[1]["windows"][j]["solid_node_visit_order"][::-1] for j in (0, 1))
    agrees = all(w["solid_node_visit_order"] == reference["heating" if r["route"] == "Hold" else "cooling"] for r in rows for w in r["windows"])
    return {"schema": "heatdrive_ecc_saved_SMA_flow_coordinates_v1", "source_snapshot_commit": arm["execution_commit"],
            "inputs": [{"path": str(p), "sha256": sha256(p)} for p in (completion, observations, tl_path, th_path)],
            "same_run_topology_flag": same_run, "routes": rows,
            "native_snapshot_heat_cool_opposite_on_same_solid_coordinates": opposite,
            "reference_heat_cool_visit_order": reference,
            "reference_direction_agrees_with_this_native_snapshot": agrees,
            "scope": "first/last-cycle non-switching windows, retained cold diagnostic only; no sign claim at valve transitions",
            "remaining_sign_assumption": "Named route signals are the direct un-inverted sensor PS outputs, as wired by the recorded builder convention",
            "paper_Fig13_co_directed_interpretation_independently_validated": False,
            "current_dirty_SLX_inspected_or_modified": False, "hydraulic_or_mechanism_qualification": False,
            "production_recovery_allowed": False}
