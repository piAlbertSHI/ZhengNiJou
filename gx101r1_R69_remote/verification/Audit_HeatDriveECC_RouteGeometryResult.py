"""Reconcile intended SMA route components with actual geometric inventory."""
import argparse
from collections import defaultdict
import json
import math
import re
from pathlib import Path

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_TLDomainInventory import as_list, resolve_domains
from Audit_HeatDriveECC_ChamberStepConvergence import PHYSICAL_SHA


def route_paths(topology, active_valves):
    vertices=topology['vertices']
    parent=list(range(len(vertices)))
    def find(i):
        while parent[i]!=i:
            parent[i]=parent[parent[i]]
            i=parent[i]
        return i
    for edge in topology['edges']:
        if edge['kind'] not in ('physical_wire_net','hierarchy_connector'):
            raise ValueError('Unknown physical edge')
        a,b=find(edge['a']-1),find(edge['b']-1)
        parent[b]=a
    graph=defaultdict(list)
    pump=None
    for block in topology['blocks']:
        source,path=block['source_file'],block['block_path']
        ports=[find(i-1) for i in as_list(block['vertex_indices'])]
        if path.endswith('/SMA Pressure Source (TL)'):
            if len(ports)!=2 or ports[0]==ports[1]:
                raise ValueError('Pump boundary is shorted or incomplete')
            pump=ports
            continue
        if '/SMA_V' in path:
            number=int(path.rsplit('/SMA_V',1)[1].split('_')[0])
            if number not in active_valves:
                continue
        if not source:
            continue
        for other in ports[1:]:
            if ports[0]!=other:
                graph[ports[0]].append((other,path))
                graph[other].append((ports[0],path))
    if pump is None:
        raise ValueError('Missing SMA pump')
    paths=[]
    def visit(node,seen,blocks):
        if len(paths)>1:
            return
        if node==pump[1]:
            paths.append(blocks)
            return
        for neighbor,path in graph[node]:
            if neighbor not in seen:
                visit(neighbor,seen|{neighbor},blocks+[path])
    visit(pump[0],{pump[0]},[])
    if len(paths)!=1:
        raise ValueError(f'Expected unique intended route, got {len(paths)}')
    return paths[0]


def value(row,key,unit):
    item=row['resolved'][key]
    number=float(item['value'])
    if item['unit']!=unit or not math.isfinite(number):
        raise ValueError('Unsupported geometry unit or nonfinite value')
    return number


def audit_geometry(data):
    if (data['geometry_schema']!='heatdrive_ecc_route_geometry_v1' or data['simulation_run']
            or data['production_checkpoint_loaded'] or data['production_model_saved'] or data['production_recovery_allowed']):
        raise ValueError('Expected read-only geometry source')
    resolve_domains(data)
    rows=data['geometry']
    if len(rows)!=115 or len({r['block_path'] for r in rows})!=len(rows) or any(r['resolution_errors'] for r in rows):
        raise ValueError('Missing or unresolved actual geometry')
    by_path={r['block_path']:r for r in rows}
    result=[]
    for stage,valves in [(1,{1,3,5}),(3,{2,4,6})]:
        path=route_paths(data,valves)
        selected=[by_path[p] for p in path if p in by_path]
        pipes=[]
        manifolds=[]
        for row in selected:
            if row['mask_type']=='Pipe (TL)':
                length=value(row,'length','m')
                area=value(row,'area','m^2')
                pipes.append(dict(block_path=row['block_path'],length_m=length,area_m2=area,
                                  hydraulic_diameter_m=value(row,'Dh','m'),fluid_volume_m3=length*area,
                                  equivalent_additional_length_m=value(row,'length_add','m')))
            elif row['mask_type']=='Constant Volume Chamber (TL)':
                volume=value(row,'volume','m^3')
                area=value(row,'area_A','m^2')
                manifolds.append(dict(block_path=row['block_path'],volume_m3=volume,equivalent_length_m=volume/area,
                                      modeled_friction_length_m=0))
            else:
                raise ValueError('Unexpected storage component on fluid route')
        if len(pipes)!=22 or len(manifolds)!=2:
            raise ValueError('Unexpected main route inventory count')
        if not all(abs(r['equivalent_length_m']-.2)<1e-12 for r in manifolds):
            raise ValueError('Public manifold volume changed')
        result.append(dict(stage=stage,active_valves=sorted(valves),component_path_from_pump_A_to_B=path,
                           pipes=pipes,manifolds=manifolds,pipe_length_sum_m=sum(r['length_m'] for r in pipes),
                           pipe_fluid_volume_sum_m3=sum(r['fluid_volume_m3'] for r in pipes),
                           manifold_volume_sum_m3=sum(r['volume_m3'] for r in manifolds),
                           equivalent_public_connector_length_m=sum(r['equivalent_length_m'] for r in manifolds),
                           physical_public_connector_friction_length_m=0,
                           physically_modeled_additional_length_m=sum(r['equivalent_additional_length_m'] for r in pipes)))
    masses=[]
    for row in rows:
        if row['mask_type']=='Thermal Mass':
            name=row['block_path']
            role=('solid_node' if re.search(r'/(SMA|SE)/Subsystem2/NodeMass_\d{2}$',name) else
                  'sink_or_load' if name.rsplit('/',1)[-1] in ('HotSinkMass','ColdSinkMass','ColdLoadMass') else 'unassigned')
            masses.append(dict(block_path=name,classification_from_block_identity=role,mass_kg=value(row,'mass','kg'),
                               cp_J_kgK=value(row,'sp_heat','J/(K*kg)'),
                               heat_capacity_J_K=value(row,'mass','kg')*value(row,'sp_heat','J/(K*kg)')))
    return dict(schema='heatdrive_ecc_route_geometry_audit_v1',geometry_audit_complete=True,
                intended_sma_routes=result,thermal_masses=masses,
                physical_geometry_count=len(rows),
                unassigned_thermal_mass_blocks=[r['block_path'] for r in masses if r['classification_from_block_identity']=='unassigned'],
                explicit_connector_named_thermal_mass_blocks=[r['block_path'] for r in masses if 'ConnectingPipe' in r['block_path'] or 'ConnectorWall' in r['block_path']],
                connector_wall_capacity_if_two_article_shells_J_K=2*math.pi/4*((.0032+2*.0005)**2-.0032**2)*.2*1.8e6,
                route_graph_assumption='Closed SMA valves removed for intended-route enumeration; leakage is not simulated.',
                full_physical_leakage_audit_complete=False,thermal_connectivity_verified=False,
                article_connector_assignment_fully_proven=False,pressure_feedforward_is_dissipative_component=False,
                production_geometry_modified=False,production_recovery_allowed=False,whole_model_first_law_verified=False,
                table4_reproduction_claim=False)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite geometry audit')
    root=args.repo/'outputs_storage_audit/production_route_geometry_20260907'
    source=root/'model/route_geometry.json'
    data=json.loads(source.read_text(encoding='utf-8-sig'))
    if sha256(Path(data['source_options_path']))!=PHYSICAL_SHA:
        raise ValueError('Options input changed')
    result=audit_geometry(data)
    result['input_sha256']=dict(geometry=sha256(source),options=PHYSICAL_SHA)
    result['execution_commit']=data['execution_commit']
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('intended_sma_routes','thermal_masses')},indent=2))


if __name__=='__main__':
    main()
