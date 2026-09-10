"""Local inventory balances on the exported failed prefix, never a run pass."""
import json
from pathlib import Path
import h5py
import numpy as np
from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_HeldIntervalBalance import balance
from Audit_HeatDriveECC_PressureDelayFailure import build as evidence
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def build(repo):
    proof=evidence(repo, joint=True)
    folder=repo/'outputs_storage_audit/nonlinear_ramp_joint_delay_20260911'
    record=folder/'compiled_states_inspection.json'
    r=json.loads(record.read_text(encoding='utf-8'))
    raw=folder/'failed_public_observations.mat'
    results=[]
    with h5py.File(raw) as f:
        rows=named_rows(f,f['native'])
        for c in r['nonlinear_inventory_contract']['components']:
            p=c['block_path']
            t=rows[p,'stored_mass']['time_s'][()].ravel()
            def get(name,unit):
                row=rows[p,name]
                assert np.array_equal(row['time_s'][()].ravel(),t)
                return scalar_series(row,unit)
            m=get('stored_mass','kg');e=get('stored_energy','J')
            mf=get('mdot_A','kg/s');q=get('Phi_A','W')+get('Q_H','W')
            if c['kind']=='chamber':
                mf=mf+get('mdot_B','kg/s');q=q+get('Phi_B','W')
            assert t[0]==0 and .1<t[-1]<.12
            for label,keep in [('full_exported_prefix',np.ones(t.shape,dtype=bool)),
                               ('post_original_event',t>=.1)]:
                tt=t[keep]
                assert len(tt)>2
                results.append(dict(block_path=p,window=label,observed_interval_s=[float(tt[0]),float(tt[-1])],
                    **balance(tt,m[keep],e[keep],mf[keep],q[keep],interval=(tt[0],tt[-1]))))
    assert len(results)==12
    return dict(schema='heatdrive_ecc_joint_delay_balance_v1',
                record_sha256=sha256(record),raw_sha256=sha256(raw),
                evidence_audit_pass=proof['failure_evidence_audit_pass'],
                passing_windows=sum(x['mass_closure_pass'] and x['energy_closure_pass'] for x in results),
                audited_windows=len(results),local_balances=results,
                simulation_pass=False,full_device_first_law_verified=False,
                quadrature_convergence_verified=False,production_recovery_allowed=False)


if __name__=='__main__':
    repo=Path(__file__).resolve().parents[1]
    out=repo/'outputs_storage_audit/joint_delay_balance_20260911'
    if out.exists():raise FileExistsError('Never overwrite evidence')
    result=build(repo);out.mkdir()
    (out/'joint_delay_balance.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps(result,indent=2))
