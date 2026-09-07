"""Audit actual thermal wire nets and declared capacity without inferring heat transfer."""
import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path
import re

from Audit_HeatDriveECC_ChamberStepConvergence import PHYSICAL_SHA
from Audit_HeatDriveECC_RouteGeometryResult import value
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_TLDomainInventory import as_list


def wire_nets(topology):
    if (topology['schema'] != 'heatdrive_ecc_thermal_connectivity_v1'
            or topology['domain'] != 'foundation.thermal.thermal'
            or topology['primitive_internal_connections_inferred'] or topology['source_model_modified']):
        raise ValueError('Expected unmodified thermal wire export')
    vertices = topology['vertices']
    n = len(vertices)
    if not n or len({v['key'] for v in vertices}) != n or len({v['handle'] for v in vertices}) != n:
        raise ValueError('Missing or duplicate typed port')
    if any(v['domain'] != topology['domain'] for v in vertices):
        raise ValueError('Mixed domains in thermal graph')
    parent = list(range(n))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    def index(i):
        if type(i) is not int or not 1 <= i <= n:
            raise ValueError('Invalid one-based port index')
        return i - 1

    observed_wire = set()
    for edge in topology['edges']:
        if edge['kind'] not in ('physical_wire_net', 'hierarchy_connector'):
            raise ValueError('Primitive heat-transfer relation is not a wire')
        a, b = index(edge['a']), index(edge['b'])
        if a == b:
            raise ValueError('Self-connected thermal port')
        if edge['kind'] == 'physical_wire_net':
            observed_wire.add(tuple(sorted((a, b))))
        parent[find(b)] = find(a)
    recorded_wire, seen = set(), set()
    for row in topology['port_connectivity']:
        a = index(row['vertex_index'])
        if a in seen:
            raise ValueError('Duplicate PortConnectivity row')
        seen.add(a)
        destinations = as_list(row['destination_indices'])
        handles = as_list(row['destination_handles'])
        if len(destinations) != len(handles):
            raise ValueError('Destination handle coverage changed')
        for b, handle in zip(destinations, handles):
            b = index(b)
            if vertices[b]['handle'] != handle:
                raise ValueError('Destination handle does not identify its typed port')
            recorded_wire.add(tuple(sorted((a, b))))
    if seen != set(range(n)) or recorded_wire != observed_wire:
        raise ValueError('Wire export disagrees with complete PortConnectivity')
    ownership = []
    for block in topology['blocks']:
        indices = as_list(block['vertex_indices'])
        for i in indices:
            a = index(i)
            if vertices[a]['block_path'] != block['block_path']:
                raise ValueError('Incorrect physical block ownership')
            ownership.append(a)
    if sorted(ownership) != list(range(n)):
        raise ValueError('Missing or repeated block port ownership')
    groups = defaultdict(list)
    for i, v in enumerate(vertices):
        groups[find(i)].append(v['key'])
    return sorted((sorted(g) for g in groups.values()), key=lambda g: g[0])


def capacity_audit(data):
    system, material, geometry = (data[k] for k in ('system_options', 'material_options', 'geometry_options'))
    masses = [r for r in data['geometry'] if r['mask_type'] == 'Thermal Mass']
    if len(masses) != 46 or len({r['block_path'] for r in masses}) != 46:
        raise ValueError('Unexpected capacity inventory; reclassify explicitly')
    rows, counts = [], Counter()
    sink_fields = dict(shex_sink_mass_kg='shex_sink_C_J_per_K', hot_sink_mass_kg='hot_sink_C_J_per_K',
                       cold_sink_mass_kg='cold_sink_C_J_per_K', cold_load_mass_kg='cold_load_C_J_per_K')
    for row in masses:
        path = row['block_path']
        actual = value(row, 'mass', 'kg') * value(row, 'sp_heat', 'J/(K*kg)')
        match = re.search(r'/(SMA|SE)/Subsystem2/NodeMass_(\d{2})$', path)
        if match:
            role = match[1]
            if not 1 <= int(match[2]) <= 21:
                raise ValueError('Unexpected solid node')
            volume = geometry['net_sma_volume_m3' if role == 'SMA' else 'se_volume_m3']
            expected = volume * material[role]['rho_kg_per_m3'] * material[role]['cp_J_per_kgK'] / 21
            formula = f'{role}: volume * material density * material cp / 21'
        else:
            expression = row['parameters']['mass']
            if expression not in sink_fields:
                raise ValueError('Unclassified thermal capacity')
            role = sink_fields[expression]
            expected = system[role]
            fluid_cp = 4180 if role == 'shex_sink_C_J_per_K' else system['cp_fluid_J_per_kgK']
            if not math.isclose(expected, system['endpoint_reservoir_mass_kg'] * fluid_cp, rel_tol=1e-12):
                raise ValueError('Reservoir closure contains an undeclared correction')
            formula = f'endpoint_reservoir_mass_kg * {fluid_cp} J/(kg K)'
        if row['resolution_errors'] or not math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12):
            raise ValueError('Actual thermal capacity differs from declared material/reservoir formula')
        counts[role] += 1
        rows.append(dict(block_path=path, role=role, capacity_J_K=actual,
                         expected_capacity_J_K=expected, absolute_difference_J_K=abs(actual-expected), formula=formula))
    if counts != Counter(dict(SMA=21, SE=21, **{k: 1 for k in sink_fields.values()})):
        raise ValueError('Capacity role coverage incomplete')
    return rows


