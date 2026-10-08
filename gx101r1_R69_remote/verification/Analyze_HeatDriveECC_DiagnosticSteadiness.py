"""Apply the existing production periodic predicates, without inventing packed-state limits."""
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
                same_phase_maxima_are_nonblocking_diagnostics=True,
                diagnostic_temperature_peak_K=temperature['same_phase_max'],
                diagnostic_phase_peak=phase['same_phase_max'])


def analyze(root, physics_path, state_path):
    read=lambda path:json.loads(path.read_text(encoding='utf-8-sig'))
    physics=read(physics_path);states=read(state_path);execution=read(root/'cold_chamber_execution.json')
    capture=read(root/'native/diagnostic_state_capture.json')
    if (physics['input_sha256']['cold_chamber_execution.json']!=sha256(root/'cold_chamber_execution.json')
            or physics['producer']!=execution['execution_commit']
            or physics['analysis_scope']!='state_qualified_diagnostic_segment'
            or physics['cycles_run']!=22 or len(physics['arms'])!=1
            or states['observation_sha256']!=capture['history_sha256']
            or states['observation_sha256']!=sha256(root/'native/diagnostic_state_observation.mat')
            or sha256(root/'native/diagnostic_complete_operating_point.mat')!=capture['operating_point_sha256']):
        raise ValueError('Completed physics, state history and intact endpoint are not jointly hash-bound')
    arm=physics['arms'][0]
    hashes={Path(key).as_posix():value for key,value in physics['input_sha256'].items()}
    if sha256(root/'native/observations.mat')!=hashes['native/observations.mat']:
        raise ValueError('Physical observation changed')
    with h5py.File(root/'native/configuration.mat') as file:
        limits={key:float(file['options/validation/'+key][0,0]) for key in (
            'max_periodic_endpoint_drift_K','max_periodic_same_phase_temperature_p99_drift_K',
            'max_periodic_same_phase_temperature_rms_drift_K','max_periodic_phase_drift',
            'max_periodic_same_phase_phase_p99_drift','max_periodic_same_phase_phase_rms_drift')}
    predicates=core_periodicity(arm,limits)
    return dict(schema='heatdrive_ecc_diagnostic_steadiness_v1',producer=execution['execution_commit'],
                total_cycles=22,segment_window_s=[20,220],physical_window_s=[200,220],
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
                interpretation='Production Summarize_HeatDriveECC_EighthRound_Output uses endpoint, p99 and RMS predicates; raw same-phase maxima are diagnostic. Passing state capture or a mechanism subset cannot grant full recovery or Table 4.')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--experiment-root',type=Path,required=True)
    parser.add_argument('--physics-audit',type=Path,required=True)
    parser.add_argument('--state-audit',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():raise FileExistsError('Never overwrite a diagnostic decision')
    result=analyze(args.experiment_root,args.physics_audit,args.state_audit)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({key:result[key] for key in ('total_cycles','mechanism_subset_pass',
        'core_periodic_last_pair','all_logged_groups_have_ten_cycle_comparisons',
        'full_state_periodicity_verified','production_recovery_allowed')},indent=2))
