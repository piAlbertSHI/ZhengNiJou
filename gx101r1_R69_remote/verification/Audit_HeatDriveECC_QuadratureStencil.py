"""Independent Decimal Lagrange integration of the worst Simpson stencil."""
from decimal import Decimal, localcontext
import json
from pathlib import Path
import h5py
import numpy as np
from scipy.integrate import cumulative_simpson
from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def exact_stencil(t, y, side):
    if len(t)!=3 or len(y)!=3 or side not in (0,1):
        raise ValueError('Require three samples and one subinterval')
    with localcontext() as ctx:
        ctx.prec=80
        x=[Decimal.from_float(float(v)) for v in t]
        z=[v-x[0] for v in x]
        if not z[0]<z[1]<z[2]:raise ValueError('Nonincreasing stencil')
        values=[Decimal.from_float(float(v)) for v in y]
        a,b=z[side:side+2];weights=[]
        for i in range(3):
            j,k=[n for n in range(3) if n!=i]
            def primitive(u):
                return u**3/3-(z[j]+z[k])*u**2/2+z[j]*z[k]*u
            weights.append((primitive(b)-primitive(a))/((z[i]-z[j])*(z[i]-z[k])))
        integral=sum(w*v for w,v in zip(weights,values))
        return dict(integral_decimal=str(integral),weights_s=[str(w) for w in weights],
                    absolute_weight_amplification=float(sum(abs(w) for w in weights)/(b-a)))


def worst(t,y):
    cumulative=cumulative_simpson(y,x=t,initial=0)
    pieces=np.diff(cumulative)
    trap=np.diff(t)*(y[:-1]+y[1:])/2
    i=int(np.argmax(abs(pieces-trap)))
    start=i if i%2==0 and i<len(t)-2 else i-1
    side=i-start
    proof=exact_stencil(t[start:start+3],y[start:start+3],side)
    independent=float(proof['integral_decimal'])
    return dict(interval_index=i,stencil_time_s=t[start:start+3].tolist(),
                stencil_values=y[start:start+3].tolist(),side=side,
                scipy_increment=float(pieces[i]),trapezoid_increment=float(trap[i]),
                scipy_vs_decimal_abs=abs(float(pieces[i])-independent),
                decimal_vs_trapezoid_abs=abs(independent-float(trap[i])),**proof)


def build(repo):
    folder=repo/'outputs_storage_audit/nonlinear_ramp_joint_delay_20260911'
    raw=folder/'failed_public_observations.mat'
    r=json.loads((folder/'compiled_states_inspection.json').read_text(encoding='utf-8'))
    result=[]
    with h5py.File(raw) as f:
        rows=named_rows(f,f['native'])
        for c in r['nonlinear_inventory_contract']['components']:
            p=c['block_path'];t=rows[p,'stored_mass']['time_s'][()].ravel()
            def get(n,u):
                row=rows[p,n]
                assert np.array_equal(row['time_s'][()].ravel(),t)
                return scalar_series(row,u)
            mf=get('mdot_A','kg/s');q=get('Phi_A','W')+get('Q_H','W')
            if c['kind']=='chamber':mf=mf+get('mdot_B','kg/s');q=q+get('Phi_B','W')
            for label,mask in [('full_prefix',np.ones(t.shape,dtype=bool)),('post_original_event',t>=.1)]:
                for name,y in [('mass_flow',mf),('power',q)]:
                    result.append(dict(block_path=p,window=label,quantity=name,**worst(t[mask],y[mask])))
    return dict(raw_sha256=sha256(raw),decimal_precision=80,stencils=result,
                data_modified=False,quadrature_convergence_verified=False,production_recovery_allowed=False)


if __name__=='__main__':
    repo=Path(__file__).resolve().parents[1]
    out=repo/'outputs_storage_audit/joint_delay_quadrature_stencils_20260911'
    if out.exists():raise FileExistsError('Never overwrite evidence')
    result=build(repo);out.mkdir()
    (out/'stencils.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps(dict(stencils=len(result['stencils']),
        max_weight_amplification=max(x['absolute_weight_amplification'] for x in result['stencils']),
        max_scipy_decimal_difference=max(x['scipy_vs_decimal_abs'] for x in result['stencils'])),indent=2))
