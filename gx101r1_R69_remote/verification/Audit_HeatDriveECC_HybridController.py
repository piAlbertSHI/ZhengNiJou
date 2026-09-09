"""Independent sampled equivalence and event-coverage audit for split lag state."""
import argparse
import json
from pathlib import Path
import h5py
from Audit_HeatDriveECC_PSControllerEquivalence import metrics, read, sha256


def audit(repo):
    root = repo/'outputs_storage_audit/hybrid_controller_equivalence_20260910'
    path = root/'controller_equivalence.json'; r = read(path)
    source = repo/'verification/simscape_sma_hybrid/+ecc_sma_hybrid/pressure_controller.ssc'
    raw, public = root/'paired_observations.mat', root/'paired_public_traces.mat'
    if (r['execution_commit'] != 'dc07bc24d8deafa00746ff5a0058fa7c202bbf4c' or not r['collection_pass']
            or not r['external_lag_requested'] or r['reference_input_gated_during_reset']
            or r['production_recovery_allowed'] or r['coupled_model_tested']
            or r['component_sha256'] != sha256(source) or r['observations_sha256'] != sha256(raw)
            or r['public_traces_sha256'] != sha256(public)):
        raise ValueError('Invalid hybrid experiment provenance')
    contract = r['external_lag_contract']
    expected = dict(candidate_path='ecc_sma_controller_equivalence/CandidateLag',
                    reference_path='ecc_sma_controller_equivalence/Lag', numerator='1', denominator='[.002 1]',
                    same_reference_state_used=False, additional_lag_state_added=False,
                    converter_filtering='provide', provided_derivatives='0')
    if contract != expected:
        raise ValueError('Original lag equation or independent state comparison changed')
    with h5py.File(public) as f:
        t = f['time_s'][...].ravel(); v = f['values'][...].T
        origin = ''.join(chr(int(x)) for x in f['source_sha256'][...].ravel())
        if origin != r['observations_sha256']:
            raise ValueError('Portable export origin changed')
    result = metrics(t,v)
    if result['maximum_absolute_errors'] != r['maximum_absolute_errors']:
        raise ValueError('Reported error differs from public samples')
    if not all(result[k] for k in ('equivalence_pass','all_limits_exercised','reset_hold_pass')):
        raise ValueError('Equivalence or event coverage failed')
    files = [path,source,raw,public,root/'component_build/ecc_sma_hybrid_lib.slx']
    result.update(evidence_audit_pass=True, isolated_equivalence_pass=True,
                  coupled_model_tested=False, production_recovery_allowed=False,
                  instantaneous_switch_derivative_verified=False, controller_state_import_allowed=False,
                  input_sha256={str(p.relative_to(repo)):sha256(p) for p in files})
    return result


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True)
    args=p.parse_args();result=audit(Path(__file__).resolve().parents[1])
    with args.output.open('x',encoding='utf-8') as f:
        f.write(json.dumps(result,indent=2,allow_nan=False)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='input_sha256'},indent=2))