def audit(data):
    if (data['geometry_schema'] != 'heatdrive_ecc_route_geometry_v1' or data['simulation_run']
            or data['production_checkpoint_loaded'] or data['production_model_saved'] or data['production_recovery_allowed']):
        raise ValueError('Expected model inspection without production restore')
    topology = data['thermal_connectivity']
    nets = wire_nets(topology)
    by_port = {p: net for net in nets for p in net}
    capacities = capacity_audit(data)
    thermal_mass_paths = {b['block_path'] for b in topology['blocks']
                          if b['source_file'] == 'foundation.thermal.elements.mass'}
    if thermal_mass_paths != {r['block_path'] for r in capacities}:
        raise ValueError('Thermal graph and geometry capacity coverage differ')
    connectors = []
    for suffix in ('/SMA_PumpInletConnectingPipeVolume', '/SMA_PumpOutletConnectingPipeVolume'):
        blocks = [b for b in topology['blocks'] if b['block_path'].endswith(suffix)]
        if len(blocks) != 1 or blocks[0]['source_file'] != 'foundation.thermal_liquid.elements.constant_volume_chamber':
            raise ValueError('Public connector primitive changed')
        key = blocks[0]['block_path'] + ':H'
        if key not in by_port:
            raise ValueError('Missing named connector H port')
        connectors.append(dict(block_path=blocks[0]['block_path'], heat_port=key,
                               connected_wire_net=by_port[key], heat_port_unconnected=by_port[key] == [key]))
    if not all(r['heat_port_unconnected'] for r in connectors):
        raise ValueError('Connector thermal boundary changed; review before asserting missing wall')
    return dict(schema='heatdrive_ecc_thermal_capacity_audit_v1', computation_complete=True,
                thermal_connectivity_verified=True, thermal_port_count=len(topology['vertices']),
                thermal_wire_net_count=len(nets), thermal_wire_nets=nets,
                primitive_counts=dict(sorted(Counter(b['source_file'] for b in topology['blocks']).items())),
                public_connectors=connectors, actual_thermal_mass_count=len(capacities), capacity_provenance=capacities,
                existing_declared_capacities_match_material_and_reservoir_formulas=True,
                explicit_connector_wall_capacity_present=False,
                wall_capacity_per_assumed_article_shell_J_K=math.pi/4*((.0032+2*.0005)**2-.0032**2)*.2*1.8e6,
                article_connector_assignment_fully_proven=False, reservoir_closure_physically_validated=False,
                resistance_or_sensor_ports_merged_as_wires=False, production_model_changed=False,
                production_recovery_allowed=False, whole_model_first_law_verified=False, table4_reproduction_claim=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite evidence')
    source = args.repo / 'outputs_storage_audit/thermal_connectivity_20260907/route_geometry.json'
    data = json.loads(source.read_text(encoding='utf-8-sig'))
    if (data['execution_commit'] != 'a878159b823acf04f217c55213f7bfd84986e99d'
            or sha256(Path(data['source_options_path'])) != PHYSICAL_SHA):
        raise ValueError('Changed inspection source')
    result = audit(data)
    result['source_sha256'] = sha256(source)
    result['inspection_execution_commit'] = data['execution_commit']
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in result.items() if k not in ('thermal_wire_nets', 'capacity_provenance')}, indent=2))


if __name__ == '__main__':
    main()
