"""Report solid-only drift using production limits; bind exact MATLAB predicates separately."""
import argparse
import json
from pathlib import Path

import h5py

from Audit_HeatDriveECC_SegmentedEvidence import sha256


def core_periodicity(arm, limits):
    temperature=arm['solid_temperature_drift_K']
    phase=arm['solid_phase_fraction_drift']
    mapping=(('temperature_endpoint',temperature['endpoint_max'],'max_periodic_endpoint_drift_K'),
             ('temperature_p99',temperature['same_phase_p99'],'max_periodic_same_phase_temperature_p99_drift_K'),
             ('temperature_rms',temperature['same_phase_rms'],'max_periodic_same_phase_temperature_rms_drift_K'),
             ('phase_endpoint',phase['endpoint_max'],'max_periodic_phase_drift'),
             ('phase_p99',phase['same_phase_p99'],'max_periodic_same_phase_phase_p99_drift'),
             ('phase_rms',phase['same_phase_rms'],'max_periodic_same_phase_phase_rms_drift'))
    gates={name:dict(value=float(value),limit=float(limits[key]),pass_gate=bool(value<=limits[key]))
           for name,value,key in mapping}
    return dict(predicates=gates,last_pair_core_predicates_pass=all(g['pass_gate'] for g in gates.values()),
                predicate_scope='solid_node_endpoint_and_numpy_percentile_last_pair',
                equivalent_to_original_production_predicates=False,
                same_phase_maxima_are_nonblocking_diagnostics=True,
                diagnostic_temperature_peak_K=temperature['same_phase_max'],
                diagnostic_phase_peak=phase['same_phase_max'])


def completed_mechanism(root, physics, execution, receipt):
    hashes={key.replace('\\', '/'):value for key,value in physics['input_sha256'].items()}
    checks=receipt.get('checks', {})
    if (receipt.get('schema') != 'heatdrive_ecc_saved_production_mechanism_audit_v1'
            or receipt.get('source_execution_commit') != execution['execution_commit']
            or receipt.get('source_execution_sha256') != sha256(root/'cold_chamber_execution.json')
            or receipt.get('source_observation_sha256') != hashes['native/observations.mat']
            or receipt.get('source_configuration_sha256') != hashes['native/configuration.mat']
            or receipt.get('original_production_predicates_evaluated') is not True
            or receipt.get('exact_saved_window_pass') is not True
            or receipt.get('simulation_executed') is not False
            or receipt.get('operating_point_loaded') is not False
            or len(checks) != 73 or any(type(value) is not bool for value in checks.values())
            or receipt.get('analysis_window', {}).get('absolute_start_s') != execution['stop_time_s']-20
            or receipt.get('analysis_window', {}).get('absolute_stop_s') != execution['stop_time_s']):
        raise ValueError('Full mechanism receipt does not bind the same completed trajectory')
    return dict(evaluated=True, count=len(checks), pass_gate=all(checks.values()),
                failed_checks=[name for name,value in checks.items() if not value])


def production_periodicity(root, execution, receipt):
    if (receipt.get('schema') != 'heatdrive_ecc_saved_production_periodicity_v1'
            or receipt.get('source_execution_commit') != execution['execution_commit']
            or receipt.get('source_execution_sha256') != sha256(root/'cold_chamber_execution.json')
            or receipt.get('source_observation_sha256') != sha256(root/'native/observations.mat')
            or receipt.get('source_configuration_sha256') != sha256(root/'native/configuration.mat')
            or receipt.get('original_summarizer_used') is not True
            or receipt.get('physical_tolerances_changed') is not False
            or receipt.get('simulation_executed') is not False
            or receipt.get('operating_point_loaded') is not False
            or receipt.get('periodic_window_cycles') != 2
            or receipt.get('ten_cycle_production_window_verified') is not False
            or receipt.get('periodic_steady_state_verified') is not False
            or receipt.get('production_recovery_allowed') is not False
            or receipt.get('analysis_window', {}).get('absolute_start_s') != execution['stop_time_s']-20
            or receipt.get('analysis_window', {}).get('absolute_stop_s') != execution['stop_time_s']):
        raise ValueError('Exact production periodicity receipt has a wrong source or promoted scope')
    return receipt


def ten_cycle_periodicity(root, execution, receipt):
    if (receipt.get('schema') != 'heatdrive_ecc_saved_ten_cycle_thermal_periodicity_v1'
            or receipt.get('source_execution_commit') != execution['execution_commit']
            or receipt.get('total_cycles') != execution['cycle_count']
            or receipt.get('source_execution_sha256') != sha256(root/'cold_chamber_execution.json')
            or receipt.get('source_observation_sha256') != sha256(root/'native/observations.mat')
            or receipt.get('source_configuration_sha256') != sha256(root/'native/configuration.mat')
            or receipt.get('absolute_window_s') != [execution['stop_time_s']-100,execution['stop_time_s']]
            or receipt.get('periodic_window_cycles') != 10 or receipt.get('exact_grid_sample_count') != 100001
            or any(receipt.get(key) is not True for key in (
                'pre_refactor_pair_exactly_equal','full_summary_before_after_exactly_equal',
                'public_material_fields_exactly_equal','original_periodic_predicates_used'))
            or any(receipt.get(key) is not False for key in (
                'simulation_executed','operating_point_loaded','physical_tolerances_changed',
                'production_recovery_allowed','outer_solve_eligible','table4_reproduction_claim',
                'complete_internal_state_periodicity_verified','full_device_first_law_verified'))):
        raise ValueError('Ten-cycle public statistics do not bind the same trajectory or overclaim scope')
    return receipt


