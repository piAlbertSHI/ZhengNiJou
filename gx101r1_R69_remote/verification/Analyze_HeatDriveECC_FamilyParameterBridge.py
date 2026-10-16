"""Read selected stored parameters across frozen C200 and the independent runtime family."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256


FIELDS = (
    'node_count', 'system/Tchex_K', 'system/cp_fluid_J_per_kgK', 'system/se_buffer_volume_m3',
    'system/cold_boundary_temperature_configurability', 'branch/network_absolute_pressure_MPa',
    'branch/UA_se_chex_W_per_K', 'branch/UA_se_the_W_per_K',
    'branch/se_stage2_pressure_bias_MPa', 'branch/se_stage4_pressure_bias_MPa',
    'branch/se_stage2_pressure_pi_kp_MPa_per_kgps', 'branch/se_stage4_pressure_pi_kp_MPa_per_kgps',
    'branch/independent_conservative_chamber_diagnostic', 'branch/diagnostic_manifold_storage_closure',
    'branch/se_distributed_pressure_feedforward_diagnostic', 'branch/diagnostic_constitutive_step_function',
    'constitutive/rate_r_stage3_unload_1_per_s', 'constitutive/drive_width_r_Pa',
    'constitutive/diagnostic_substeps', 'material/SE/T_As_K', 'material/SE/T_Ms_K',
    'material/SE/Delta_h_J_per_kg', 'geometry/L_r_m', 'geometry/S_r_m2', 'equilibrium/m_r_kg')


def value(file, path):
    if path not in file:
        return dict(present=False)
    d = file[path]
    if not isinstance(d, h5py.Dataset):
        raise ValueError('Expected a selected leaf parameter')
    a = np.asarray(d)
    if d.attrs.get('MATLAB_class') == b'char':
        return dict(present=True, value=''.join(chr(int(v)) for v in a.ravel() if v))
    if a.size != 1 or a.dtype.kind not in 'fiu' or not np.isfinite(a).all():
        raise ValueError('Expected a finite scalar parameter, not an arbitrary array')
    return dict(present=True, value=float(a.ravel()[0]))


def bridge(repo, qualification, output):
    if output.exists():
        raise FileExistsError('Never overwrite a physical-family comparison')
    repo = repo.resolve()
    freeze_path = repo/'verification/c200_mainline_recovery_reference_20260915.json'
    freeze = json.loads(freeze_path.read_text(encoding='utf-8-sig'))
    q = json.loads(qualification.read_text(encoding='utf-8-sig'))
    baseline = (repo/freeze['result_relative_path']).resolve()
    op = (repo/freeze['checkpoint_relative_path']).resolve()
    candidate = Path(q['source_packet_root'])/'native/configuration.mat'
    if (not baseline.is_relative_to(repo) or not op.is_relative_to(repo) or
            sha256(baseline) != freeze['result_sha256'] or sha256(op) != freeze['checkpoint_sha256'] or
            not any(Path(r['path']) == candidate and r['sha256'] == sha256(candidate) for r in q['files'])):
        raise ValueError('Changed frozen C200 or candidate configuration')
    with h5py.File(baseline, 'r') as a, h5py.File(candidate, 'r') as b:
        rows = []
        for field in FIELDS:
            old, new = value(a, 'options/'+field), value(b, 'plant_build_options/'+field)
            rows.append(dict(field=field, C200=old, independent_runtime_constructor=new,
                             equal_in_selected_coordinate=old == new))
    record = dict(schema='heatdrive_ecc_selected_family_parameter_bridge_v1',
        producer_source_sha256=sha256(Path(__file__)), C200_result_sha256=freeze['result_sha256'],
        C200_OP_sha256=freeze['checkpoint_sha256'], candidate_configuration_sha256=sha256(candidate),
        candidate_qualification_sha256=sha256(qualification),
        candidate_runtime_Tc_K=q['temperature_K'], candidate_snapshot_s=q['snapshot_time_s'],
        constructor_Tc_is_not_runtime_Tc=True, compared_selected_fields=rows,
        selected_difference_count=sum(not r['equal_in_selected_coordinate'] for r in rows),
        full_physical_family_equivalence_established=False,
        all_parameter_fields_or_source_implementations_compared=False,
        options_only_read=True, source_states_loaded_into_simulation=False, simulation_executed=False,
        C200_gap_attribution_from_independent_family_authorized=False,
        six_factor_coupled_sensitivity_completed=False, production_recovery_allowed=False)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(record, indent=2, allow_nan=False)+'\n', encoding='utf-8', newline='\n')
    return dict(output_sha256=sha256(output), differences=[r for r in rows if not r['equal_in_selected_coordinate']],
                frozen_C200_hashes_pass=True, full_family_equivalence_established=False)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('repo', 'qualification', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    print(json.dumps(bridge(**vars(parser.parse_args())), indent=2))
