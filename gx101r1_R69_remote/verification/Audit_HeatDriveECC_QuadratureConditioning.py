"""Test offset invariance and constant exactness on the unchanged export grid."""
import json
from pathlib import Path
import h5py
import numpy as np
import scipy
from scipy.integrate import cumulative_simpson, cumulative_trapezoid
from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def diagnose(t, y):
    t,y=np.asarray(t,dtype=float),np.asarray(y,dtype=float)
    if t.ndim!=1 or len(t)<3 or t.shape!=y.shape or not np.isfinite([t,y]).all() or np.any(np.diff(t)<=0):
        raise ValueError('Require aligned finite increasing samples')
    h=np.diff(t);ratios=np.maximum(h[:-1]/h[1:],h[1:]/h[:-1])
    one=cumulative_simpson(np.ones_like(t),x=t,initial=0)
    direct=cumulative_simpson(y,x=t,initial=0)
    centered=cumulative_simpson(y-y[0],x=t,initial=0)+y[0]*(t-t[0])
    trap=cumulative_trapezoid(y,t,initial=0)
    return dict(sample_count=len(t),min_step_s=float(h.min()),max_step_s=float(h.max()),
                max_adjacent_step_ratio=float(ratios.max()),
                constant_simpson_max_error_s=float(np.max(abs(one-(t-t[0])))),
                simpson_offset_invariance_error=float(np.max(abs(direct-centered))),
                centered_simpson_vs_trapezoid=float(np.max(abs(centered-trap))),
                direct_simpson_vs_trapezoid=float(np.max(abs(direct-trap))))


def build(repo):
    folder=repo/'outputs_storage_audit/nonlinear_ramp_joint_delay_20260911'
    raw=folder/'failed_public_observations.mat'
    r=json.loads((folder/'compiled_states_inspection.json').read_text(encoding='utf-8'))
    results=[]
    with h5py.File(raw) as f:
        rows=named_rows(f,f['native'])
        for c in r['nonlinear_inventory_contract']['components']:
            p=c['block_path'];t=rows[p,'stored_mass']['time_s'][()].ravel()
            def get(n,u):
                row=rows[p,n]
                assert np.array_equal(row['time_s'][()].ravel(),t)
                return scalar_series(row,u)
            mf=get('mdot_A','kg/s');q=get('Phi_A','W')+get('Q_H','W')
            if c['kind']=='chamber':
                mf=mf+get('mdot_B','kg/s');q=q+get('Phi_B','W')
            for label,mask in [('full_prefix',np.ones(t.shape,dtype=bool)),('post_original_event',t>=.1)]:
                for name,y,unit in [('mass_flow',mf,'kg'),('power',q,'J')]:
                    results.append(dict(block_path=p,window=label,quantity=name,integral_unit=unit,
                                        **diagnose(t[mask],y[mask])))
    return dict(scipy_version=scipy.__version__,raw_sha256=sha256(raw),results=results,
                original_data_modified=False,physical_gate_changed=False,
                quadrature_convergence_verified=False,production_recovery_allowed=False)


if __name__=='__main__':
    repo=Path(__file__).resolve().parents[1]
    out=repo/'outputs_storage_audit/joint_delay_quadrature_conditioning_20260911'
    if out.exists():raise FileExistsError('Never overwrite evidence')
    result=build(repo);out.mkdir()
    (out/'conditioning.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps(dict(scipy_version=result['scipy_version'],cases=len(result['results']),
        max_step_ratio=max(x['max_adjacent_step_ratio'] for x in result['results']),
        constant_max_error_s=max(x['constant_simpson_max_error_s'] for x in result['results']),
        max_mass_offset_error_kg=max(x['simpson_offset_invariance_error'] for x in result['results'] if x['quantity']=='mass_flow'),
        max_energy_offset_error_J=max(x['simpson_offset_invariance_error'] for x in result['results'] if x['quantity']=='power')),indent=2))