def analyze(root, physics_path, state_path, mechanism_path=None, periodicity_path=None, thermal_path=None):
    read=lambda path:json.loads(path.read_text(encoding='utf-8-sig'))
    physics=read(physics_path);states=read(state_path);execution=read(root/'cold_chamber_execution.json')
    capture=read(root/'native/diagnostic_state_capture.json')
    if (physics['input_sha256']['cold_chamber_execution.json']!=sha256(root/'cold_chamber_execution.json')
            or physics['producer']!=execution['execution_commit']
            or physics['analysis_scope']!='state_qualified_diagnostic_segment'
            or physics['cycles_run']!=execution['cycle_count'] or len(physics['arms'])!=1
            or physics['logged_window_s']!=[execution['stop_time_s']-20,execution['stop_time_s']]
            or states['observation_sha256']!=capture['history_sha256']
            or states['observation_sha256']!=sha256(root/'native/diagnostic_state_observation.mat')
            or sha256(root/'native/diagnostic_complete_operating_point.mat')!=capture['operating_point_sha256']):
        raise ValueError('Completed physics, state history and intact endpoint are not jointly hash-bound')
    arm=physics['arms'][0]
    hashes={key.replace('\\', '/'):value for key,value in physics['input_sha256'].items()}
    if sha256(root/'native/observations.mat')!=hashes['native/observations.mat']:
        raise ValueError('Physical observation changed')
    with h5py.File(root/'native/configuration.mat') as file:
        limits={key:float(file['options/validation/'+key][0,0]) for key in (
            'max_periodic_endpoint_drift_K','max_periodic_same_phase_temperature_p99_drift_K',
            'max_periodic_same_phase_temperature_rms_drift_K','max_periodic_phase_drift',
            'max_periodic_same_phase_phase_p99_drift','max_periodic_same_phase_phase_rms_drift')}
    predicates=core_periodicity(arm,limits)
    result=dict(schema='heatdrive_ecc_diagnostic_steadiness_v1',producer=execution['execution_commit'],
                total_cycles=execution['cycle_count'],
                segment_window_s=[execution['start_time_s'],execution['stop_time_s']],
                physical_window_s=physics['logged_window_s'],
                mechanism_subset_pass=physics['mechanism_subset_pass'],
                all_mechanism_gates_evaluated=False,
                core_periodic_last_pair=predicates,
                all_119_inventory_endpoint_K=arm['storage_drift']['worst_temperature_endpoint_K'],
                all_119_inventory_same_phase_peak_K=arm['storage_drift']['worst_temperature_same_phase_K'],
                all_logged_groups_have_ten_cycle_comparisons=states['all_logged_groups_have_ten_cycle_comparisons'],
                all_three_PI_memories_observed=states['all_three_PI_memories_observed'],
                full_state_periodicity_verified=False,packed_state_joint_norm_used=False,
                physical_tolerances_changed=False,production_recovery_allowed=False,
                outer_solve_eligible=False,paired_table4_eligible=False,table4_reproduction_claim=False,
                source_minus_endpoint_inventory_J=arm['inventory_ledger']['source_minus_actual_endpoint_storage_J'],
                full_device_first_law_verified=False,
                next_action='Complete production mechanism predicates and dimensional state mapping; do not retune PI or rerun cold solely for unsteady drift',
                input_sha256={'physics_audit':sha256(physics_path),'state_audit':sha256(state_path),
                              'configuration':sha256(root/'native/configuration.mat'),
                              'operating_point':capture['operating_point_sha256'],'history':capture['history_sha256']},
                interpretation='core_periodic_last_pair is a solid-only diagnostic, not the original production predicate: production includes heat-exchanger temperatures, mean solid endpoints, cycle phase extrema and nearest-rank p99. Raw maxima are diagnostic. Neither a last pair nor captured state grants steady recovery or Table 4.')
    if mechanism_path is not None:
        mechanism=completed_mechanism(root,physics,execution,read(mechanism_path))
        result.update(all_mechanism_gates_evaluated=True, full_mechanism=mechanism,
                      next_action='Qualify the intact latest diagnostic endpoint for further warmup; complete dimensional state mapping before steady outer solve')
        result['input_sha256']['full_mechanism_audit']=sha256(mechanism_path)
    if periodicity_path is not None:
        result['original_production_last_pair']=production_periodicity(root,execution,read(periodicity_path))
        result['input_sha256']['original_production_periodicity_audit']=sha256(periodicity_path)
    if thermal_path is not None:
        result['ten_cycle_production_temperature_phase']=ten_cycle_periodicity(root,execution,read(thermal_path))
        result['input_sha256']['ten_cycle_thermal_periodicity_audit']=sha256(thermal_path)
    return result


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--experiment-root',type=Path,required=True)
    parser.add_argument('--physics-audit',type=Path,required=True)
    parser.add_argument('--state-audit',type=Path,required=True)
    parser.add_argument('--mechanism-audit',type=Path)
    parser.add_argument('--periodicity-audit',type=Path)
    parser.add_argument('--thermal-periodicity-audit',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():raise FileExistsError('Never overwrite a diagnostic decision')
    result=analyze(args.experiment_root,args.physics_audit,args.state_audit,args.mechanism_audit,args.periodicity_audit,args.thermal_periodicity_audit)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({key:result[key] for key in ('total_cycles','mechanism_subset_pass',
        'core_periodic_last_pair','all_logged_groups_have_ten_cycle_comparisons',
        'full_state_periodicity_verified','production_recovery_allowed')},indent=2))
