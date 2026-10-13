"""Audit a common-reference intervention against the completed unchanged-volume cold case."""
import argparse
import copy
import json
from pathlib import Path

import h5py
import numpy as np

from Analyze_HeatDriveECC_ManifoldCounterfactual import analyze_case, initial_coordinates, COMMAND_NAMES
from Analyze_HeatDriveECC_SECommutationInventory import partition,reference_comparison
from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_CoupledEnergyInventory import ROOT
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def config_contract(baseline,candidate):
    baseline,candidate=copy.deepcopy(baseline),copy.deepcopy(candidate)
    baseline.pop('output_root');candidate.pop('output_root')
    if candidate.pop('diagnostic_se_reference_options')!={'mode':'coherent_envelope'} or baseline!=candidate:
        raise ValueError('Changed parameters beyond the declared reference contract')


def controller_contract(time,signals,contract):
    alpha=signals['distributed_pressure_envelope']
    expected=np.interp(time,contract['time_s'],contract['stroke_envelope'])
    nominal=contract['nominal_mass_flow_kgps']
    if not np.allclose(alpha,expected,atol=1e-12,rtol=0):
        raise ValueError('Actual envelope differs from its applied contract')
    reference=reference_comparison(time,alpha,signals['distributed_target_flow_kg_s'],
        signals['stage4_target_flow_command'],signals['stage4_integrator_output_gate'],nominal)
    if not reference['pressure_envelope_and_PI_reference_identical']:
        raise ValueError('The coherent-reference intervention did not reach the real controller')
    gate=next(row for row in contract['route_output_gates'] if row['stage']==4)
    indices=np.searchsorted(gate['time_s'],time+1e-10,side='right')-1
    output_enable=np.asarray(gate['coherent_output_enable'])[indices]
    error=float(np.max(abs(signals['stage4_integrator_output_gate']-
        signals['stage4_integrator_state']*output_enable)))
    if error>1e-10:
        raise ValueError('Measured route-I output is not unchanged memory times its declared envelope')
    return dict(reference_comparison=reference,route_I_output_equation_max_error_MPa=error,
        integral_memory_reset=False,integral_update_policy_changed=False)


