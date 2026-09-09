"""Check split-lag cold actuation without promoting an initial point to a trajectory."""
import argparse
import csv
import json
import math
from pathlib import Path
from Audit_HeatDriveECC_ColdPassivePSObserver import (
    read, sha256, coordinates, check_runtime, check_derivative, check_phases,
    check_topology, check_actuation, check_value_edge, check_inactive_removal,
    summarize_coordinates, component_inventory_preserved, decode_tags, CHAMBERS, BUFFERS)


def check_hybrid_runtime(r):
    prefix='heatdrive_ecc_coupled_se21/'; c=r['passive_ps_observer_contract']
    if (not c['external_lag'] or c['flow_input_mode']!='live_external_lag'
            or c['flow_value_source']!=prefix+'ColdObserver_ErrorLag'
            or c['provided_flow_derivatives']!='0' or not math.isfinite(r['actual_initial_sensor_mdot_kg_s'])):
        raise ValueError('Not the live external-lag representation')
    h=c['hybrid_contract']
    if (h['lag_path']!=c['flow_value_source'] or h['lag_numerator']!='1' or h['lag_denominator']!='[.002 1]'
            or h['normalization']!='1' or h['additional_lag_state_added'] or not h['original_internal_lag_removed']):
        raise ValueError('Original lag dynamics changed or duplicated')
    if 'error_lag' in r['ps_controller_child_ids'] or len([
            s for s in r['states'] if s['block_path']==[prefix+'ColdObserver_ErrorLag'] and s['time_s']==0])!=1:
        raise ValueError('Expected exactly one external lag state and no internal lag component')
    expected_input=dict(path=prefix+'ColdObserver_mdot_PS',Unit='1',FilteringAndDerivatives='provide',
                        UdotUserProvided='0',input_count=1,value_source=prefix+'ColdObserver_ErrorLag')
    expected_lag=dict(path=prefix+'ColdObserver_ErrorLag',block_type='TransferFcn',numerator='1',
                      denominator='[.002 1]',input_source=prefix+'ColdObserver_ErrorNormalizer')
    compile_callbacks=r['pre_simulation_compile_callbacks']
    if len(compile_callbacks)!=2 or any(c['stage']!='InitFcn' or c['simulation_status']!='updating' for c in compile_callbacks):
        raise ValueError('Missing compile-only callback evidence')
    for callback in r['runtime_callbacks']+compile_callbacks:
        if callback['passive_observer_flow_input']!=expected_input or callback['external_controller_lag']!=expected_lag:
            raise ValueError('Lag dynamics or converter changed at runtime')
        solver=callback['passive_observer_solver']
        if not solver['copied_settings_identical'] or solver['settings']!=c['observer_solver_contract']['settings']:
            raise ValueError('Observer solver differs')
        if callback['pressure_converter']['value_source']!=r['ps_initial_actuation_contract']['pressure_driver']:
            raise ValueError('Candidate is not the actual pressure driver')
    loop=r['algebraic_structure']
    if loop['loop_count']!=0 or loop['loops'] or loop['simulation_run']:
        raise ValueError('Compiled algebraic loop remains')
    expected=dict(lag_input=(0.,'1'),bias=(-1e-6,'MPa'),enable=(0.,'1'),reset=(1.,'1'),
                  pressure=(-1e-6,'MPa'),lag=(0.,'1'),integral=(0.,'MPa'))
    values=r['ps_controller_initial']
    if len(values)!=7 or {x['name'] for x in values}!=set(expected):
        raise ValueError('Missing hybrid initial signals')
    for item in values:
        value,unit=expected[item['name']]
        if item['source_time_s']!=0 or item['unit']!=unit or not math.isclose(item['actual'],value,abs_tol=1e-12,rel_tol=0):
            raise ValueError('Hybrid actual initial signal differs')


