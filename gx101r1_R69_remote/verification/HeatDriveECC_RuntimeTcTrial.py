"""Versioned temperature intervention scope; never changes packet physics gates."""
import math


def validate_trial(t):
    source, target = t['source_Tc_K'], t['candidate_Tc_K']
    if not all(type(v) in (int, float) and math.isfinite(v) for v in (source, target)):
        raise ValueError('Finite scalar temperatures required')
    if t['schema'] == 'heatdrive_ecc_runtime_Tc_intervention_v1':
        if source != 276.95 or abs(target-source) > .1+1e-12:
            raise ValueError('The original compatibility probe stays within 0.1 K')
    elif t['schema'] == 'heatdrive_ecc_runtime_Tc_intervention_v2':
        p = t['search_policy']
        if (p != dict(schema='heatdrive_ecc_runtime_Tc_bounded_search_v1', minimum_Tc_K=255.05,
                maximum_Tc_K=393.15, maximum_step_K=2, fluid_minimum_K=255.05, fluid_maximum_K=393.15,
                source_public_periodic_pass=True, source_target_precision_pass=True) or
                p['source_public_periodic_pass'] is not True or p['source_target_precision_pass'] is not True or
                not 255.05 <= source <= 393.15 or not 255.05 <= target <= 393.15 or
                abs(target-source) > 2+1e-12 or t['transition_time_s'] < 520):
            raise ValueError('Search steps require a qualified current source, declared domain and at most 2 K')
    else:
        raise ValueError('Unknown runtime intervention schema')
    if (abs(target-source) <= .001 or t['minimum_transition_cycles'] != 12 or
            t['only_runtime_temperature_variable_changed'] is not True or
            t['source_state_edited'] is not False or t['old_model_OP_imported'] is not False):
        raise ValueError('A real external step must preserve the complete inherited state')