def audit(root):
    manifest=json.loads((root/'reference_execution.json').read_text(encoding='utf-8'))
    if manifest['status']!='collected_requires_physical_comparison' or manifest['source_state_loaded']:
        raise ValueError('Incomplete or state-imported reference experiment')
    a,b=Path(manifest['baseline_root']),Path(manifest['candidate_root'])
    read=lambda p:json.loads(p.read_text(encoding='utf-8'))
    executions=[read(folder/'cold_chamber_execution.json') for folder in (a,b)]
    for folder,execution,key in ((a,executions[0],'baseline_execution_sha256'),(b,executions[1],'candidate_execution_sha256')):
        if (sha256(folder/'cold_chamber_execution.json')!=manifest[key] or
                not execution['requested_arm_collection_pass'] or execution['error_message'] or
                execution['start_time_s']!=0 or execution['stop_time_s']!=10 or execution['checkpoint_saved'] or
                execution['cases'][0]['observation_sha256']!=sha256(folder/'native/observations.mat')):
            raise ValueError('Changed or incomplete cold observation')
    config_contract(read(a.parent/'baseline_config.json'),read(root/'candidate_config.json'))
    if read(a/'native/inventory_metadata.json')!=read(b/'native/inventory_metadata.json'):
        raise ValueError('Geometry, initialization parameters or fluid properties changed')
    contract=read(b/'native/se_reference_contract.json')
    if sha256(b/'native/se_reference_contract.json')!=executions[1]['se_reference_diagnostic']['contract_sha256']:
        raise ValueError('Reference contract changed')
    cases=[analyze_case(folder,execution) for folder,execution in zip((a,b),executions)]
    initialization=initial_coordinates(a,b,candidate_volume_factor=1)
    with h5py.File(a/'native/configuration.mat') as ca,h5py.File(b/'native/configuration.mat') as cb:
        if set(ca['commands'])!=COMMAND_NAMES or set(cb['commands'])!=COMMAND_NAMES:
            raise ValueError('Incomplete independent-route command coverage')
        allowed={'SE_stage2_pressure_integrator_output_enable_command','SE_stage4_pressure_integrator_output_enable_command'}
        for name in COMMAND_NAMES-allowed:
            for field in ('time_s','values'):
                if not np.array_equal(ca['commands'][name][field][:],cb['commands'][name][field][:]):
                    raise ValueError('Undeclared control command change')
        for route in contract['route_output_gates']:
            name=f"SE_stage{route['stage']}_pressure_integrator_output_enable_command"
            time=ca['commands'][name]['time_s'][:].ravel()
            expected=ca['commands'][name]['values'][:].ravel()*np.interp(time,contract['time_s'],contract['stroke_envelope'])
            if (not np.array_equal(time,cb['commands'][name]['time_s'][:].ravel()) or
                    np.max(abs(expected-cb['commands'][name]['values'][:].ravel()))>1e-12):
                raise ValueError('Route output command is not its retained memory-output gate times envelope')
    time=np.arange(10001)*.001
    with h5py.File(b/'native/observations.mat') as f:
        names=('distributed_pressure_envelope','distributed_target_flow_kg_s','stage4_target_flow_command',
            'stage4_integrator_output_gate','stage4_integrator_state')
        signals={name:f['signals/'+name+'/values'][:].ravel() for name in names}
        equations=controller_contract(time,signals,contract)
    partitions=[]
    for folder in (a,b):
        with h5py.File(folder/'native/observations.mat') as f,h5py.File(folder/'native/configuration.mat') as c:
            rows=named_rows(f,f['native'])
            mass=scalar_series(rows[ROOT+'ColdFluidBuffer','stored_mass'],'kg')
            flow=scalar_series(rows[ROOT+'ColdFluidBuffer','mdot_A'],'kg/s')
            ramp=float(c['options/branch/stage_command_ramp_s'][0,0])
            partitions.append(partition(time,mass,flow,ramp))
    return dict(schema='heatdrive_ecc_se_reference_comparison_v1',source_root=str(root),
        manifest_sha256=sha256(root/'reference_execution.json'),cases=cases,
        cold_initialization=initialization,controller_equations=equations,
        cold_buffer_stage_partitions=partitions,geometry_and_properties_identical=True,
        only_PI_target_and_route_memory_output_envelope_changed=True,
        two_cycle_cold_followup_allowed=bool(initialization['actual_initial_coordinates_match'] and
            all(case['model_energy_balance']['model_equation_energy_closure_pass'] and
                case['mass_budget']['buffer_mass_equations_pass'] and
                case['mechanism_subset_runtime']['distributed_controller_runtime_pass'] and
                case['mechanism_subset_runtime']['selected_flow_gates_pass'] and
                case['mechanism_subset_runtime']['phase_bounds_pass'] and
                case['mechanism_subset_runtime']['solid_energy_pass'] and
                case['mechanism_subset_runtime']['pressure_boundary']['pressure_range_gate'] and
                case['mechanism_subset_runtime']['pressure_boundary']['hydraulic_diagnostic_gate'] for case in cases)),
        periodic_steady_state=False,all_mechanism_gates_evaluated=False,production_recovery_allowed=False,
        outer_solve_eligible=False,table4_reproduction_claim=False,
        interpretation='Single-cycle cold comparison. The final boundary holds Stage4 open because '
        'the one-cycle command horizon ends there; endpoint mass is not a periodicity certificate. '
        'Only a new state-captured multi-cycle cold experiment can test both commutation tails.')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--experiment-root',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():raise FileExistsError('Never overwrite reference comparison evidence')
    result=audit(args.experiment_root.resolve())
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({'initial_match':result['cold_initialization']['actual_initial_coordinates_match'],
        'references':result['controller_equations'],'two_cycle_cold_followup_allowed':result['two_cycle_cold_followup_allowed'],
        'Cold_buffer_endpoint_kg':[next(row['full_cycle_mass_change_kg'] for row in case['mass_budget']['buffers'] if row['buffer']=='ColdFluidBuffer') for case in result['cases']]}))
