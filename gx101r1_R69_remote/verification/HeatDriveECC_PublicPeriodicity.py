"""Read-only reconstruction of the six predicates in Evaluate_HeatDriveECC_Periodicity."""
import math


PUBLIC_PREDICATES=(
    ('Endpoint T','last_cycle_endpoint_drift_K','periodic_endpoint_limit_K'),
    ('Same-phase T P99','last_cycle_same_phase_temperature_p99_drift_K','periodic_same_phase_temperature_p99_limit_K'),
    ('Same-phase T RMS','last_cycle_same_phase_temperature_rms_drift_K','periodic_same_phase_temperature_rms_limit_K'),
    ('Phase extrema','last_cycle_phase_drift','periodic_phase_limit'),
    ('Same-phase phase P99','last_cycle_same_phase_phase_p99_drift','periodic_same_phase_phase_p99_limit'),
    ('Same-phase phase RMS','last_cycle_same_phase_phase_rms_drift','periodic_same_phase_phase_rms_limit'))


def audit_public_statistics(s):
    rows=[]
    for label,field,limit_field in PUBLIC_PREDICATES:
        value,limit=s[field],s[limit_field]
        if not math.isfinite(value) or not math.isfinite(limit) or value<0 or limit<=0:
            raise ValueError('Invalid recorded public criterion')
        rows.append(dict(label=label,field=field,value=value,limit=limit,pass_=value<=limit))
    recomputed=s['periodic_window_cycles']>=10 and all(r['pass_'] for r in rows)
    if recomputed is not s['periodic_steady_state']:
        raise ValueError('Recorded public flag disagrees with the original six predicates')
    return dict(original_public_flag=s['periodic_steady_state'],six_predicates_recomputed=True,predicates=rows,
        diagnostic_only_fields=['last_cycle_same_phase_temperature_drift_K','last_cycle_same_phase_phase_drift'],
        thresholds_changed=False,full_internal_state_periodicity_claim=False)
