"""Variable-step inventory/flux diagnostics for the pre-switch held interval."""
import numpy as np
from scipy.integrate import cumulative_trapezoid

STOP_S = .04
MASS_LIMIT_KG = 1e-15
ENERGY_LIMIT_J = 1e-8


def balance(time, mass, energy, mass_flow, power):
    t,m,e,f,q=[np.asarray(a,dtype=float) for a in (time,mass,energy,mass_flow,power)]
    if (t.ndim!=1 or len(t)<2 or any(a.shape!=t.shape for a in (m,e,f,q)) or
            not np.isfinite([t,m,e,f,q]).all() or t[0]!=0 or t[-1]!=STOP_S or
            np.any(np.diff(t)<=0) or np.any(m<=0)):
        raise ValueError('Require complete, aligned, finite actual variable-step history')
    dm=m-m[0];de=e-e[0]
    mf=cumulative_trapezoid(f,t,initial=0);qe=cumulative_trapezoid(q,t,initial=0)
    rm=dm-mf;re=de-qe
    # Quadrature comparison is reported separately; no BE identity is assumed for ode15s.
    right_m=np.r_[0,np.cumsum(f[1:]*np.diff(t))];right_e=np.r_[0,np.cumsum(q[1:]*np.diff(t))]
    return dict(sample_count=len(t),mass_endpoint_change_kg=float(dm[-1]),energy_endpoint_change_J=float(de[-1]),
                integrated_mass_input_kg=float(mf[-1]),integrated_energy_input_J=float(qe[-1]),
                mass_max_abs_residual_kg=float(abs(rm).max()),energy_max_abs_residual_J=float(abs(re).max()),
                mass_limit_kg=MASS_LIMIT_KG,energy_limit_J=ENERGY_LIMIT_J,
                mass_closure_pass=bool(np.all(abs(rm)<=MASS_LIMIT_KG)),energy_closure_pass=bool(np.all(abs(re)<=ENERGY_LIMIT_J)),
                right_vs_trapezoid_mass_max_kg=float(abs(right_m-mf).max()),
                right_vs_trapezoid_energy_max_J=float(abs(right_e-qe).max()),
                integral_scheme='trapezoid on every actual variable-step sample',
                quadrature_convergence_verified=False)


def check_held_contract(c):
    until=c['constant_interval_end_exclusive_s']
    if (c['allowed_stop_time_s']!=STOP_S or not abs(until-.05)<=4*np.spacing(.05) or not STOP_S<until
            or c['derivative_source']!='heatdrive_ecc_coupled_se21/ColdHeldPressureDerivative'
            or c['first_derivative_MPa_s']!=0 or c['feedback_enable']!=0 or c['reset_held']!=1
            or c['full_cycle_derivative_verified'] or c['production_recovery_allowed']):
        raise ValueError('Not the bounded constant-pressure interval')
    if len(c['commands'])!=3:
        raise ValueError('Missing command proof')
    for row,value,mode in zip(c['commands'],[-1e-6,0,1],['on','off','off']):
        time=row['time_s']
        if (len(time)!=2 or time[0]!=0 or not abs(time[1]-.05)<=4*np.spacing(.05) or not STOP_S<time[1]
                or row['values']!=[value,value] or row['interpolate']!=mode):
            raise ValueError('A command changes within the held interval')