def audit(repo):
    root=repo/'outputs_storage_audit/specific_inventory_hybrid_lag_actuation_initial_20260910'
    source=root/'compiled_states_inspection.json'; r=read(source)
    target_path=repo/'outputs_storage_audit/conservative_buffer_coupled_cycle_20260909/conservative/public_inventory_targets.json'
    reference=read(target_path);targets=reference['targets'];native=target_path.parent.parent/'native/observations.mat'
    if (r['inspector_commit']!='5d6d8efaab51df37bd1dccef62ed2c8fb4578637' or not r['inspection_pass']
            or not r['external_lag_requested'] or r['algebraic_structure_only'] or not r['simulation_run']
            or not r['initialization_only'] or r['diagnostic_stop_time_s']!=0 or r['error_message']
            or r['inventory_formulation']!='specific_inventory' or len(targets)!=204 or reference['has_private_data']
            or r['source_native_sha256']!=reference['source_sha256'] or sha256(native)!=reference['source_sha256']
            or any(r[k] for k in ('c200_state_imported','failed_terminal_state_imported','checkpoint_saved','production_recovery_allowed',
                                 'component_inventory_priority_high','block_temperature_pressure_priority_low'))):
        raise ValueError('Wrong cold diagnostic or state propagation')
    check_runtime(r,targets,'derivative');check_derivative(r['initial_pressure_derivative_contract'])
    check_topology(r['passive_ps_observer_contract'],True);check_actuation(r['ps_initial_actuation_contract'],r['passive_ps_observer_contract'])
    check_value_edge(r['pressure_value_path_contract']);check_inactive_removal(r['inactive_controller_removal_contract'],r['pressure_value_path_contract'])
    check_hybrid_runtime(r)
    for callback in r['pre_simulation_compile_callbacks']:
        if callback['targets']!=r['runtime_callbacks'][0]['targets']:
            raise ValueError('Compile and simulation public targets differ')
    rows=coordinates(r['initial_coordinates'],targets);summary=summarize_coordinates(rows)
    check_phases(r['cached_phase_targets'],targets,rows)
    tagged=[dict(block_name=t['block_name'],variable_name=t['variable_name'],**decode_tags(t)) for t in r['node_metadata']]
    inventory=component_inventory_preserved(tagged,CHAMBERS|BUFFERS)
    if not summary['strict_initial_coordinate_gate'] or not inventory:
        raise ValueError('Original strict initial or inventory gate failed')
    component=repo/'verification/simscape_sma_hybrid/+ecc_sma_hybrid/pressure_controller.ssc'
    qualified=repo/'outputs_storage_audit/hybrid_controller_equivalence_20260910/hybrid_controller_audit.json'
    c=r['passive_ps_observer_contract'];library=Path(c['library_path'])
    if (sha256(component)!=c['component_sha256'] or sha256(library)!=c['library_sha256']
            or sha256(qualified)!='E2B9A87B4EA88A33C3376D11F3EE716692F5C8B7F558133E7471142CBF6A4CC9'):
        raise ValueError('Qualified controller artifact changed')
    chamber=root/'component_build/+ecc_inventory_specific/conservative_chamber.ssc'
    expected=(repo/'verification/simscape_inventory/+ecc_inventory/conservative_chamber.ssc').read_text(encoding='utf-8')
    expected=expected.replace('stored_mass == volume * rho_I;','rho_I == stored_mass / volume;').replace('stored_energy == stored_mass * u_I;','u_I == stored_energy / stored_mass;')
    chamber_lib=Path(r['loaded_chamber_library'])
    if chamber.read_text(encoding='utf-8')!=expected or sha256(chamber_lib)!=r['loaded_library_sha256']:
        raise ValueError('Chamber equation or library changed')
    files=[source,target_path,native,component,qualified,library,chamber,chamber_lib,root/'compiled_initial_state_dataset.mat',root/'matlab_diary.log']
    freeze_path=repo/'verification/c200_mainline_freeze_contract.json';freeze=read(freeze_path);files.append(freeze_path)
    for key in ('result','checkpoint'):
        p=repo/freeze[key+'_relative_path']
        if sha256(p)!=freeze[key+'_sha256']:raise ValueError('C200 changed')
        files.append(p)
    result=dict(evidence_audit_pass=True,cold_initial_actuation_pass=True,coordinate_audit=summary,
                compiled_inventory_gate=inventory,compiled_algebraic_loops=0,
                active_feedback_transient_verified=False,full_cycle_pressure_derivative_verified=False,
                trajectory_conservation_verified=False,production_recovery_allowed=False,table4_reproduction_claim=False,
                input_sha256={str(p.relative_to(repo)):sha256(p) for p in files})
    return result,rows


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output-root',type=Path,required=True);args=p.parse_args()
    if args.output_root.exists():raise FileExistsError('Never overwrite evidence')
    result,rows=audit(Path(__file__).resolve().parents[1]);args.output_root.mkdir(parents=True)
    (args.output_root/'hybrid_cold_audit.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    with (args.output_root/'initial_coordinates.csv').open('x',newline='',encoding='utf-8') as f:
        writer=csv.DictWriter(f,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
    print(json.dumps({k:v for k,v in result.items() if k!='input_sha256'},indent=2))
