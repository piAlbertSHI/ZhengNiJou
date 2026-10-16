"""Independent checks for the declared six-factor cold comparison, never a recovery grant."""
from pathlib import Path
import json
import math

import h5py
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field


LEVELS = np.array([[-1,-1,-1,-1,-1,-1],[-1,-1,-1,1,1,1],[-1,1,1,-1,-1,1],[-1,1,1,1,1,-1],
                   [1,-1,1,-1,1,-1],[1,-1,1,1,-1,1],[1,1,-1,-1,1,1],[1,1,-1,1,-1,-1]])
FRACTIONS = np.array([.05,.05,.10,.10,.03,.05])
NAMES = ('UA_multiplier','endpoint_capacity_multiplier','SE_buffer_multiplier','fluid_inventory_multiplier',
         'regenerator_utilization_multiplier','latent_heat_multiplier')
UA = ('UA_sma_shex_W_per_K','UA_sma_the_W_per_K','UA_se_the_W_per_K','UA_se_chex_W_per_K',
      'sma_pipe_Nu','se_pipe_Nu','se_natural_convection_UA_W_per_K','se_natural_thermal_gate_G_W_per_K',
      'endpoint_UA_sma_shex_W_per_K','endpoint_UA_sma_the_W_per_K','endpoint_UA_se_the_W_per_K',
      'endpoint_UA_se_chex_W_per_K','boundary_UA_shex_W_per_K','boundary_UA_the_W_per_K','boundary_UA_chex_W_per_K')
FIELD_FACTORS = {**{'branch.'+n:0 for n in UA},
    **{'system.'+n:1 for n in ('shex_sink_C_J_per_K','hot_sink_C_J_per_K','cold_sink_C_J_per_K')},
    'system.se_buffer_volume_m3':2,'branch.sma_pump_manifold_volume_m3':3,
    **{'branch.'+n:4 for n in ('m_dot_kg_per_s','m_dot_se_the_kg_per_s','m_dot_se_chex_kg_per_s')},
    **{'material.'+m+'.'+n:5 for m in ('SMA','SE') for n in ('Delta_h_J_per_kg','Delta_s0_J_per_kgK')}}


def design(row):
    index = row['run_index']
    if type(index) not in (int, float) or int(index) != index or not 0 <= index <= 8:
        raise ValueError('Unknown L8 case')
    levels = np.zeros(6) if index == 0 else LEVELS[int(index)-1]
    if not np.array_equal(row['levels'], levels) or not np.array_equal(row['fractions'], FRACTIONS):
        raise ValueError('Changed orthogonal design or factor range')
    multipliers = 1+levels*FRACTIONS
    if any(not math.isclose(row[n], float(v), rel_tol=1e-12, abs_tol=1e-12) for n,v in zip(NAMES,multipliers)):
        raise ValueError('Factor multiplier does not match declared level')
    return multipliers


def audit_case(packet):
    root = packet/'native'
    c = json.loads((root/'sensitivity_case_contract.json').read_text(encoding='utf-8-sig'))
    multipliers = design(c['design'])
    rows = c['parameters']
    if (c['schema'] != 'heatdrive_ecc_runtime_sensitivity_cold_case_v1' or c['fixed_Tc_K'] != 276.95 or
            c['source_state_imported'] or c['C200_gap_attribution_authorized'] or c['orthogonal_effects_evaluated'] or
            c['production_recovery_allowed'] or c['original_scientific_thresholds_changed'] or
            len(rows) != len(FIELD_FACTORS) or {r['field'] for r in rows} != set(FIELD_FACTORS)):
        raise ValueError('Incomplete or wrongly scoped cold factor contract')
    qpath = Path(c['source_qualification_path'])
    if sha256(qpath) != c['source_qualification_sha256']:
        raise ValueError('Changed constructor parameter reference')
    q = json.loads(qpath.read_text(encoding='utf-8-sig'))
    original = Path(q['source_packet_root'])/'native/configuration.mat'
    if (q['schema'] != 'heatdrive_ecc_runtime_Tc_candidate_endpoint_v1' or
            not q['all_original_packet_mechanism_flow_phase_energy_gates_pass'] or not q['original_public_thermal_periodic_pass'] or
            q['source_state_edited'] or q['production_recovery_allowed'] or
            sha256(original) != c['parameter_source_configuration_sha256'] or
            not any(Path(r['path']) == original and r['sha256'] == c['parameter_source_configuration_sha256'] for r in q['files']) or
            sha256(Path(c['fresh_native_source_path'])) != c['fresh_native_source_sha256']):
        raise ValueError('Changed source construction parameters')
    with h5py.File(original) as a, h5py.File(root/'configuration.mat') as b:
        for row in rows:
            field = row['field'];key = field.replace('.', '/')
            before = float(a['plant_build_options/'+key][0,0]);after = float(b['options/'+key][0,0])
            target = before*multipliers[FIELD_FACTORS[field]]
            if not all(math.isclose(x,y,rel_tol=1e-12,abs_tol=1e-12) for x,y in
                       ((before,row['before']),(after,row['after']),(after,target))):
                raise ValueError('A declared factor differs from actual stored construction: '+field)
        if not bool(b['options/validation/sensitivity_mode'][0,0]) or float(b['options/validation/mechanism_gate_start_cycle'][0,0]) != 1:
            raise ValueError('Cold factor scope was not installed')
        declared = {text_field(b[r]) for r in b['options/validation/sensitivity_declared_transition_fields'][:].reshape(-1)}
        permitted = {text_field(b[r]) for r in b['options/simulation/checkpoint_transition_fields'][:].reshape(-1)}
        if declared != set(FIELD_FACTORS) or permitted != declared:
            raise ValueError('Sensitivity declarations do not match the original mechanism contract')
    return dict(case_index=c['design']['run_index'], independently_checked_parameter_fields=len(rows),
                all_declared_parameters_match=True, steady_sensitivity_response_qualified=False)
